#!/bin/bash

# =============================================================================
# GeuseMaker - AWS Deployment Automation
# =============================================================================
# This script automates the complete deployment of the AI starter kit on AWS
# Features: EFS setup, GPU instances, cost optimization, monitoring
# Intelligent AMI and Instance Selection: Automatically selects best price/performance
# Deep Learning AMIs: Pre-configured NVIDIA drivers, Docker GPU runtime, CUDA toolkit
# Cost Optimization: 70% savings with spot instances + intelligent configuration selection
# =============================================================================

# Check if running under bash (required for associative arrays)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash to run properly."
    echo "Please run: bash $0 $*"
    echo "Or make the script executable and ensure it uses the bash shebang."
    exit 1
fi

# =============================================================================
# CLEANUP ON FAILURE HANDLER
# =============================================================================

# Global flag to track if cleanup should run
CLEANUP_ON_FAILURE="${CLEANUP_ON_FAILURE:-true}"
RESOURCES_CREATED=false
STACK_NAME=""

cleanup_on_failure() {
    local exit_code=$?
    if [ "$CLEANUP_ON_FAILURE" = "true" ] && [ "$RESOURCES_CREATED" = "true" ] && [ $exit_code -ne 0 ] && [ -n "$STACK_NAME" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error "🚨 Deployment failed! Running automatic cleanup for stack: $STACK_NAME"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Get script directory
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        # Use cleanup script if available
        if [ -f "$script_dir/cleanup-stack.sh" ]; then
            log "Using cleanup script to remove resources..."
            "$script_dir/cleanup-stack.sh" "$STACK_NAME" || true
        else
            log "Running manual cleanup..."
            # Basic manual cleanup
            aws ec2 describe-instances --filters "Name=tag:Stack,Values=$STACK_NAME" --query 'Reservations[].Instances[].[InstanceId]' --output text | while read -r instance_id; do
                if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                    aws ec2 terminate-instances --instance-ids "$instance_id" --region "${AWS_REGION:-us-east-1}" || true
                    log "Terminated instance: $instance_id"
                fi
            done
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warning "💡 To disable automatic cleanup, set CLEANUP_ON_FAILURE=false"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Register cleanup handler
trap cleanup_on_failure EXIT

# Note: Converted to work with bash 3.2+ (compatible with macOS default bash)

set -euo pipefail

# Load security validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/security-validation.sh" ]]; then
    source "$SCRIPT_DIR/security-validation.sh"
else
    echo "Warning: Security validation library not found at $SCRIPT_DIR/security-validation.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-auto}"  # Changed to auto-selection
MAX_SPOT_PRICE="${MAX_SPOT_PRICE:-2.00}"  # Increased for G5 instances
KEY_NAME="${KEY_NAME:-GeuseMaker-key}"
STACK_NAME="${STACK_NAME:-GeuseMaker}"
PROJECT_NAME="${PROJECT_NAME:-GeuseMaker}"
ENABLE_CROSS_REGION="${ENABLE_CROSS_REGION:-false}"  # Cross-region analysis
USE_LATEST_IMAGES="${USE_LATEST_IMAGES:-true}"  # Use latest Docker images by default
SETUP_ALB="${SETUP_ALB:-false}"  # Setup Application Load Balancer
SETUP_CLOUDFRONT="${SETUP_CLOUDFRONT:-false}"  # Setup CloudFront distribution

# =============================================================================
# GPU INSTANCE AND AMI CONFIGURATION MATRIX
# =============================================================================

# Dynamic AMI Discovery System
# =============================================================================
# Replaces hardcoded AMI IDs with intelligent discovery based on:
# - Architecture (x86_64/arm64) compatibility with instance type
# - Latest AWS Deep Learning AMI with GPU support
# - Regional availability and validation

# Cache for AMI discovery to avoid repeated API calls
# AMI_CACHE will be handled with string concatenation for bash 3.2 compatibility

discover_latest_deep_learning_ami() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    local architecture
    
    # Determine architecture based on instance type
    case "$instance_type" in
        g4dn.*|g4ad.*|g5.*|p3.*|p4.*) architecture="x86_64" ;;
        g5g.*|c6g.*|c7g.*|m6g.*|m7g.*|r6g.*|r7g.*) architecture="arm64" ;;
        *) 
            error "Unsupported instance type for GPU workloads: $instance_type"
            return 1
            ;;
    esac
    
    # Check cache first
    local cache_key="${instance_type}_${region}_${architecture}"
    if [[ -n "${AMI_CACHE[$cache_key]:-}" ]]; then
        echo "${AMI_CACHE[$cache_key]}"
        return 0
    fi
    
    log "🔍 Discovering latest Deep Learning AMI for $instance_type ($architecture) in $region..."
    
    # Define AMI name patterns based on architecture and requirements
    local ami_name_patterns=()
    if [[ "$architecture" == "x86_64" ]]; then
        ami_name_patterns=(
            "Deep Learning AMI GPU PyTorch*Ubuntu*"
            "Deep Learning AMI GPU TensorFlow*Ubuntu*"
            "Deep Learning AMI (Ubuntu*)*GPU*"
            "aws-deep-learning-ami-gpu-*ubuntu*"
        )
    else
        ami_name_patterns=(
            "Deep Learning AMI GPU PyTorch*Ubuntu*ARM64*"
            "Deep Learning AMI GPU*ARM64*Ubuntu*"
            "aws-deep-learning-ami-gpu-*ubuntu*arm64*"
        )
    fi
    
    local best_ami=""
    local best_date=""
    
    # Try each AMI name pattern until we find a suitable AMI
    for pattern in "${ami_name_patterns[@]}"; do
        info "  Searching for pattern: $pattern"
        
        # Query AWS for AMIs matching the pattern
        local ami_info=$(aws ec2 describe-images \
            --region "$region" \
            --owners amazon \
            --filters \
                "Name=name,Values=$pattern" \
                "Name=architecture,Values=$architecture" \
                "Name=virtualization-type,Values=hvm" \
                "Name=root-device-type,Values=ebs" \
                "Name=state,Values=available" \
            --query 'Images[*].[ImageId,Name,CreationDate,Description]' \
            --output text 2>/dev/null || continue)
        
        if [[ -n "$ami_info" ]]; then
            # Parse results and find the most recent AMI
            while IFS=$'\t' read -r ami_id ami_name creation_date description; do
                # Validate this is a proper GPU-enabled Deep Learning AMI
                if [[ "$ami_name" == *"GPU"* ]] && [[ "$description" == *"GPU"* || "$description" == *"CUDA"* || "$description" == *"NVIDIA"* ]]; then
                    # Compare dates to find the newest
                    if [[ -z "$best_date" ]] || [[ "$creation_date" > "$best_date" ]]; then
                        best_ami="$ami_id"
                        best_date="$creation_date"
                        info "  ✓ Found candidate: $ami_id ($ami_name, $creation_date)"
                    fi
                fi
            done <<< "$ami_info"
            
            # If we found a good AMI with this pattern, we can stop searching
            if [[ -n "$best_ami" ]]; then
                break
            fi
        fi
    done
    
    if [[ -z "$best_ami" ]]; then
        warning "⚠️  No suitable Deep Learning AMI found via automatic discovery"
        
        # Fallback: Use fallback AMI IDs based on region and architecture
        case "${region}_${architecture}" in
            # US East 1 (Virginia) - most comprehensive AMI selection
            "us-east-1_x86_64") best_ami="ami-0c02fb55956c7d316" ;;
            "us-east-1_arm64") best_ami="ami-0c7217cdde317cfec" ;;
            
            # US West 2 (Oregon) - popular for ML workloads
            "us-west-2_x86_64") best_ami="ami-013168dc3850ef002" ;;
            "us-west-2_arm64") best_ami="ami-0c5204531f5e0dc35" ;;
            
            # EU West 1 (Ireland) - European ML hub
            "eu-west-1_x86_64") best_ami="ami-0a8e758f5e873d1c1" ;;
            "eu-west-1_arm64") best_ami="ami-0d71ea30463e0ff8d" ;;
            
            # Asia Pacific (Tokyo) - Asian region option
            "ap-northeast-1_x86_64") best_ami="ami-0bcc04cc58d71a388" ;;
            "ap-northeast-1_arm64") best_ami="ami-0f36dcfcc94112ea1" ;;
            
            *)
                error "❌ No fallback AMI available for region $region with architecture $architecture"
                return 1
                ;;
        esac
        
        warning "🔄 Using fallback AMI: $best_ami"
    fi
    
    # Validate the AMI exists and is available
    if ! verify_ami_availability "$best_ami" "$region"; then
        error "❌ Selected AMI $best_ami is not available in region $region"
        return 1
    fi
    
    # Cache the result
    AMI_CACHE[$cache_key]="$best_ami"
    
    success "✅ Selected AMI: $best_ami (region: $region, arch: $architecture)"
    echo "$best_ami"
    return 0
}

# Enhanced GPU configuration function with dynamic AMI discovery
get_gpu_config() {
    local key="$1"
    local instance_type region
    
    # Parse the key to extract instance type and region info
    case "$key" in
        *_primary|*_secondary)
            # Extract instance type (remove suffix)
            instance_type="${key%_*}"
            ;;
        *)
            # Direct instance type
            instance_type="$key"
            ;;
    esac
    
    # Use current region or default
    region="${AWS_REGION:-us-east-1}"
    
    # Discover and return the appropriate AMI
    discover_latest_deep_learning_ami "$instance_type" "$region"
}

# Instance type specifications
# Function to get instance specs (replaces associative array for bash 3.2 compatibility)
get_instance_specs() {
    local key="$1"
    case "$key" in
        "g4dn.xlarge") echo "4:16:1:T4:Intel:125GB" ;;     # vCPUs:RAM:GPUs:GPU_Type:CPU_Arch:Storage
        "g4dn.2xlarge") echo "8:32:1:T4:Intel:225GB" ;;
        "g5g.xlarge") echo "4:8:1:T4G:ARM:125GB" ;;
        "g5g.2xlarge") echo "8:16:1:T4G:ARM:225GB" ;;
        *) echo "" ;;  # Return empty string for unknown keys
    esac
}

# Performance scoring (higher = better)
# Function to get performance scores (replaces associative array for bash 3.2 compatibility)
get_performance_score() {
    local key="$1"
    case "$key" in
        "g4dn.xlarge") echo "70" ;;
        "g4dn.2xlarge") echo "85" ;;
        "g5g.xlarge") echo "65" ;;      # ARM may have compatibility considerations
        "g5g.2xlarge") echo "80" ;;
        *) echo "0" ;;  # Return 0 for unknown keys
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}" >&2
}

# Enhanced deployment progress tracking with visual indicators
track_deployment_progress() {
    local phase="$1"
    local step="$2"
    local status="$3"  # start, progress, complete, error
    local message="$4"
    local current_step="${5:-0}"
    local total_steps="${6:-10}"
    
    # Define deployment phases
    local phases=(
        "1:Initialization"
        "2:Prerequisites"
        "3:Configuration"
        "4:Infrastructure"
        "5:Instance Launch"
        "6:Connectivity"
        "7:System Setup"
        "8:Application Deploy"
        "9:Validation"
        "10:Completion"
    )
    
    # Progress bar width
    local bar_width=50
    local current_progress=0
    
    # Calculate overall progress based on phase and step
    if [[ "$total_steps" -gt 0 ]]; then
        local phase_weight=$((100 / ${#phases[@]}))
        local phase_progress=$(( (phase - 1) * phase_weight ))
        local step_progress=$(( (current_step * phase_weight) / total_steps ))
        current_progress=$(( phase_progress + step_progress ))
        
        # Cap at 100%
        if [[ "$current_progress" -gt 100 ]]; then
            current_progress=100
        fi
    fi
    
    # Create progress bar
    local filled=$(( (current_progress * bar_width) / 100 ))
    local empty=$(( bar_width - filled ))
    local bar=""
    
    # Build progress bar with colors
    for ((i=0; i<filled; i++)); do
        if [[ "$status" == "error" ]]; then
            bar+="█"
        else
            bar+="█"
        fi
    done
    
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # Status indicator
    local status_icon
    case "$status" in
        "start")     status_icon="🚀" ;;
        "progress")  status_icon="⚙️ " ;;
        "complete")  status_icon="✅" ;;
        "error")     status_icon="❌" ;;
        *)           status_icon="🔄" ;;
    esac
    
    # Color based on status
    local color
    case "$status" in
        "start"|"progress") color="$CYAN" ;;
        "complete")         color="$GREEN" ;;
        "error")           color="$RED" ;;
        *)                 color="$BLUE" ;;
    esac
    
    # Get phase name
    local phase_name="Unknown"
    for phase_info in "${phases[@]}"; do
        local phase_num="${phase_info%:*}"
        local phase_desc="${phase_info#*:}"
        if [[ "$phase_num" == "$phase" ]]; then
            phase_name="$phase_desc"
            break
        fi
    done
    
    # Format timestamp
    local timestamp=$(date +'%H:%M:%S')
    
    # Display progress line
    if [[ "$status" == "error" ]]; then
        echo -e "${RED}[$timestamp] ${status_icon} ${color}[$bar${RED}] ${current_progress}% | Phase $phase: $phase_name${NC}"
        echo -e "${RED}           ❌ ERROR in $step: $message${NC}"
    else
        echo -e "${BLUE}[$timestamp] ${status_icon} ${color}[$bar${BLUE}] ${current_progress}% | Phase $phase: $phase_name${NC}"
        if [[ -n "$message" ]]; then
            echo -e "${BLUE}           📋 $step: $message${NC}"
        fi
    fi
    
    # Add extra spacing for major phase transitions
    if [[ "$status" == "complete" ]] && [[ "$current_step" -eq "$total_steps" ]]; then
        echo
    fi
}

# Wrapper functions for easy progress tracking
track_start() {
    track_deployment_progress "$1" "$2" "start" "$3" "${4:-0}" "${5:-10}"
}

track_progress() {
    track_deployment_progress "$1" "$2" "progress" "$3" "${4:-0}" "${5:-10}"
}

track_complete() {
    track_deployment_progress "$1" "$2" "complete" "$3" "${4:-0}" "${5:-10}"
}

track_error() {
    track_deployment_progress "$1" "$2" "error" "$3" "${4:-0}" "${5:-10}"
}

# Display deployment banner with progress overview
show_deployment_banner() {
    local banner_width=80
    
    echo
    echo -e "${CYAN}$(printf '═%.0s' $(seq 1 $banner_width))${NC}"
    echo -e "${CYAN}║$(printf ' %.0s' $(seq 1 $((($banner_width-40)/2))))🚀 AI STARTER KIT DEPLOYMENT 🚀$(printf ' %.0s' $(seq 1 $((($banner_width-40)/2))))║${NC}"
    echo -e "${CYAN}$(printf '═%.0s' $(seq 1 $banner_width))${NC}"
    echo
    echo -e "${BLUE}Starting intelligent GPU instance deployment with enhanced monitoring...${NC}"
    echo -e "${YELLOW}💡 This deployment includes:${NC}"
    echo -e "${YELLOW}   • Dynamic AMI discovery with latest Deep Learning images${NC}"
    echo -e "${YELLOW}   • 3-phase instance readiness validation${NC}"
    echo -e "${YELLOW}   • Resource-optimized container configuration${NC}"
    echo -e "${YELLOW}   • Real-time progress tracking and error reporting${NC}"
    echo
    echo -e "${CYAN}$(printf '═%.0s' $(seq 1 $banner_width))${NC}"
    echo
}

check_prerequisites() {
    log "🔍 Checking prerequisites for intelligent GPU deployment..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI first."
        error "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker first."
        error "Install: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose not found. Please install Docker Compose first."
        error "Install: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        error "Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html"
        exit 1
    fi
    
    # Check jq for JSON processing (critical for intelligent selection)
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Installing jq for intelligent configuration selection..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install jq || {
                    error "Failed to install jq via Homebrew. Please install it manually."
                    error "Install: brew install jq"
                    exit 1
                }
            else
                error "jq required for intelligent selection but Homebrew not found."
                error "Please install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq || {
                    error "Failed to install jq. Please install it manually."
                    error "Install: sudo apt-get install jq"
                    exit 1
                }
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq || {
                    error "Failed to install jq. Please install it manually."
                    error "Install: sudo yum install jq"
                    exit 1
                }
            else
                error "jq required for intelligent selection. Please install manually."
                error "Install: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        else
            error "jq required for intelligent selection on this platform."
            error "Install: https://stedolan.github.io/jq/download/"
            exit 1
        fi
    fi
    
    # Check bc for price calculations (critical for cost optimization)
    if ! command -v bc &> /dev/null; then
        warning "bc (calculator) not found. Installing bc for price calculations..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install bc || {
                    error "Failed to install bc via Homebrew. Please install it manually."
                    exit 1
                }
            else
                error "bc required for price calculations but Homebrew not found."
                error "Please install bc manually"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y bc || {
                    error "Failed to install bc. Please install it manually."
                    exit 1
                }
            elif command -v yum &> /dev/null; then
                sudo yum install -y bc || {
                    error "Failed to install bc. Please install it manually."
                    exit 1
                }
            fi
        fi
    fi
    
    # Verify AWS region availability
    if ! aws ec2 describe-regions --region-names "$AWS_REGION" &> /dev/null; then
        error "Invalid or inaccessible AWS region: $AWS_REGION"
        error "Please specify a valid region with --region"
        exit 1
    fi
    
    # Get account info for display
    local ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    local CALLER_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null | sed 's/.*\///')
    
    success "✅ Prerequisites check completed"
    info "AWS Account: $ACCOUNT_ID"
    info "Caller: $CALLER_USER"
    info "Region: $AWS_REGION"
    info "Ready for intelligent GPU deployment!"
}

# =============================================================================
# INTELLIGENT AMI AND INSTANCE SELECTION
# =============================================================================

get_instance_type_list() {
    echo "g4dn.xlarge g4dn.2xlarge g5g.xlarge g5g.2xlarge"
}

verify_ami_availability() {
    local ami_id="$1"
    local region="$2"
    
    log "Verifying AMI availability: $ami_id in $region..."
    
    AMI_STATE=$(aws ec2 describe-images \
        --image-ids "$ami_id" \
        --region "$region" \
        --query 'Images[0].State' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$AMI_STATE" == "available" ]]; then
        # Get AMI details
        AMI_INFO=$(aws ec2 describe-images \
            --image-ids "$ami_id" \
            --region "$region" \
            --query 'Images[0].{Name:Name,Description:Description,Architecture:Architecture,CreationDate:CreationDate}' \
            --output json 2>/dev/null)
        
        if [[ -n "$AMI_INFO" && "$AMI_INFO" != "null" ]]; then
            AMI_NAME=$(echo "$AMI_INFO" | jq -r '.Name // "Unknown"')
            AMI_ARCH=$(echo "$AMI_INFO" | jq -r '.Architecture // "Unknown"')
            AMI_DATE=$(echo "$AMI_INFO" | jq -r '.CreationDate // "Unknown"')
            
            success "✓ AMI $ami_id available: $AMI_NAME ($AMI_ARCH)"
            info "  Creation Date: $AMI_DATE"
            return 0
        fi
    fi
    
    warning "✗ AMI $ami_id not available in $region (State: $AMI_STATE)"
    return 1
}

check_instance_type_availability() {
    local instance_type="$1"
    local region="$2"
    
    log "Checking instance type availability: $instance_type in $region..."
    
    AVAILABLE_AZS=$(aws ec2 describe-instance-type-offerings \
        --location-type availability-zone \
        --filters "Name=instance-type,Values=$instance_type" \
        --region "$region" \
        --query 'InstanceTypeOfferings[].Location' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$AVAILABLE_AZS" && "$AVAILABLE_AZS" != "None" ]]; then
        success "✓ $instance_type available in AZs: $AVAILABLE_AZS"
        echo "$AVAILABLE_AZS"
        return 0
    else
        warning "✗ $instance_type not available in $region"
        return 1
    fi
}

get_comprehensive_spot_pricing() {
    local instance_types="$1"
    local region="$2"
    
    log "Analyzing comprehensive spot pricing across all configurations..."
    
    # Create temporary file for pricing data
    local pricing_file=$(mktemp)
    echo "[]" > "$pricing_file"
    
    for instance_type in $instance_types; do
        info "Fetching spot prices for $instance_type..."
        
        # Get recent spot price history with better error handling
        SPOT_DATA=$(aws ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --product-descriptions "Linux/UNIX" \
            --max-items 50 \
            --region "$region" \
            --query 'SpotPrices | sort_by(@, &Timestamp) | reverse(@) | [*] | group_by(@, &AvailabilityZone) | map({instance_type: `'"$instance_type"'`, az: .[0].AvailabilityZone, price: .[0].SpotPrice, timestamp: .[0].Timestamp})' \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$SPOT_DATA" != "[]" && -n "$SPOT_DATA" && "$SPOT_DATA" != "null" ]]; then
            # Validate JSON and merge with existing data
            if echo "$SPOT_DATA" | jq empty 2>/dev/null; then
                jq -s '.[0] + .[1]' "$pricing_file" <(echo "$SPOT_DATA") > "${pricing_file}.tmp"
                mv "${pricing_file}.tmp" "$pricing_file"
            else
                warning "Invalid JSON response for $instance_type pricing data"
            fi
        else
            warning "No spot pricing data available for $instance_type in $region"
            # Add fallback pricing based on typical market rates
            case "$instance_type" in
                "g4dn.xlarge")
                    FALLBACK_PRICE="0.45"
                    ;;
                "g4dn.2xlarge")
                    FALLBACK_PRICE="0.89"
                    ;;
                "g5g.xlarge")
                    FALLBACK_PRICE="0.38"
                    ;;
                "g5g.2xlarge")
                    FALLBACK_PRICE="0.75"
                    ;;
                *)
                    FALLBACK_PRICE="1.00"
                    ;;
            esac
            
            warning "Using fallback pricing estimate: \$$FALLBACK_PRICE/hour for $instance_type"
            FALLBACK_DATA=$(jq -n --arg instance_type "$instance_type" --arg price "$FALLBACK_PRICE" --arg az "${region}a" \
                '[{instance_type: $instance_type, az: $az, price: $price, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%S.000Z"))}]')
            
            jq -s '.[0] + .[1]' "$pricing_file" <(echo "$FALLBACK_DATA") > "${pricing_file}.tmp"
            mv "${pricing_file}.tmp" "$pricing_file"
        fi
    done
    
    # Validate final pricing data
    local final_data=$(cat "$pricing_file")
    if [[ "$final_data" == "[]" || -z "$final_data" ]]; then
        error "No pricing data could be obtained for any instance type"
        rm -f "$pricing_file"
        return 1
    fi
    
    # Output comprehensive pricing data
    cat "$pricing_file"
    rm -f "$pricing_file"
}

analyze_cost_performance_matrix() {
    local pricing_data="$1"
    
    log "Analyzing cost-performance matrix for optimal selection..."
    
    # Validate input pricing data
    if [[ -z "$pricing_data" || "$pricing_data" == "[]" || "$pricing_data" == "null" ]]; then
        error "No pricing data provided for analysis"
        return 1
    fi
    
    # Create comprehensive analysis
    local analysis_file=$(mktemp)
    echo "[]" > "$analysis_file"
    
    for instance_type in $(get_instance_type_list); do
        # Check if we have pricing data for this instance type
        local avg_price=$(echo "$pricing_data" | jq -r --arg type "$instance_type" '
            [.[] | select(.instance_type == $type) | .price | tonumber] | 
            if length > 0 then (add / length) else null end' 2>/dev/null || echo "null")
        
        if [[ "$avg_price" != "null" && -n "$avg_price" && "$avg_price" != "0" ]]; then
            # Get performance score
            local perf_score="$(get_performance_score "$instance_type")"
            
            # Validate performance score
            if [[ -z "$perf_score" || "$perf_score" == "0" ]]; then
                warning "No performance score available for $instance_type, skipping"
                continue
            fi
            
            # Calculate price-performance ratio (higher = better value)
            local price_perf_ratio=$(echo "scale=3; $perf_score / $avg_price" | bc -l 2>/dev/null || echo "0")
            
            # Validate calculation
            if [[ "$price_perf_ratio" == "0" || -z "$price_perf_ratio" ]]; then
                warning "Could not calculate price-performance ratio for $instance_type"
                continue
            fi
            
            # Get instance specifications
            local specs="$(get_instance_specs "$instance_type")"
            if [[ -z "$specs" ]]; then
                warning "No specifications available for $instance_type, skipping"
                continue
            fi
            
            IFS=':' read -r vcpus ram gpus gpu_type cpu_arch storage <<< "$specs"
            
            # Create analysis entry with validation
            local entry=$(jq -n \
                --arg instance_type "$instance_type" \
                --arg avg_price "$avg_price" \
                --arg perf_score "$perf_score" \
                --arg price_perf_ratio "$price_perf_ratio" \
                --arg vcpus "$vcpus" \
                --arg ram "$ram" \
                --arg gpus "$gpus" \
                --arg gpu_type "$gpu_type" \
                --arg cpu_arch "$cpu_arch" \
                --arg storage "$storage" \
                '{
                    instance_type: $instance_type,
                    avg_spot_price: ($avg_price | tonumber),
                    performance_score: ($perf_score | tonumber),
                    price_performance_ratio: ($price_perf_ratio | tonumber),
                    vcpus: ($vcpus | tonumber),
                    ram_gb: ($ram | tonumber),
                    gpus: ($gpus | tonumber),
                    gpu_type: $gpu_type,
                    cpu_architecture: $cpu_arch,
                    storage: $storage
                }' 2>/dev/null)
            
            if [[ -n "$entry" && "$entry" != "null" ]]; then
                # Add to analysis
                jq -s '.[0] + [.[1]]' "$analysis_file" <(echo "$entry") > "${analysis_file}.tmp" 2>/dev/null && \
                mv "${analysis_file}.tmp" "$analysis_file" || {
                    warning "Failed to add $instance_type to analysis"
                }
            fi
        else
            warning "No valid pricing data for $instance_type (price: $avg_price)"
        fi
    done
    
    # Validate we have some analysis data
    local analysis_count=$(jq 'length' "$analysis_file" 2>/dev/null || echo "0")
    if [[ "$analysis_count" == "0" ]]; then
        error "No valid configurations could be analyzed"
        rm -f "$analysis_file"
        return 1
    fi
    
    # Sort by price-performance ratio (descending)
    local sorted_analysis=$(jq 'sort_by(-.price_performance_ratio)' "$analysis_file" 2>/dev/null || echo "[]")
    echo "$sorted_analysis"
    rm -f "$analysis_file"
}

select_optimal_configuration() {
    local max_budget="$1"
    local enable_cross_region="${2:-false}"
    
    log "🤖 Intelligent Configuration Selection Process Starting..."
    log "Budget limit: \$$max_budget/hour"
    log "Cross-region analysis: $enable_cross_region"
    
    # Define regions to analyze
    local regions_to_check=("$AWS_REGION")
    if [[ "$enable_cross_region" == "true" ]]; then
        # Add popular regions with good GPU availability
        regions_to_check=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1" "us-east-2" "eu-central-1")
        info "Cross-region analysis enabled - checking regions: ${regions_to_check[*]}"
    fi
    
    local all_valid_configs=()
    local best_region=""
    local best_config=""
    local best_price="999999"
    
    # Analyze each region
    for region in "${regions_to_check[@]}"; do
        log "Analyzing region: $region"
        
        # Step 1: Check availability of all instance types in this region
        info "Step 1: Checking instance type availability in $region..."
        local available_types=""
        for instance_type in $(get_instance_type_list); do
            if check_instance_type_availability "$instance_type" "$region" >/dev/null 2>&1; then
                available_types="$available_types $instance_type"
            fi
        done
        
        if [[ -z "$available_types" ]]; then
            warning "No GPU instance types available in region $region, skipping"
            continue
        fi
        
        info "Available instance types in $region:$available_types"
        
        # Step 2: Check AMI availability for each configuration in this region
        info "Step 2: Verifying AMI availability for each configuration in $region..."
        local valid_configs=()
        
        for instance_type in $available_types; do
            local primary_ami="$(get_gpu_config "${instance_type}_primary")"
            local secondary_ami="$(get_gpu_config "${instance_type}_secondary")"
            
            if verify_ami_availability "$primary_ami" "$region" >/dev/null 2>&1; then
                valid_configs+=("${instance_type}:${primary_ami}:primary:${region}")
                info "✓ $instance_type with primary AMI $primary_ami in $region"
            elif verify_ami_availability "$secondary_ami" "$region" >/dev/null 2>&1; then
                valid_configs+=("${instance_type}:${secondary_ami}:secondary:${region}")
                info "✓ $instance_type with secondary AMI $secondary_ami in $region"
            else
                warning "✗ $instance_type: No valid AMIs available in $region"
            fi
        done
        
        if [[ ${#valid_configs[@]} -eq 0 ]]; then
            warning "No valid AMI+instance combinations available in $region"
            continue
        fi
        
        # Step 3: Get comprehensive spot pricing for this region
        info "Step 3: Analyzing spot pricing in $region..."
        local pricing_data=$(get_comprehensive_spot_pricing "$available_types" "$region")
        
        if [[ -z "$pricing_data" || "$pricing_data" == "[]" ]]; then
            warning "No pricing data available for $region, skipping"
            continue
        fi
        
        # Step 4: Perform cost-performance analysis for this region
        info "Step 4: Performing cost-performance analysis for $region..."
        local analysis=$(analyze_cost_performance_matrix "$pricing_data")
        
        if [[ -z "$analysis" || "$analysis" == "[]" ]]; then
            warning "No valid analysis results for $region, skipping"
            continue
        fi
        
        # Add region info to configs and find best in this region
        for config in "${valid_configs[@]}"; do
            all_valid_configs+=("$config")
        done
        
        # Find best config in this region within budget
        local region_best_config=$(echo "$analysis" | jq -r --arg budget "$max_budget" '
            [.[] | select(.avg_spot_price <= ($budget | tonumber))] | 
            if length > 0 then 
                sort_by(-.price_performance_ratio)[0] | 
                "\(.instance_type)|\(.avg_spot_price)"
            else 
                empty 
            end')
        
        if [[ -n "$region_best_config" ]]; then
            IFS='|' read -r region_instance region_price <<< "$region_best_config"
            
            # Check if this is better than our current best
            if (( $(echo "$region_price < $best_price" | bc -l 2>/dev/null || echo "0") )); then
                best_price="$region_price"
                best_region="$region"
                
                # Find corresponding AMI for this config
                for config in "${valid_configs[@]}"; do
                    IFS=':' read -r inst ami type reg <<< "$config"
                    if [[ "$inst" == "$region_instance" ]]; then
                        best_config="$region_instance:$ami:$type:$region_price:$region"
                        break
                    fi
                done
            fi
            
            info "Best in $region: $region_instance at \$$region_price/hour"
        fi
    done
    
    # Step 5: Display comprehensive analysis if cross-region enabled
    if [[ "$enable_cross_region" == "true" && ${#all_valid_configs[@]} -gt 0 ]]; then
        info "Step 5: Cross-Region Configuration Analysis:"
        echo ""
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│                      CROSS-REGION COST-PERFORMANCE ANALYSIS                        │${NC}"
        echo -e "${CYAN}├─────────────────┬─────────────┬──────────┬────────────┬─────────────┬─────────────────┤${NC}"
        echo -e "${CYAN}│ Region          │ Best Instance│ Price/hr │ Perf Score │ Architecture│ Availability    │${NC}"
        echo -e "${CYAN}├─────────────────┼─────────────┼──────────┼────────────┼─────────────┼─────────────────┤${NC}"
        
        # Show best option per region
        for region in "${regions_to_check[@]}"; do
            # Find best config for this region
            local region_configs=()
            for config in "${all_valid_configs[@]}"; do
                if [[ "$config" == *":$region" ]]; then
                    region_configs+=("$config")
                fi
            done
            
            if [[ ${#region_configs[@]} -gt 0 ]]; then
                # Get pricing for first available instance in region
                local sample_config="${region_configs[0]}"
                IFS=':' read -r sample_inst sample_ami sample_type sample_region <<< "$sample_config"
                
                local region_pricing=$(get_comprehensive_spot_pricing "$sample_inst" "$region" 2>/dev/null || echo "[]")
                if [[ "$region_pricing" != "[]" ]]; then
                    local region_analysis=$(analyze_cost_performance_matrix "$region_pricing" 2>/dev/null || echo "[]")
                    if [[ "$region_analysis" != "[]" ]]; then
                        local region_best=$(echo "$region_analysis" | jq -r --arg budget "$max_budget" '
                            [.[] | select(.avg_spot_price <= ($budget | tonumber))] | 
                            if length > 0 then 
                                sort_by(-.price_performance_ratio)[0] | 
                                "\(.instance_type)|\(.avg_spot_price)|\(.performance_score)|\(.cpu_architecture)"
                            else 
                                "none|N/A|N/A|N/A"
                            end')
                        
                        IFS='|' read -r r_inst r_price r_perf r_arch <<< "$region_best"
                        local availability="✓ Available"
                        if [[ "$r_inst" == "none" ]]; then
                            availability="✗ Over budget"
                        fi
                        
                        printf "${CYAN}│ %-15s │ %-11s │ %-8s │ %-10s │ %-11s │ %-15s │${NC}\n" \
                            "$region" "$r_inst" "\$${r_price}" "$r_perf" "$r_arch" "$availability"
                    fi
                fi
            else
                printf "${CYAN}│ %-15s │ %-11s │ %-8s │ %-10s │ %-11s │ %-15s │${NC}\n" \
                    "$region" "none" "N/A" "N/A" "N/A" "✗ No capacity"
            fi
        done
        
        echo -e "${CYAN}└─────────────────┴─────────────┴──────────┴────────────┴─────────────┴─────────────────┘${NC}"
        echo ""
    fi
    
    # Step 6: Select final configuration
    if [[ -n "$best_config" ]]; then
        IFS=':' read -r selected_instance selected_ami selected_type selected_price selected_region <<< "$best_config"
        
        success "🎯 OPTIMAL CONFIGURATION SELECTED:"
        info "  Instance Type: $selected_instance"
        info "  AMI: $selected_ami ($selected_type)"
        info "  Region: $selected_region"
        info "  Average Spot Price: \$$selected_price/hour"
        info "  Performance Score: $(get_performance_score "$selected_instance")"
        
        # If different region selected, update global region
        if [[ "$selected_region" != "$AWS_REGION" ]]; then
            warning "Optimal configuration found in different region: $selected_region"
            info "Updating deployment region from $AWS_REGION to $selected_region"
            export AWS_REGION="$selected_region"
        fi
        
        # Export variables for use by other functions - THIS IS THE KEY FIX
        export SELECTED_INSTANCE_TYPE="$selected_instance"
        export SELECTED_AMI="$selected_ami"
        export SELECTED_AMI_TYPE="$selected_type"
        export SELECTED_PRICE="$selected_price"
        export SELECTED_REGION="$selected_region"
        
        # Return the configuration string
        echo "$selected_instance:$selected_ami:$selected_type:$selected_price:$selected_region"
        return 0
        
    else
        error "No configurations available within budget of \$$max_budget/hour"
        
        # Try to suggest alternatives
        if [[ ${#all_valid_configs[@]} -gt 0 ]]; then
            warning "Available configurations exceed budget. Consider:"
            warning "  1. Increase --max-spot-price (current: $max_budget)"
            warning "  2. Try during off-peak hours for better pricing"
            warning "  3. Use on-demand instances instead"
            
            # Show cheapest available option
            local cheapest_found=""
            local cheapest_price="999999"
            
            for region in "${regions_to_check[@]}"; do
                local available_types=""
                for instance_type in $(get_instance_type_list); do
                    if check_instance_type_availability "$instance_type" "$region" >/dev/null 2>&1; then
                        available_types="$available_types $instance_type"
                    fi
                done
                
                if [[ -n "$available_types" ]]; then
                    local pricing_data=$(get_comprehensive_spot_pricing "$available_types" "$region" 2>/dev/null || echo "[]")
                    if [[ "$pricing_data" != "[]" ]]; then
                        local min_price=$(echo "$pricing_data" | jq -r 'min_by(.price | tonumber) | .price' 2>/dev/null || echo "999999")
                        if (( $(echo "$min_price < $cheapest_price" | bc -l 2>/dev/null || echo "0") )); then
                            cheapest_price="$min_price"
                            cheapest_found="$region"
                        fi
                    fi
                fi
            done
            
            if [[ -n "$cheapest_found" ]]; then
                info "Cheapest option found: \$$cheapest_price/hour in $cheapest_found"
                info "Suggested budget: \$$(echo "scale=2; $cheapest_price * 1.2" | bc -l)/hour"
            fi
        fi
        
        return 1
    fi
}

# =============================================================================
# ENHANCED INTELLIGENT INSTANCE SELECTION
# =============================================================================

get_multi_az_spot_prices() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    log "🔍 Getting spot prices across all AZs for $instance_type in $region..."
    
    # Get all availability zones in the region
    local azs=$(aws ec2 describe-availability-zones \
        --region "$region" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$azs" ]]; then
        warning "No availability zones found in $region"
        echo "[]"
        return 1
    fi
    
    local pricing_data="[]"
    local temp_file=$(mktemp)
    
    for az in $azs; do
        info "  Checking spot prices in $az..."
        
        # Get latest spot price for this AZ
        local spot_data=$(aws ec2 describe-spot-price-history \
            --region "$region" \
            --instance-types "$instance_type" \
            --product-descriptions "Linux/UNIX" \
            --availability-zone "$az" \
            --max-items 5 \
            --query 'SpotPrices[0].[SpotPrice,Timestamp,AvailabilityZone]' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$spot_data" && "$spot_data" != "None" ]]; then
            IFS=$'\t' read -r price timestamp az_name <<< "$spot_data"
            
            # Create JSON entry
            local json_entry=$(jq -n \
                --arg instance_type "$instance_type" \
                --arg price "$price" \
                --arg timestamp "$timestamp" \
                --arg az "$az_name" \
                --arg region "$region" \
                '{
                    instance_type: $instance_type,
                    spot_price: ($price | tonumber),
                    timestamp: $timestamp,
                    availability_zone: $az,
                    region: $region
                }')
            
            # Add to pricing data
            echo "$pricing_data" | jq ". + [$json_entry]" > "$temp_file"
            pricing_data=$(cat "$temp_file")
            
            info "    💰 $az: \$$price/hour"
        else
            warning "    ❌ $az: No spot price data available"
        fi
    done
    
    rm -f "$temp_file"
    echo "$pricing_data"
}

calculate_cost_efficiency_score() {
    local instance_type="$1"
    local spot_price="$2"
    local region="${3:-$AWS_REGION}"
    
    # Get performance score
    local perf_score=$(get_performance_score "$instance_type")
    if [[ -z "$perf_score" || "$perf_score" == "0" ]]; then
        echo "0"
        return 1
    fi
    
    # Get on-demand price for comparison
    local on_demand_price=$(get_on_demand_price "$instance_type" "$region")
    if [[ -z "$on_demand_price" || "$on_demand_price" == "0" ]]; then
        # Fallback prices
        case "$instance_type" in
            "g4dn.xlarge") on_demand_price="1.204" ;;
            "g4dn.2xlarge") on_demand_price="2.176" ;;
            "g5g.xlarge") on_demand_price="1.006" ;;
            "g5g.2xlarge") on_demand_price="2.012" ;;
            *) on_demand_price="1.50" ;;
        esac
    fi
    
    # Calculate metrics
    local savings_percent=$(echo "scale=2; (($on_demand_price - $spot_price) / $on_demand_price) * 100" | bc -l 2>/dev/null || echo "0")
    local price_performance=$(echo "scale=3; $perf_score / $spot_price" | bc -l 2>/dev/null || echo "0")
    local cost_efficiency=$(echo "scale=3; ($price_performance * (1 + $savings_percent / 100))" | bc -l 2>/dev/null || echo "0")
    
    echo "$cost_efficiency"
}

get_on_demand_price() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    # Try to get from AWS Pricing API (simplified version)
    local price=$(aws pricing get-products \
        --service-code AmazonEC2 \
        --region us-east-1 \
        --filters "Type=TERM_MATCH,Field=instanceType,Value=$instance_type" \
                 "Type=TERM_MATCH,Field=location,Value=US East (N. Virginia)" \
                 "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
                 "Type=TERM_MATCH,Field=operating-system,Value=Linux" \
        --query 'PriceList[0]' \
        --output text 2>/dev/null | \
        jq -r '.terms.OnDemand | to_entries[0].value.priceDimensions | to_entries[0].value.pricePerUnit.USD' 2>/dev/null || echo "")
    
    if [[ -n "$price" && "$price" != "null" ]]; then
        echo "$price"
    else
        # Fallback to hardcoded prices (updated as of 2024)
        case "$instance_type" in
            "g4dn.xlarge") echo "1.204" ;;
            "g4dn.2xlarge") echo "2.176" ;;
            "g5g.xlarge") echo "1.006" ;;
            "g5g.2xlarge") echo "2.012" ;;
            "g5.xlarge") echo "1.212" ;;
            "g5.2xlarge") echo "2.424" ;;
            *) echo "1.50" ;;
        esac
    fi
}

find_optimal_instance_configuration() {
    local max_budget="${1:-$MAX_SPOT_PRICE}"
    local preferred_regions="${2:-$AWS_REGION}"
    local enable_cross_region="${3:-false}"
    
    log "🎯 Finding optimal instance configuration with budget \$$max_budget/hour..."
    
    # Convert preferred_regions to array
    IFS=',' read -ra regions_to_check <<< "$preferred_regions"
    if [[ "$enable_cross_region" == "true" ]]; then
        regions_to_check+=("us-west-2" "eu-west-1" "ap-northeast-1" "eu-central-1")
        # Remove duplicates
        IFS=" " read -ra regions_to_check <<< "$(printf '%s\n' "${regions_to_check[@]}" | sort -u | tr '\n' ' ')"
    fi
    
    local best_config=""
    local best_cost_efficiency="0"
    local all_options=()
    
    # Check each region
    for region in "${regions_to_check[@]}"; do
        info "🌍 Analyzing region: $region"
        
        # Check each instance type
        for instance_type in $(get_instance_type_list); do
            # Skip if instance type not available in region
            if ! check_instance_type_availability "$instance_type" "$region" >/dev/null 2>&1; then
                continue
            fi
            
            # Get multi-AZ spot prices
            local az_pricing=$(get_multi_az_spot_prices "$instance_type" "$region")
            
            if [[ "$az_pricing" == "[]" ]]; then
                continue
            fi
            
            # Find best AZ for this instance type in this region
            local best_az_config=$(echo "$az_pricing" | jq -r --arg budget "$max_budget" '
                [.[] | select(.spot_price <= ($budget | tonumber))] |
                if length > 0 then
                    sort_by(.spot_price)[0] |
                    "\(.instance_type)|\(.spot_price)|\(.availability_zone)|\(.region)"
                else
                    empty
                end' 2>/dev/null || echo "")
            
            if [[ -n "$best_az_config" ]]; then
                IFS='|' read -r inst_type spot_price best_az inst_region <<< "$best_az_config"
                
                # Calculate cost efficiency score
                local cost_efficiency=$(calculate_cost_efficiency_score "$inst_type" "$spot_price" "$inst_region")
                
                # Get AMI for this configuration
                local ami=$(discover_latest_deep_learning_ami "$inst_type" "$inst_region" 2>/dev/null || echo "")
                
                if [[ -n "$ami" ]]; then
                    local config="$inst_type:$ami:$spot_price:$best_az:$inst_region:$cost_efficiency"
                    all_options+=("$config")
                    
                    info "  ✅ $inst_type in $best_az: \$$spot_price/hour (efficiency: $cost_efficiency)"
                    
                    # Check if this is the best option so far
                    if (( $(echo "$cost_efficiency > $best_cost_efficiency" | bc -l 2>/dev/null || echo "0") )); then
                        best_cost_efficiency="$cost_efficiency"
                        best_config="$config"
                    fi
                fi
            fi
        done
    done
    
    # Display analysis results
    if [[ ${#all_options[@]} -gt 0 ]]; then
        info "📊 Cost-Efficiency Analysis (sorted by efficiency score):"
        echo ""
        echo -e "${CYAN}┌─────────────────┬──────────┬───────────────┬─────────────┬────────────────┐${NC}"
        echo -e "${CYAN}│ Instance Type   │ Price/hr │ Availability  │ Region      │ Efficiency     │${NC}"
        echo -e "${CYAN}│                 │          │ Zone          │             │ Score          │${NC}"
        echo -e "${CYAN}├─────────────────┼──────────┼───────────────┼─────────────┼────────────────┤${NC}"
        
        # Sort by efficiency and show top options
        IFS=$'\n' read -d '' -r -a sorted_options < <(printf '%s\n' "${all_options[@]}" | sort -t':' -k6 -nr) || true
        
        local count=0
        for option in "${sorted_options[@]}"; do
            if [[ $count -ge 10 ]]; then break; fi  # Show top 10
            
            IFS=':' read -r inst_type ami price az region efficiency <<< "$option"
            printf "${CYAN}│ %-15s │ %-8s │ %-13s │ %-11s │ %-14s │${NC}\n" \
                "$inst_type" "\$$price" "$az" "$region" "$efficiency"
            ((count++))
        done
        
        echo -e "${CYAN}└─────────────────┴──────────┴───────────────┴─────────────┴────────────────┘${NC}"
        echo ""
    fi
    
    # Return best configuration
    if [[ -n "$best_config" ]]; then
        IFS=':' read -r selected_type selected_ami selected_price selected_az selected_region selected_efficiency <<< "$best_config"
        
        success "🏆 OPTIMAL CONFIGURATION SELECTED:"
        info "  Instance Type: $selected_type"
        info "  AMI: $selected_ami"
        info "  Spot Price: \$$selected_price/hour"
        info "  Availability Zone: $selected_az"
        info "  Region: $selected_region"
        info "  Cost Efficiency Score: $selected_efficiency"
        
        # Calculate potential savings
        local on_demand_price=$(get_on_demand_price "$selected_type" "$selected_region")
        local savings_percent=$(echo "scale=1; (($on_demand_price - $selected_price) / $on_demand_price) * 100" | bc -l 2>/dev/null || echo "0")
        local monthly_savings=$(echo "scale=2; ($on_demand_price - $selected_price) * 24 * 30" | bc -l 2>/dev/null || echo "0")
        
        info "  💰 Estimated savings: $savings_percent% vs on-demand (\$$monthly_savings/month)"
        
        # Export for use by other functions
        export SELECTED_INSTANCE_TYPE="$selected_type"
        export SELECTED_AMI="$selected_ami"
        export SELECTED_PRICE="$selected_price"
        export SELECTED_AZ="$selected_az"
        export SELECTED_REGION="$selected_region"
        
        echo "$best_config"
        return 0
    else
        error "No suitable configurations found within budget \$$max_budget/hour"
        
        # Suggest alternatives
        if [[ ${#all_options[@]} -gt 0 ]]; then
            local cheapest_option="${all_options[0]}"
            for option in "${all_options[@]}"; do
                IFS=':' read -r _ _ price _ _ _ <<< "$option"
                IFS=':' read -r _ _ cheapest_price _ _ _ <<< "$cheapest_option"
                if (( $(echo "$price < $cheapest_price" | bc -l 2>/dev/null || echo "0") )); then
                    cheapest_option="$option"
                fi
            done
            
            IFS=':' read -r cheap_type _ cheap_price cheap_az cheap_region _ <<< "$cheapest_option"
            warning "💡 Cheapest available option: $cheap_type in $cheap_az (\$$cheap_price/hour)"
            warning "💡 Consider increasing budget to \$$(echo "scale=2; $cheap_price * 1.1" | bc -l)/hour"
        fi
        
        return 1
    fi
}

estimate_deployment_costs() {
    local instance_type="$1"
    local spot_price="$2"
    local region="${3:-$AWS_REGION}"
    
    log "💰 Estimating deployment costs for $instance_type..."
    
    # Get on-demand price for comparison
    local on_demand_price=$(get_on_demand_price "$instance_type" "$region")
    
    # Calculate various cost estimates
    local hourly_spot="$spot_price"
    local hourly_ondemand="$on_demand_price"
    local daily_spot=$(echo "scale=2; $spot_price * 24" | bc -l)
    local daily_ondemand=$(echo "scale=2; $on_demand_price * 24" | bc -l)
    local monthly_spot=$(echo "scale=2; $spot_price * 24 * 30" | bc -l)
    local monthly_ondemand=$(echo "scale=2; $on_demand_price * 24 * 30" | bc -l)
    
    # Calculate savings
    local daily_savings=$(echo "scale=2; $daily_ondemand - $daily_spot" | bc -l)
    local monthly_savings=$(echo "scale=2; $monthly_ondemand - $monthly_spot" | bc -l)
    local savings_percent=$(echo "scale=1; (($on_demand_price - $spot_price) / $on_demand_price) * 100" | bc -l)
    
    # Additional AWS service costs (estimated)
    local ebs_monthly="8.00"  # 100GB gp3 storage
    local efs_monthly="12.00" # 40GB EFS storage
    local data_transfer="5.00" # Modest data transfer
    local other_services=$(echo "scale=2; $ebs_monthly + $efs_monthly + $data_transfer" | bc -l)
    
    local total_monthly_spot=$(echo "scale=2; $monthly_spot + $other_services" | bc -l)
    local total_monthly_ondemand=$(echo "scale=2; $monthly_ondemand + $other_services" | bc -l)
    
    # Display cost analysis
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                    💰 DEPLOYMENT COST ANALYSIS                      │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ Instance: %-58s │${NC}" "$instance_type"
    echo -e "${CYAN}│ Region: %-60s │${NC}" "$region"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ COMPUTE COSTS:                                                      │${NC}"
    printf "${CYAN}│   Spot Instance:     %-20s %-20s %-11s │${NC}\n" "\$$hourly_spot/hr" "\$$daily_spot/day" "\$$monthly_spot/month"
    printf "${CYAN}│   On-Demand:         %-20s %-20s %-11s │${NC}\n" "\$$hourly_ondemand/hr" "\$$daily_ondemand/day" "\$$monthly_ondemand/month"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ ADDITIONAL AWS SERVICES (estimated):                               │${NC}"
    echo -e "${CYAN}│   EBS Storage (100GB gp3):                              \$8.00/month  │${NC}"
    echo -e "${CYAN}│   EFS Storage (40GB):                                  \$12.00/month  │${NC}"
    echo -e "${CYAN}│   Data Transfer & Other:                                \$5.00/month  │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ TOTAL ESTIMATED MONTHLY COSTS:                                     │${NC}"
    printf "${CYAN}│   With Spot Instances:                                 \$%-12s │${NC}\n" "$total_monthly_spot"
    printf "${CYAN}│   With On-Demand:                                      \$%-12s │${NC}\n" "$total_monthly_ondemand"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ POTENTIAL SAVINGS:                                                 │${NC}"
    printf "${CYAN}│   Daily Savings:                                       \$%-12s │${NC}\n" "$daily_savings"
    printf "${CYAN}│   Monthly Savings:                                     \$%-12s │${NC}\n" "$monthly_savings"
    printf "${CYAN}│   Savings Percentage:                                   %-12s │${NC}\n" "$savings_percent%"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Cost alerts
    if (( $(echo "$total_monthly_spot > 200" | bc -l) )); then
        warning "⚠️  High monthly cost estimate: \$$total_monthly_spot"
        warning "   Consider smaller instance types or scheduled shutdowns"
    fi
    
    if (( $(echo "$savings_percent < 30" | bc -l) )); then
        warning "⚠️  Low savings vs on-demand ($savings_percent%)"
        warning "   Spot prices may be elevated - consider waiting or different regions"
    fi
    
    # Export cost estimates for other functions
    export ESTIMATED_MONTHLY_COST="$total_monthly_spot"
    export ESTIMATED_MONTHLY_SAVINGS="$monthly_savings"
    export ESTIMATED_SAVINGS_PERCENT="$savings_percent"
}

send_cost_alert() {
    local alert_type="$1"
    local message="$2"
    local cost_estimate="${3:-N/A}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local alert_message="[AI Starter Kit] $alert_type Alert - $timestamp

$message

Estimated Monthly Cost: \$$cost_estimate
Instance: ${SELECTED_INSTANCE_TYPE:-N/A}
Region: ${SELECTED_REGION:-$AWS_REGION}

Deployment Command: $0 $*

Generated by AI Starter Kit Cost Monitoring"
    
    # Log the alert
    echo "$alert_message" | tee -a "/tmp/cost-alerts.log"
    
    # In production, this would send to SNS, email, or Slack
    if [[ -n "${COST_ALERT_WEBHOOK:-}" ]]; then
        curl -X POST "$COST_ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$alert_message\"}" \
            2>/dev/null || true
    fi
    
    # Could also send to AWS SNS if topic is configured
    if [[ -n "${COST_ALERT_SNS_TOPIC:-}" ]]; then
        aws sns publish \
            --topic-arn "$COST_ALERT_SNS_TOPIC" \
            --message "$alert_message" \
            --region "$AWS_REGION" \
            2>/dev/null || true
    fi
}

# =============================================================================
# OPTIMIZED USER DATA GENERATION
# =============================================================================

create_optimized_user_data() {
    local instance_type="$1"
    local ami_type="$2"
    
    log "Creating optimized user data for $instance_type with $ami_type AMI..."
    
    # Determine CPU architecture
    local cpu_arch="x86_64"
    if [[ "$instance_type" == g5g* ]]; then
        cpu_arch="arm64"
    fi
    
    cat > user-data.sh << EOF
#!/bin/bash
set -euo pipefail

# Progress tracking function
create_progress_marker() {
    local step="\$1"
    local status="\$2"
    local message="\$3"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [\$status] \$step: \$message" | tee -a /var/log/user-data-progress.log
    echo "\$step:\$status:\$message" > "/tmp/user-data-step-\$step"
    # Also create a latest status file for easy monitoring
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [\$status] \$step: \$message" > /tmp/user-data-latest-status
}

# Error handling function
handle_error() {
    local step="\$1"
    local error_msg="\$2"
    create_progress_marker "\$step" "ERROR" "\$error_msg"
    echo "=== ERROR DETAILS ===" >> /var/log/user-data-progress.log
    echo "Step: \$step" >> /var/log/user-data-progress.log
    echo "Error: \$error_msg" >> /var/log/user-data-progress.log
    echo "Last 20 lines of user-data.log:" >> /var/log/user-data-progress.log
    tail -20 /var/log/user-data.log >> /var/log/user-data-progress.log
    exit 1
}

# Set error trap
trap 'handle_error "UNKNOWN" "Script failed unexpectedly at line \$LINENO"' ERR

# Log all output for debugging
exec > >(tee /var/log/user-data.log) 2>&1

create_progress_marker "INIT" "STARTING" "AI Starter Kit Deep Learning AMI Setup"

echo "=== AI Starter Kit Deep Learning AMI Setup ==="
echo "Timestamp: \$(date)"
echo "Instance Type: $instance_type"
echo "CPU Architecture: $cpu_arch"
echo "AMI Type: $ami_type"

# System identification
echo "System Information:"
uname -a
cat /etc/os-release

create_progress_marker "SYSTEM_UPDATE" "RUNNING" "Updating system packages"

# Update system packages
echo "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update && apt-get upgrade -y || handle_error "SYSTEM_UPDATE" "Failed to update packages with apt-get"
elif command -v yum &> /dev/null; then
    yum update -y || handle_error "SYSTEM_UPDATE" "Failed to update packages with yum"
fi

create_progress_marker "SYSTEM_UPDATE" "COMPLETED" "System packages updated successfully"

create_progress_marker "GPU_VERIFY" "RUNNING" "Verifying Deep Learning AMI components"

# Verify Deep Learning AMI components
echo "=== Verifying Deep Learning AMI Components ==="

# Check NVIDIA drivers
if command -v nvidia-smi &> /dev/null; then
    echo "✓ NVIDIA drivers found:"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
    create_progress_marker "GPU_VERIFY" "SUCCESS" "NVIDIA drivers found and working"
else
    echo "⚠ NVIDIA drivers not found - installing drivers"
    create_progress_marker "GPU_INSTALL" "RUNNING" "Installing NVIDIA drivers"
    
    # Install NVIDIA drivers for Deep Learning AMI
    if [[ "$cpu_arch" == "x86_64" ]]; then
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb || handle_error "GPU_INSTALL" "Failed to download CUDA keyring"
        dpkg -i cuda-keyring_1.0-1_all.deb || handle_error "GPU_INSTALL" "Failed to install CUDA keyring"
        apt-get update || handle_error "GPU_INSTALL" "Failed to update package list after CUDA keyring"
        apt-get install -y nvidia-driver-470 cuda-toolkit-11-8 || handle_error "GPU_INSTALL" "Failed to install NVIDIA drivers and CUDA toolkit"
    else
        echo "ARM64 architecture - using different driver installation method"
        apt-get install -y nvidia-jetpack || handle_error "GPU_INSTALL" "Failed to install NVIDIA Jetpack for ARM64"
    fi
    
    create_progress_marker "GPU_INSTALL" "COMPLETED" "NVIDIA drivers installed successfully"
fi

create_progress_marker "DOCKER_VERIFY" "RUNNING" "Verifying Docker installation"

# Verify Docker
if command -v docker &> /dev/null; then
    echo "✓ Docker found:"
    docker --version
    # Ensure ubuntu user is in docker group
    usermod -aG docker ubuntu
    create_progress_marker "DOCKER_VERIFY" "SUCCESS" "Docker found and configured"
else
    echo "Installing Docker..."
    create_progress_marker "DOCKER_INSTALL" "RUNNING" "Installing Docker"
    
    curl -fsSL https://get.docker.com -o get-docker.sh || handle_error "DOCKER_INSTALL" "Failed to download Docker install script"
    sh get-docker.sh || handle_error "DOCKER_INSTALL" "Failed to install Docker"
    usermod -aG docker ubuntu || handle_error "DOCKER_INSTALL" "Failed to add ubuntu user to docker group"
    rm get-docker.sh
    
    create_progress_marker "DOCKER_INSTALL" "COMPLETED" "Docker installed successfully"
fi

create_progress_marker "DOCKER_COMPOSE" "RUNNING" "Installing/verifying Docker Compose"

# Install/verify Docker Compose
if command -v docker-compose &> /dev/null; then
    echo "✓ Docker Compose found:"
    docker-compose --version
    create_progress_marker "DOCKER_COMPOSE" "SUCCESS" "Docker Compose found"
else
    echo "Installing Docker Compose..."
    if [[ "$cpu_arch" == "x86_64" ]]; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose || handle_error "DOCKER_COMPOSE" "Failed to download Docker Compose for x86_64"
    else
        # ARM64 version
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose || handle_error "DOCKER_COMPOSE" "Failed to download Docker Compose for ARM64"
    fi
    chmod +x /usr/local/bin/docker-compose || handle_error "DOCKER_COMPOSE" "Failed to make Docker Compose executable"
    
    create_progress_marker "DOCKER_COMPOSE" "COMPLETED" "Docker Compose installed successfully"
fi

create_progress_marker "NVIDIA_RUNTIME" "RUNNING" "Configuring NVIDIA Container Runtime"

# Configure NVIDIA Container Runtime
echo "=== Configuring NVIDIA Container Runtime ==="
if ! docker info | grep -q nvidia; then
    echo "Configuring NVIDIA Container Runtime..."
    
    # Install nvidia-container-toolkit
    if [[ "$cpu_arch" == "x86_64" ]]; then
        distribution=\$(. /etc/os-release;echo \$ID\$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add - || handle_error "NVIDIA_RUNTIME" "Failed to add NVIDIA Docker GPG key"
        curl -s -L https://nvidia.github.io/nvidia-docker/\$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list || handle_error "NVIDIA_RUNTIME" "Failed to add NVIDIA Docker repository"
        apt-get update && apt-get install -y nvidia-container-toolkit || handle_error "NVIDIA_RUNTIME" "Failed to install nvidia-container-toolkit"
    else
        # ARM64 specific nvidia container runtime
        apt-get install -y nvidia-container-runtime || handle_error "NVIDIA_RUNTIME" "Failed to install nvidia-container-runtime for ARM64"
    fi
    
    # Configure Docker daemon
    cat > /etc/docker/daemon.json << 'EODAEMON'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EODAEMON
    
    systemctl restart docker || handle_error "NVIDIA_RUNTIME" "Failed to restart Docker service"
    
    create_progress_marker "NVIDIA_RUNTIME" "COMPLETED" "NVIDIA Container Runtime configured successfully"
else
    create_progress_marker "NVIDIA_RUNTIME" "SUCCESS" "NVIDIA Container Runtime already configured"
fi

create_progress_marker "GPU_TEST" "RUNNING" "Testing GPU access in containers"

# Test GPU access
echo "=== Testing GPU Access ==="
if [[ "$cpu_arch" == "x86_64" ]]; then
    if docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi; then
        echo "✓ GPU access in Docker containers verified"
        create_progress_marker "GPU_TEST" "SUCCESS" "GPU access in Docker containers verified"
    else
        handle_error "GPU_TEST" "GPU access in Docker containers failed"
    fi
else
    # ARM64 GPU test
    if docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/l4t-base:r32.7.1 nvidia-smi; then
        echo "✓ ARM64 GPU access verified"
        create_progress_marker "GPU_TEST" "SUCCESS" "ARM64 GPU access verified"
    else
        handle_error "GPU_TEST" "ARM64 GPU access failed"
    fi
fi

create_progress_marker "TOOLS_INSTALL" "RUNNING" "Installing additional tools"

# Install additional tools
echo "Installing additional tools..."
if command -v apt-get &> /dev/null; then
    apt-get install -y jq curl wget git htop awscli nfs-common tree || handle_error "TOOLS_INSTALL" "Failed to install additional tools with apt-get"
    
    # Install nvtop for GPU monitoring (if available)
    if [[ "$cpu_arch" == "x86_64" ]]; then
        apt-get install -y nvtop || echo "nvtop not available, continuing..."
    fi
elif command -v yum &> /dev/null; then
    yum install -y jq curl wget git htop awscli nfs-utils tree || handle_error "TOOLS_INSTALL" "Failed to install additional tools with yum"
fi

create_progress_marker "TOOLS_INSTALL" "COMPLETED" "Additional tools installed successfully"

create_progress_marker "CLOUDWATCH" "RUNNING" "Installing CloudWatch agent"

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
if [[ "$cpu_arch" == "x86_64" ]]; then
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb || handle_error "CLOUDWATCH" "Failed to download CloudWatch agent for x86_64"
    dpkg -i amazon-cloudwatch-agent.deb || handle_error "CLOUDWATCH" "Failed to install CloudWatch agent"
    rm amazon-cloudwatch-agent.deb
else
    # ARM64 CloudWatch agent
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb || handle_error "CLOUDWATCH" "Failed to download CloudWatch agent for ARM64"
    dpkg -i amazon-cloudwatch-agent.deb || handle_error "CLOUDWATCH" "Failed to install CloudWatch agent"
    rm amazon-cloudwatch-agent.deb
fi

create_progress_marker "CLOUDWATCH" "COMPLETED" "CloudWatch agent installed successfully"

create_progress_marker "SERVICES" "RUNNING" "Starting and enabling services"

# Ensure services are running
systemctl enable docker || handle_error "SERVICES" "Failed to enable Docker service"
systemctl start docker || handle_error "SERVICES" "Failed to start Docker service"

# Create mount point for EFS
mkdir -p /mnt/efs

create_progress_marker "SERVICES" "COMPLETED" "Services started and configured"

create_progress_marker "GPU_SCRIPT" "RUNNING" "Creating GPU monitoring script"

# Create architecture-aware GPU monitoring script
cat > /usr/local/bin/gpu-check.sh << 'EOGPU'
#!/bin/bash
echo "=== GPU Status Check ==="
echo "Date: \$(date)"
echo "Architecture: $cpu_arch"
echo "Instance Type: $instance_type"

if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA Driver Version:"
    nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits
    echo "GPU Information:"
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu,power.draw --format=csv
    echo "Docker GPU Test:"
    if [[ "$cpu_arch" == "x86_64" ]]; then
        docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi -L
    else
        docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/l4t-base:r32.7.1 nvidia-smi -L
    fi
else
    echo "NVIDIA drivers not found"
fi
EOGPU

chmod +x /usr/local/bin/gpu-check.sh

create_progress_marker "GPU_SCRIPT" "COMPLETED" "GPU monitoring script created"

create_progress_marker "FINAL_CHECK" "RUNNING" "Running final GPU check"

# Run initial GPU check
echo "=== Running Initial GPU Check ==="
/usr/local/bin/gpu-check.sh

create_progress_marker "FINAL_CHECK" "COMPLETED" "Final GPU check completed"

# Signal completion
create_progress_marker "SETUP_COMPLETE" "SUCCESS" "Deep Learning AMI setup completed successfully"

echo "=== Deep Learning AMI Setup Complete ==="
echo "Timestamp: \$(date)"
echo "Instance: $instance_type ($cpu_arch)"
echo "AMI Type: $ami_type"
touch /tmp/user-data-complete

EOF
}

# =============================================================================
# INTELLIGENT SPOT INSTANCE LAUNCH
# =============================================================================

launch_spot_instance() {
    local SG_ID="$1"
    local EFS_DNS="$2"
    local enable_cross_region="${3:-false}"
    
    log "🚀 Launching GPU spot instance with intelligent configuration selection..."
    
    # Step 1: Run enhanced intelligent configuration selection
    if [[ "$INSTANCE_TYPE" == "auto" ]]; then
        log "Auto-selection mode: Finding optimal configuration with advanced cost analysis..."
        OPTIMAL_CONFIG=$(find_optimal_instance_configuration "$MAX_SPOT_PRICE" "$AWS_REGION" "$enable_cross_region")
        
        if [[ $? -ne 0 ]]; then
            error "Failed to find optimal configuration within budget"
            return 1
        fi
        
        # Parse optimal configuration - Enhanced format: instance:ami:price:az:region:efficiency
        IFS=':' read -r SELECTED_INSTANCE_TYPE SELECTED_AMI SELECTED_PRICE SELECTED_AZ SELECTED_REGION SELECTED_EFFICIENCY <<< "$OPTIMAL_CONFIG"
        
        # Set AMI type based on discovered AMI
        SELECTED_AMI_TYPE="auto-discovered"
        
        # Use the selected AZ if provided
        if [[ -n "$SELECTED_AZ" ]]; then
            export PREFERRED_AZ="$SELECTED_AZ"
        fi
        
        # Update region if different
        if [[ "$SELECTED_REGION" != "$AWS_REGION" ]]; then
            export AWS_REGION="$SELECTED_REGION"
        fi
        
        # Debug output
        info "Enhanced configuration selection results:"
        info "  Instance Type: '$SELECTED_INSTANCE_TYPE'"
        info "  AMI: '$SELECTED_AMI'"
        info "  Spot Price: '\$$SELECTED_PRICE/hour'"
        info "  Availability Zone: '$SELECTED_AZ'"
        info "  Region: '$SELECTED_REGION'"
        info "  Cost Efficiency Score: '$SELECTED_EFFICIENCY'"
        
    else
        log "Manual selection mode: Using specified instance type $INSTANCE_TYPE"
        
        # Verify manually selected instance type and find best AMI
        if ! check_instance_type_availability "$INSTANCE_TYPE" "$AWS_REGION" >/dev/null 2>&1; then
            error "Specified instance type $INSTANCE_TYPE not available in $AWS_REGION"
            return 1
        fi
        
        # Find best AMI for specified instance type
        local primary_ami="$(get_gpu_config "${INSTANCE_TYPE}_primary")"
        local secondary_ami="$(get_gpu_config "${INSTANCE_TYPE}_secondary")"
        
        if verify_ami_availability "$primary_ami" "$AWS_REGION" >/dev/null 2>&1; then
            SELECTED_AMI="$primary_ami"
            SELECTED_AMI_TYPE="primary"
        elif verify_ami_availability "$secondary_ami" "$AWS_REGION" >/dev/null 2>&1; then
            SELECTED_AMI="$secondary_ami"
            SELECTED_AMI_TYPE="secondary"
        else
            error "No valid AMIs available for $INSTANCE_TYPE"
            return 1
        fi
        
        SELECTED_INSTANCE_TYPE="$INSTANCE_TYPE"
        SELECTED_PRICE="$MAX_SPOT_PRICE"
        SELECTED_REGION="$AWS_REGION"
    fi
    
    # Validate that we have all required values
    if [[ -z "$SELECTED_INSTANCE_TYPE" || -z "$SELECTED_AMI" || -z "$SELECTED_AMI_TYPE" ]]; then
        error "Configuration selection failed - missing required values:"
        error "  Instance Type: '$SELECTED_INSTANCE_TYPE'"
        error "  AMI: '$SELECTED_AMI'"
        error "  AMI Type: '$SELECTED_AMI_TYPE'"
        return 1
    fi
    
    success "Selected configuration: $SELECTED_INSTANCE_TYPE with AMI $SELECTED_AMI ($SELECTED_AMI_TYPE)"
    info "Budget: \$$SELECTED_PRICE/hour"
    info "Region: $SELECTED_REGION"
    
    # Step 2: Estimate deployment costs and send alerts if needed
    estimate_deployment_costs "$SELECTED_INSTANCE_TYPE" "$SELECTED_PRICE" "$SELECTED_REGION"
    
    # Send cost alert if estimate is high
    if [[ -n "$ESTIMATED_MONTHLY_COST" ]] && (( $(echo "$ESTIMATED_MONTHLY_COST > 150" | bc -l 2>/dev/null || echo "0") )); then
        send_cost_alert "High Cost" "Deployment estimated at \$$ESTIMATED_MONTHLY_COST/month" "$ESTIMATED_MONTHLY_COST"
    fi
    
    # Step 3: Create optimized user data
    create_optimized_user_data "$SELECTED_INSTANCE_TYPE" "$SELECTED_AMI_TYPE"
    
    # Step 3: Get pricing data for selected instance type for AZ optimization
    log "Analyzing spot pricing by availability zone for $SELECTED_INSTANCE_TYPE..."
    SPOT_PRICES_JSON=$(aws ec2 describe-spot-price-history \
        --instance-types "$SELECTED_INSTANCE_TYPE" \
        --product-descriptions "Linux/UNIX" \
        --max-items 50 \
        --region "$AWS_REGION" \
        --query 'SpotPrices | sort_by(@, &Timestamp) | reverse(@) | [*] | group_by(@, &AvailabilityZone) | map([.[0].AvailabilityZone, .[0].SpotPrice]) | sort_by(@, &[1])' \
        --output json 2>/dev/null || echo "[]")
    
    # Step 4: Determine AZ launch order
    local ORDERED_AZS=()
    if [[ "$SPOT_PRICES_JSON" != "[]" && -n "$SPOT_PRICES_JSON" ]]; then
        info "Current spot pricing by AZ:"
        echo "$SPOT_PRICES_JSON" | jq -r '.[] | "  \(.[0]): $\(.[1])/hour"'
        
        # Create ordered list of AZs by price (lowest first)
        ORDERED_AZS=($(echo "$SPOT_PRICES_JSON" | jq -r '.[] | .[0]' 2>/dev/null || echo ""))
        
        # Filter AZs within budget
        local AFFORDABLE_AZS=()
        for AZ_PRICE in $(echo "$SPOT_PRICES_JSON" | jq -r '.[] | "\(.[0]):\(.[1])"' 2>/dev/null); do
            IFS=':' read -r AZ PRICE <<< "$AZ_PRICE"
            if (( $(echo "$PRICE <= $MAX_SPOT_PRICE" | bc -l 2>/dev/null || echo "1") )); then
                AFFORDABLE_AZS+=("$AZ")
            else
                warning "Excluding $AZ (price: \$$PRICE exceeds budget: \$$MAX_SPOT_PRICE)"
            fi
        done
        
        if [[ ${#AFFORDABLE_AZS[@]} -gt 0 ]]; then
            ORDERED_AZS=("${AFFORDABLE_AZS[@]}")
            info "Attempting launch in price-ordered AZs: ${ORDERED_AZS[*]}"
        else
            warning "No AZs within budget, trying all available AZs"
            ORDERED_AZS=($(aws ec2 describe-availability-zones --region "$AWS_REGION" --query 'AvailabilityZones[?State==`available`].ZoneName' --output text))
        fi
    else
        warning "Could not retrieve pricing data, using all available AZs"
        ORDERED_AZS=($(aws ec2 describe-availability-zones --region "$AWS_REGION" --query 'AvailabilityZones[?State==`available`].ZoneName' --output text))
    fi
    
    # Step 5: Try launching in each AZ in order
    for AZ in "${ORDERED_AZS[@]}"; do
        log "Attempting spot instance launch in AZ: $AZ"
        
        # Get subnet for this AZ
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=availability-zone,Values=$AZ" "Name=default-for-az,Values=true" \
            --region "$AWS_REGION" \
            --query 'Subnets[0].SubnetId' \
            --output text)
        
        if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
            warning "No suitable subnet found in $AZ, skipping..."
            continue
        fi
        
        info "Using subnet $SUBNET_ID in $AZ"
        
        # Get current price for this AZ
        CURRENT_PRICE=$(echo "$SPOT_PRICES_JSON" | jq -r ".[] | select(.[0] == \"$AZ\") | .[1]" 2>/dev/null || echo "unknown")
        if [[ "$CURRENT_PRICE" != "unknown" && "$CURRENT_PRICE" != "null" ]]; then
            info "Current spot price in $AZ: \$$CURRENT_PRICE/hour"
        fi
        
        # Create spot instance request
        log "Creating spot instance request in $AZ with max price \$$MAX_SPOT_PRICE/hour..."
        # Prepare instance profile name
        INSTANCE_PROFILE_NAME="$(if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then echo "app-$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')-profile"; else echo "${STACK_NAME}-instance-profile"; fi)"
        
        # Validate security group ID format before using
        if [[ ! "$SG_ID" =~ ^sg-[0-9a-fA-F]+$ ]]; then
            warning "Invalid security group ID format: $SG_ID. Skipping $AZ."
            continue
        fi
        
        # Validate required parameters before spot instance request
        if [[ -z "$SELECTED_AMI" || -z "$SELECTED_INSTANCE_TYPE" || -z "$KEY_NAME" || -z "$SUBNET_ID" || -z "$INSTANCE_PROFILE_NAME" ]]; then
            warning "Missing required parameters for spot instance in $AZ. Skipping..."
            continue
        fi
        
        # Validate user data file exists
        if [[ ! -f "user-data.sh" ]]; then
            warning "User data file not found. Skipping $AZ."
            continue
        fi
        
        # Create spot instance request with individual parameters
        info "Requesting spot instance in $AZ: $SELECTED_INSTANCE_TYPE at \$$MAX_SPOT_PRICE/hour"
        
        REQUEST_RESULT=$(aws ec2 request-spot-instances \
            --spot-price "$MAX_SPOT_PRICE" \
            --instance-count 1 \
            --type "one-time" \
            --image-id "$SELECTED_AMI" \
            --instance-type "$SELECTED_INSTANCE_TYPE" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SG_ID" \
            --subnet-id "$SUBNET_ID" \
            --user-data "file://user-data.sh" \
            --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
            --region "$AWS_REGION" 2>&1) || {
            warning "Failed to create spot instance request in $AZ: $REQUEST_RESULT"
            continue
        }
        
        REQUEST_ID=$(echo "$REQUEST_RESULT" | jq -r '.SpotInstanceRequests[0].SpotInstanceRequestId' 2>/dev/null || echo "")
        
        if [[ -z "$REQUEST_ID" || "$REQUEST_ID" == "None" || "$REQUEST_ID" == "null" ]]; then
            warning "Failed to extract spot request ID from response in $AZ"
            continue
        fi
        
        success "Created spot instance request $REQUEST_ID in $AZ"
        
        info "Spot instance request ID: $REQUEST_ID in $AZ"
        
        # Wait for spot request fulfillment
        log "Waiting for spot instance to be launched in $AZ..."
        local attempt=0
        local max_attempts=10
        local fulfilled=false
        
        while [ $attempt -lt $max_attempts ]; do
            REQUEST_STATE=$(aws ec2 describe-spot-instance-requests \
                --spot-instance-request-ids "$REQUEST_ID" \
                --region "$AWS_REGION" \
                --query 'SpotInstanceRequests[0].State' \
                --output text 2>/dev/null || echo "failed")
            
            if [[ "$REQUEST_STATE" == "active" ]]; then
                fulfilled=true
                break
            elif [[ "$REQUEST_STATE" == "failed" || "$REQUEST_STATE" == "cancelled" ]]; then
                warning "Spot instance request failed with state: $REQUEST_STATE"
                break
            fi
            
            attempt=$((attempt + 1))
            info "Attempt $attempt/$max_attempts: Request state is $REQUEST_STATE, waiting 30s..."
            sleep 30
        done
        
        if [ "$fulfilled" = true ]; then
            # Get instance ID
            INSTANCE_ID=$(aws ec2 describe-spot-instance-requests \
                --spot-instance-request-ids "$REQUEST_ID" \
                --region "$AWS_REGION" \
                --query 'SpotInstanceRequests[0].InstanceId' \
                --output text)
            
            if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" ]]; then
                # Wait for instance to be running
                log "Waiting for instance to be running..."
                aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                
                # Get instance details
                INSTANCE_INFO=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].{PublicIp:PublicIpAddress,AZ:Placement.AvailabilityZone}' \
                    --output json)
                
                PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIp')
                ACTUAL_AZ=$(echo "$INSTANCE_INFO" | jq -r '.AZ')
                
                # Tag instance with configuration details
                aws ec2 create-tags \
                    --resources "$INSTANCE_ID" \
                    --tags \
                        Key=Name,Value="${STACK_NAME}-gpu-instance" \
                        Key=Project,Value="$PROJECT_NAME" \
                        Key=InstanceType,Value="$SELECTED_INSTANCE_TYPE" \
                        Key=AMI,Value="$SELECTED_AMI" \
                        Key=AMIType,Value="$SELECTED_AMI_TYPE" \
                        Key=AvailabilityZone,Value="$ACTUAL_AZ" \
                        Key=SpotPrice,Value="${CURRENT_PRICE:-unknown}" \
                        Key=Architecture,Value="$(echo "$(get_instance_specs "$SELECTED_INSTANCE_TYPE")" | cut -d: -f5)" \
                        Key=GPUType,Value="$(echo "$(get_instance_specs "$SELECTED_INSTANCE_TYPE")" | cut -d: -f4)" \
                    --region "$AWS_REGION"
                
                success "🎉 Spot instance launched successfully!"
                success "  Instance ID: $INSTANCE_ID"
                success "  Public IP: $PUBLIC_IP"
                success "  Instance Type: $SELECTED_INSTANCE_TYPE"
                success "  AMI: $SELECTED_AMI ($SELECTED_AMI_TYPE)"
                success "  Availability Zone: $ACTUAL_AZ"
                if [[ "$CURRENT_PRICE" != "unknown" ]]; then
                    success "  Spot Price: \$$CURRENT_PRICE/hour"
                fi
                
                # Clean up user data file
                rm -f user-data.sh
                
                # Export for other functions
                export DEPLOYED_INSTANCE_TYPE="$SELECTED_INSTANCE_TYPE"
                export DEPLOYED_AMI="$SELECTED_AMI"
                export DEPLOYED_AMI_TYPE="$SELECTED_AMI_TYPE"
                
                echo "$INSTANCE_ID:$PUBLIC_IP:$ACTUAL_AZ"
                return 0
            else
                warning "Failed to get instance ID from spot request in $AZ"
                continue
            fi
        else
            warning "Spot instance request failed/timed out in $AZ, trying next AZ..."
            aws ec2 cancel-spot-instance-requests --spot-instance-request-ids "$REQUEST_ID" --region "$AWS_REGION" 2>/dev/null || true
            continue
        fi
    done
    
    # If we get here, all AZs failed
    error "❌ Failed to launch spot instance in any availability zone"
    error "This may be due to:"
    error "  1. Capacity constraints across all AZs for selected instance type"
    error "  2. Service quota limits for GPU spot instances"
    error "  3. Current spot prices exceed budget limit"
    error "  4. AMI availability issues in the region"
    error ""
    error "💡 Suggestions:"
    error "  1. Increase --max-spot-price (current: $MAX_SPOT_PRICE)"
    error "  2. Try a different region with better capacity"
    error "  3. Check service quotas for GPU instances"
    error "  4. Try during off-peak hours for better pricing"
    
    # Clean up
    rm -f user-data.sh
    return 1
}

# =============================================================================
# DEBUGGING AND MONITORING FUNCTIONS
# =============================================================================

check_instance_setup_status() {
    local PUBLIC_IP="$1"
    local KEY_FILE="${2:-${KEY_NAME}.pem}"
    local ssh_options="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ControlMaster=auto -o ControlPath=/tmp/ssh-control-status-%h-%p-%r -o ControlPersist=60"
    
    if [[ -z "$PUBLIC_IP" ]]; then
        error "Usage: check_instance_setup_status <PUBLIC_IP> [KEY_FILE]"
        return 1
    fi
    
    log "🔍 Checking setup status for instance at $PUBLIC_IP..."
    
    # Test SSH connectivity
    if ! ssh $ssh_options -i "$KEY_FILE" "ubuntu@$PUBLIC_IP" "echo SSH_READY" &> /dev/null; then
        error "❌ Cannot establish SSH connection to $PUBLIC_IP"
        return 1
    fi
    
    success "✅ SSH connection successful"
    
    # Get comprehensive status with single SSH call
    status_result=$(ssh $ssh_options -i "$KEY_FILE" "ubuntu@$PUBLIC_IP" '
        # Current status
        if [ -f /tmp/user-data-latest-status ]; then
            cat /tmp/user-data-latest-status
        else
            echo "No status file found"
        fi
        
        # Setup completion
        if [ -f /tmp/user-data-complete ]; then
            echo "COMPLETE"
        else
            echo "INCOMPLETE"
        fi
        
        # Step count
        ls /tmp/user-data-step-* 2>/dev/null | grep -v ERROR | wc -l || echo "0"
        
        # Errors
        ls /tmp/user-data-step-*ERROR* 2>/dev/null | head -1 || echo "NO_ERRORS"
        
        # Completed steps list
        echo "=== COMPLETED STEPS ==="
        ls /tmp/user-data-step-* 2>/dev/null | grep -v ERROR | while read step; do 
            echo "$(basename "$step" | cut -d- -f4-)"
        done || echo "No steps completed"
        
        # System status
        echo "=== SYSTEM STATUS ==="
        
        # Docker
        if docker info >/dev/null 2>&1; then
            echo "Docker: running"
        else
            echo "Docker: not running"
        fi
        
        # GPU
        if nvidia-smi >/dev/null 2>&1; then
            echo "GPU: available"
        else
            echo "GPU: not available"
        fi
        
        # Services (if setup complete)
        if [ -f /tmp/user-data-complete ]; then
            echo "=== SERVICE STATUS ==="
            for port_name in "5678:n8n" "11434:ollama" "6333:qdrant" "11235:crawl4ai"; do
                port=$(echo "$port_name" | cut -d: -f1)
                name=$(echo "$port_name" | cut -d: -f2)
                status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health" 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/healthz" 2>/dev/null || echo "unreachable")
                echo "$name (port $port): $status"
            done
        fi
    ' 2>/dev/null || echo "Could not retrieve status information")
    
    # Parse results
    local current_status=""
    local completion_status=""
    local completed_steps="0"
    local error_files=""
    local parsing_mode="status"
    
    while IFS= read -r line; do
        case "$parsing_mode" in
            "status")
                if [[ "$line" == "COMPLETE" || "$line" == "INCOMPLETE" ]]; then
                    completion_status="$line"
                    parsing_mode="steps"
                elif [[ "$line" =~ ^[0-9]+$ ]]; then
                    completed_steps="$line"
                    parsing_mode="errors"
                else
                    current_status="$line"
                fi
                ;;
            "steps")
                if [[ "$line" =~ ^[0-9]+$ ]]; then
                    completed_steps="$line"
                    parsing_mode="errors"
                fi
                ;;
            "errors")
                if [[ "$line" == "=== COMPLETED STEPS ===" ]]; then
                    parsing_mode="completed_list"
                elif [[ "$line" != "NO_ERRORS" ]]; then
                    error_files="$line"
                fi
                ;;
            "completed_list")
                if [[ "$line" == "=== SYSTEM STATUS ===" ]]; then
                    parsing_mode="system"
                elif [[ "$line" != "No steps completed" ]]; then
                    echo "  ✅ $line"
                fi
                ;;
            "system")
                if [[ "$line" == "=== SERVICE STATUS ===" ]]; then
                    parsing_mode="services"
                elif [[ "$line" =~ ^(Docker|GPU): ]]; then
                    echo "  $line"
                fi
                ;;
            "services")
                if [[ "$line" =~ .*\(port.*\): ]]; then
                    local service_name=$(echo "$line" | cut -d'(' -f1 | xargs)
                    local service_status=$(echo "$line" | cut -d':' -f3 | xargs)
                    if [[ "$service_status" =~ ^2[0-9][0-9]$ ]]; then
                        echo "  $service_name: ✅ healthy"
                    else
                        echo "  $service_name: ❌ not responding (status: $service_status)"
                    fi
                fi
                ;;
        esac
    done <<< "$status_result"
    
    # Display summary
    echo -e "${BLUE}📊 Current Status:${NC} $current_status"
    
    if [[ "$completion_status" == "COMPLETE" ]]; then
        success "🎉 Setup completed successfully!"
    else
        warning "⏳ Setup still in progress or failed"
    fi
    
    echo -e "${BLUE}📈 Progress:${NC} $completed_steps/12 steps completed"
    
    if [[ -n "$error_files" && "$error_files" != "NO_ERRORS" ]]; then
        error "❌ Errors detected in setup process:"
        echo "$error_files"
        
        # Get error details
        error_details=$(ssh $ssh_options -i "$KEY_FILE" "ubuntu@$PUBLIC_IP" "cat /var/log/user-data-progress.log 2>/dev/null | grep ERROR -A 3 -B 1 | tail -10" 2>/dev/null)
        if [[ -n "$error_details" ]]; then
            echo -e "${RED}Recent error details:${NC}"
            echo "$error_details"
        fi
    else
        success "✅ No errors detected"
    fi
    
    echo -e "${BLUE}📋 Completed steps:${NC}"
    # Steps were already displayed during parsing
    
    echo -e "${BLUE}🔧 System Status:${NC}"
    # System status was already displayed during parsing
    
    if [[ "$completion_status" == "COMPLETE" ]]; then
        echo -e "${BLUE}🌐 Service Status:${NC}"
        # Service status was already displayed during parsing
    fi
    
    # Close SSH control connection
    ssh $ssh_options -O exit "ubuntu@$PUBLIC_IP" 2>/dev/null || true
    
    echo ""
    echo -e "${YELLOW}💡 For detailed logs, run:${NC}"
    echo "ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
    echo "Then check:"
    echo "  - sudo tail -f /var/log/user-data.log"
    echo "  - cat /var/log/user-data-progress.log"
    echo "  - ls -la /tmp/user-data-*"
}

# =============================================================================
# DEPLOYMENT RESULTS DISPLAY
# =============================================================================

display_results() {
    local PUBLIC_IP="$1"
    local INSTANCE_ID="$2"
    local EFS_DNS="$3"
    local INSTANCE_AZ="$4"
    
    # Get deployed configuration info
    local DEPLOYED_TYPE="${DEPLOYED_INSTANCE_TYPE:-$INSTANCE_TYPE}"
    local DEPLOYED_AMI_ID="${DEPLOYED_AMI:-unknown}"
    local DEPLOYED_AMI_TYPE="${DEPLOYED_AMI_TYPE:-unknown}"
    
    # Get instance specs
    local SPECS="$(get_instance_specs "$DEPLOYED_TYPE")"
    if [[ -z "$SPECS" ]]; then
        SPECS="unknown:unknown:unknown:unknown:unknown:unknown"
    fi
    IFS=':' read -r vcpus ram gpus gpu_type cpu_arch storage <<< "$SPECS"
    
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}   🚀 AI STARTER KIT DEPLOYED!    ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${BLUE}🎯 Intelligent Configuration Selected:${NC}"
    echo -e "  Instance Type: ${YELLOW}$DEPLOYED_TYPE${NC}"
    echo -e "  vCPUs: ${YELLOW}$vcpus${NC} | RAM: ${YELLOW}${ram}GB${NC} | GPUs: ${YELLOW}$gpus x $gpu_type${NC}"
    echo -e "  Architecture: ${YELLOW}$cpu_arch${NC} | Storage: ${YELLOW}$storage${NC}"
    echo -e "  AMI: ${YELLOW}$DEPLOYED_AMI_ID${NC} ($DEPLOYED_AMI_TYPE)"
    local perf_score="$(get_performance_score "$DEPLOYED_TYPE")"
    if [[ -z "$perf_score" || "$perf_score" == "0" ]]; then
        perf_score="N/A"
    fi
    echo -e "  Performance Score: ${YELLOW}${perf_score}/100${NC}"
    echo ""
    echo -e "${BLUE}📍 Deployment Location:${NC}"
    echo -e "  Instance ID: ${YELLOW}$INSTANCE_ID${NC}"
    echo -e "  Public IP: ${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  Availability Zone: ${YELLOW}$INSTANCE_AZ${NC}"
    echo -e "  Region: ${YELLOW}$AWS_REGION${NC}"
    echo -e "  EFS DNS: ${YELLOW}$EFS_DNS${NC}"
    echo ""
    echo -e "${BLUE}🌐 Service URLs:${NC}"
    echo -e "  ${GREEN}n8n Workflow Editor:${NC}     http://$PUBLIC_IP:5678"
    echo -e "  ${GREEN}Crawl4AI Web Scraper:${NC}    http://$PUBLIC_IP:11235"
    echo -e "  ${GREEN}Qdrant Vector Database:${NC}  http://$PUBLIC_IP:6333"
    echo -e "  ${GREEN}Ollama AI Models:${NC}        http://$PUBLIC_IP:11434"
    echo ""
    echo -e "${BLUE}🔐 SSH Access:${NC}"
    echo -e "  ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
    echo ""
    
    # Show architecture-specific benefits
    if [[ "$cpu_arch" == "ARM" ]]; then
        echo -e "${BLUE}🔧 ARM64 Graviton2 Benefits:${NC}"
        echo -e "  ${GREEN}✓${NC} Up to 40% better price-performance than x86"
        echo -e "  ${GREEN}✓${NC} Lower power consumption"
        echo -e "  ${GREEN}✓${NC} Custom ARM-optimized Deep Learning AMI"
        echo -e "  ${GREEN}✓${NC} NVIDIA T4G Tensor Core GPUs"
        echo -e "  ${YELLOW}⚠${NC} Some software may require ARM64 compatibility"
    else
        echo -e "${BLUE}🔧 Intel x86_64 Benefits:${NC}"
        echo -e "  ${GREEN}✓${NC} Universal software compatibility"
        echo -e "  ${GREEN}✓${NC} Mature ecosystem and optimizations"
        echo -e "  ${GREEN}✓${NC} NVIDIA T4 Tensor Core GPUs"
        echo -e "  ${GREEN}✓${NC} High-performance Intel Xeon processors"
    fi
    
    echo ""
    echo -e "${BLUE}🤖 Deep Learning AMI Features:${NC}"
    echo -e "  ${GREEN}✓${NC} Pre-installed NVIDIA drivers (optimized versions)"
    echo -e "  ${GREEN}✓${NC} Docker with NVIDIA container runtime"
    echo -e "  ${GREEN}✓${NC} CUDA toolkit and cuDNN libraries"
    echo -e "  ${GREEN}✓${NC} Python ML frameworks (TensorFlow, PyTorch, etc.)"
    echo -e "  ${GREEN}✓${NC} Conda environments for different frameworks"
    echo -e "  ${GREEN}✓${NC} Jupyter notebooks and development tools"
    echo ""
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo -e "  1. ${CYAN}Wait 5-10 minutes${NC} for all services to fully start"
    echo -e "  2. ${CYAN}Access n8n${NC} at http://$PUBLIC_IP:5678 to set up workflows"
    echo -e "  3. ${CYAN}Check GPU status${NC}: ssh to instance and run '/usr/local/bin/gpu-check.sh'"
    echo -e "  4. ${CYAN}Check service logs${NC}: ssh to instance and run 'docker-compose logs'"
    echo -e "  5. ${CYAN}Configure API keys${NC} in .env file for enhanced features"
    echo ""
    echo -e "${YELLOW}💰 Cost Optimization:${NC}"
    if [[ -n "${SELECTED_PRICE:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} Spot instance selected at ~\$${SELECTED_PRICE}/hour"
        local daily_cost=$(echo "scale=2; $SELECTED_PRICE * 24" | bc -l 2>/dev/null || echo "N/A")
        if [[ "$daily_cost" != "N/A" ]]; then
            echo -e "  ${GREEN}✓${NC} Estimated daily cost: ~\$${daily_cost} (24 hours)"
        fi
    else
        echo -e "  ${GREEN}✓${NC} Spot instance pricing optimized"
    fi
    echo -e "  ${GREEN}✓${NC} ~70% savings vs on-demand pricing"
    echo -e "  ${GREEN}✓${NC} Multi-AZ failover for availability"
    echo -e "  ${GREEN}✓${NC} Intelligent configuration selection"
    echo -e "  ${RED}⚠${NC} Remember to terminate when not in use!"
    echo ""
    echo -e "${BLUE}🎛️ Deployment Features:${NC}"
    echo -e "  ${GREEN}✓${NC} Intelligent AMI and instance selection"
    echo -e "  ${GREEN}✓${NC} Real-time spot pricing analysis"
    echo -e "  ${GREEN}✓${NC} Multi-architecture support (Intel/ARM)"
    echo -e "  ${GREEN}✓${NC} EFS shared storage"
    echo -e "  ${GREEN}✓${NC} Application Load Balancer"
    echo -e "  ${GREEN}✓${NC} CloudFront CDN"
    echo -e "  ${GREEN}✓${NC} CloudWatch monitoring"
    echo -e "  ${GREEN}✓${NC} SSM parameter management"
    echo -e "  ${GREEN}✓${NC} Real-time setup progress tracking"
    echo -e "  ${GREEN}✓${NC} Advanced error detection and debugging"
    echo ""
    echo -e "${PURPLE}🧠 Intelligent Selection Summary:${NC}"
    if [[ "$INSTANCE_TYPE" == "auto" ]]; then
        echo -e "  ${CYAN}Mode:${NC} Automatic optimal configuration selection"
        echo -e "  ${CYAN}Budget:${NC} \$$MAX_SPOT_PRICE/hour maximum"
        echo -e "  ${CYAN}Selection:${NC} $DEPLOYED_TYPE chosen for best price/performance"
    else
        echo -e "  ${CYAN}Mode:${NC} Manual instance type selection"
        echo -e "  ${CYAN}Specified:${NC} $INSTANCE_TYPE"
        echo -e "  ${CYAN}AMI Selection:${NC} Best available AMI auto-selected"
    fi
    echo ""
    echo -e "${BLUE}🔍 Monitoring & Debugging:${NC}"
    echo -e "  ${CYAN}Real-time status check:${NC}     $0 check-status $PUBLIC_IP"
    echo -e "  ${CYAN}Progress logs:${NC}              ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP 'tail -f /var/log/user-data-progress.log'"
    echo -e "  ${CYAN}Full setup logs:${NC}            ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP 'tail -f /var/log/user-data.log'"
    echo -e "  ${CYAN}GPU status:${NC}                 ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP '/usr/local/bin/gpu-check.sh'"
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${BLUE}Happy building with your AI-powered infrastructure! 🚀${NC}"
    echo ""
}

# =============================================================================
# INFRASTRUCTURE SETUP FUNCTIONS
# =============================================================================

cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Use comprehensive cleanup script if available
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/cleanup-stack.sh" ] && [ -n "${STACK_NAME:-}" ]; then
        log "Running comprehensive cleanup for stack: $STACK_NAME"
        "$script_dir/cleanup-stack.sh" "$STACK_NAME" || true
        return
    fi
    
    # Fallback to manual cleanup if no stack name or cleanup script
    # Terminate instance first
    if [ ! -z "${INSTANCE_ID:-}" ]; then
        log "Terminating instance $INSTANCE_ID..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete CloudWatch alarms (if any were created)
    log "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms \
        --alarm-names "${STACK_NAME}-high-gpu-utilization" "${STACK_NAME}-low-gpu-utilization" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Delete CloudFront distribution (takes longest, do early)
    if [ ! -z "${DISTRIBUTION_ID:-}" ]; then
        log "Disabling and deleting CloudFront distribution..."
        # Disable first
        ETAG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
        if [ ! -z "$ETAG" ] && [ "$ETAG" != "None" ]; then
            CONFIG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query DistributionConfig --output json 2>/dev/null) || true
            if [ ! -z "$CONFIG" ]; then
                echo "$CONFIG" | jq '.Enabled = false' > disabled-config.json 2>/dev/null || true
                aws cloudfront update-distribution --id "$DISTRIBUTION_ID" --distribution-config file://disabled-config.json --if-match "$ETAG" 2>/dev/null || true
                aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID" 2>/dev/null || true
                NEW_ETAG=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
                aws cloudfront delete-distribution --id "$DISTRIBUTION_ID" --if-match "$NEW_ETAG" 2>/dev/null || true
            fi
        fi
    fi
    
    # Clean up temporary files
    rm -f user-data.sh trust-policy.json custom-policy.json deploy-app.sh disabled-config.json cloudfront-config.json
}

create_key_pair() {
    log "Setting up SSH key pair..."
    
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        warning "Key pair $KEY_NAME already exists"
        return 0
    fi
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    
    chmod 600 "${KEY_NAME}.pem"
    success "Created SSH key pair: ${KEY_NAME}.pem"
}

retry_with_backoff() {
    local cmd=("$@")
    local max_attempts=5
    local base_delay=1
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Attempt $attempt/$max_attempts: ${cmd[*]}"
        
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            error "Command failed after $max_attempts attempts: ${cmd[*]}"
            return 1
        fi
        
        local delay=$((base_delay * (2 ** (attempt - 1))))
        local jitter=$((RANDOM % 3))
        delay=$((delay + jitter))
        
        warning "Command failed, retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done
}

generate_secure_password() {
    local length=${1:-32}
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

store_ssm_parameter() {
    local param_name="$1"
    local param_value="$2"
    local param_type="${3:-SecureString}"
    local description="$4"
    
    log "Storing parameter: $param_name"
    
    retry_with_backoff aws ssm put-parameter \
        --name "$param_name" \
        --value "$param_value" \
        --type "$param_type" \
        --description "$description" \
        --overwrite \
        --region "$AWS_REGION" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        success "Stored parameter: $param_name"
    else
        error "Failed to store parameter: $param_name"
        return 1
    fi
}

get_ssm_parameter() {
    local param_name="$1"
    local default_value="${2:-}"
    
    local value
    value=$(aws ssm get-parameter \
        --name "$param_name" \
        --with-decryption \
        --region "$AWS_REGION" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ "$value" != "None" ]] && [[ -n "$value" ]]; then
        echo "$value"
    else
        if [[ -n "$default_value" ]]; then
            log "Parameter $param_name not found, using default"
            echo "$default_value"
        else
            warning "Parameter $param_name not found and no default provided"
            return 1
        fi
    fi
}

setup_secure_credentials() {
    log "Setting up secure credential management..."
    
    local base_path="/aibuildkit"
    local postgres_password
    local n8n_encryption_key
    local openai_api_key
    local webhook_url
    
    postgres_password=$(get_ssm_parameter "$base_path/POSTGRES_PASSWORD")
    if [[ -z "$postgres_password" ]]; then
        postgres_password=$(generate_secure_password 24)
        store_ssm_parameter "$base_path/POSTGRES_PASSWORD" "$postgres_password" "SecureString" "PostgreSQL database password for AI Starter Kit"
    fi
    
    n8n_encryption_key=$(get_ssm_parameter "$base_path/n8n/ENCRYPTION_KEY")
    if [[ -z "$n8n_encryption_key" ]]; then
        n8n_encryption_key=$(generate_secure_password 32)
        store_ssm_parameter "$base_path/n8n/ENCRYPTION_KEY" "$n8n_encryption_key" "SecureString" "n8n encryption key for secure workflow storage"
    fi
    
    openai_api_key=$(get_ssm_parameter "$base_path/OPENAI_API_KEY")
    if [[ -z "$openai_api_key" ]]; then
        warning "OpenAI API key not found in SSM. Please set it manually:"
        warning "aws ssm put-parameter --name '$base_path/OPENAI_API_KEY' --value 'your-api-key' --type SecureString --region $AWS_REGION"
    fi
    
    webhook_url=$(get_ssm_parameter "$base_path/WEBHOOK_URL")
    if [[ -z "$webhook_url" ]]; then
        log "Webhook URL not set in SSM. This is optional for basic functionality."
    fi
    
    export POSTGRES_PASSWORD="$postgres_password"
    export N8N_ENCRYPTION_KEY="$n8n_encryption_key"
    export OPENAI_API_KEY="$openai_api_key"
    export WEBHOOK_URL="$webhook_url"
    
    success "Secure credentials configured"
}

setup_infrastructure_parallel() {
    log "Setting up infrastructure components in parallel..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    local key_pair_file="$temp_dir/key_pair"
    local iam_role_file="$temp_dir/iam_role"
    local security_group_file="$temp_dir/security_group"
    
    {
        create_key_pair 2>&1 && echo "SUCCESS" > "$key_pair_file"
    } &
    local key_pair_pid=$!
    
    {
        create_iam_role 2>&1 && echo "SUCCESS" > "$iam_role_file"
    } &
    local iam_role_pid=$!
    
    {
        SG_ID=$(create_security_group 2>&1)
        if [[ $? -eq 0 ]] && [[ -n "$SG_ID" ]]; then
            echo "$SG_ID" > "$security_group_file"
        else
            echo "FAILED" > "$security_group_file"
        fi
    } &
    local security_group_pid=$!
    
    log "Waiting for parallel infrastructure creation to complete..."
    
    local failed_components=()
    
    if ! wait "$key_pair_pid"; then
        failed_components+=("key_pair")
    elif [[ ! -f "$key_pair_file" ]] || [[ "$(cat "$key_pair_file")" != "SUCCESS" ]]; then
        failed_components+=("key_pair")
    fi
    
    if ! wait "$iam_role_pid"; then
        failed_components+=("iam_role")
    elif [[ ! -f "$iam_role_file" ]] || [[ "$(cat "$iam_role_file")" != "SUCCESS" ]]; then
        failed_components+=("iam_role")
    fi
    
    if ! wait "$security_group_pid"; then
        failed_components+=("security_group")
    elif [[ ! -f "$security_group_file" ]] || [[ "$(cat "$security_group_file")" == "FAILED" ]]; then
        failed_components+=("security_group")
    fi
    
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        error "Failed to create infrastructure components: ${failed_components[*]}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    local sg_id
    sg_id=$(cat "$security_group_file")
    
    success "Parallel infrastructure setup completed successfully"
    log "Security Group ID: $sg_id"
    
    log "Creating EFS file system..."
    local efs_dns
    efs_dns=$(create_efs "$sg_id")
    
    if [[ -z "$efs_dns" ]] || [[ "$efs_dns" == "None" ]]; then
        error "Failed to create EFS file system"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
    
    echo "$sg_id:$efs_dns"
}

get_caller_ip() {
    local caller_ip
    caller_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || \
                curl -s --max-time 10 icanhazip.com 2>/dev/null || \
                curl -s --max-time 10 checkip.amazonaws.com 2>/dev/null)
    
    if [[ -z "$caller_ip" ]] || [[ ! "$caller_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        warning "Could not determine caller IP, using 0.0.0.0/0 for SSH access"
        echo "0.0.0.0/0"
    else
        log "Detected caller IP: $caller_ip"
        echo "$caller_ip/32"
    fi
}

test_service_endpoint() {
    local host="$1"
    local port="$2"
    local service_name="$3"
    local health_path="${4:-/health}"
    
    local url="http://$host:$port$health_path"
    local response
    local http_code
    local timing
    
    timing=$(time (
        response=$(curl -s --max-time 10 --connect-timeout 5 -w "%{http_code}" "$url" 2>/dev/null || echo "connection_failed")
    ) 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    
    if [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
        if [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]]; then
            local response_time
            response_time=$(echo "$timing" | grep -o '[0-9]*\.[0-9]*s' | head -n1 | sed 's/s//')
            echo "✓ $service_name ($host:$port): HTTP $http_code (${response_time:-unknown}s)"
            return 0
        else
            echo "✗ $service_name ($host:$port): HTTP $http_code (error response)"
            return 1
        fi
    else
        echo "✗ $service_name ($host:$port): Connection failed"
        return 1
    fi
}

get_docker_service_info() {
    local host="$1"
    
    log "Gathering Docker service information from $host..."
    
    ssh -i "${KEY_NAME}.pem" -o StrictHostKeyChecking=no ubuntu@"$host" '
        echo "=== DOCKER CONTAINERS ==="
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not available"
        
        echo ""
        echo "=== DOCKER STATS ==="
        timeout 5 docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || echo "Docker stats not available"
        
        echo ""
        echo "=== DOCKER LOGS (last 10 lines per service) ==="
        for service in n8n ollama qdrant crawl4ai postgres; do
            echo "--- $service ---"
            docker logs --tail 10 "$service" 2>/dev/null || echo "No logs for $service"
        done
        
        echo ""
        echo "=== SYSTEM RESOURCES ==="
        echo "Memory:"
        free -h 2>/dev/null || echo "Memory info not available"
        echo "Disk:"
        df -h / 2>/dev/null || echo "Disk info not available"
        echo "Load:"
        uptime 2>/dev/null || echo "Load info not available"
        
        if command -v nvidia-smi >/dev/null 2>&1; then
            echo ""
            echo "=== GPU STATUS ==="
            nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "GPU info not available"
        fi
    ' 2>/dev/null || echo "Could not gather Docker service information"
}

enhanced_health_check() {
    local host="$1"
    local max_attempts="${2:-10}"
    local attempt=1
    
    log "Starting enhanced health check for $host..."
    
    local services=(
        "5678:n8n:/healthz"
        "11434:ollama:/api/tags"
        "6333:qdrant:/health"
        "11235:crawl4ai:/health"
    )
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Health check attempt $attempt/$max_attempts"
        
        local all_healthy=true
        local failed_services=()
        
        for service_config in "${services[@]}"; do
            local port=$(echo "$service_config" | cut -d: -f1)
            local name=$(echo "$service_config" | cut -d: -f2)
            local path=$(echo "$service_config" | cut -d: -f3)
            
            if ! test_service_endpoint "$host" "$port" "$name" "$path"; then
                all_healthy=false
                failed_services+=("$name")
            fi
        done
        
        if [[ "$all_healthy" == true ]]; then
            success "All services are healthy on $host"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            error "Health check failed after $max_attempts attempts"
            error "Failed services: ${failed_services[*]}"
            
            log "Gathering diagnostic information..."
            get_docker_service_info "$host"
            
            return 1
        fi
        
        local delay=$((30 + (attempt * 10)))
        warning "Services not ready: ${failed_services[*]}. Retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done
}

comprehensive_service_diagnostics() {
    local host="$1"
    
    log "Running comprehensive service diagnostics for $host..."
    
    echo "=== SERVICE ENDPOINT TESTS ==="
    test_service_endpoint "$host" "5678" "n8n" "/healthz"
    test_service_endpoint "$host" "11434" "ollama" "/api/tags"
    test_service_endpoint "$host" "6333" "qdrant" "/health"
    test_service_endpoint "$host" "11235" "crawl4ai" "/health"
    
    echo ""
    echo "=== DOCKER SERVICE INFORMATION ==="
    get_docker_service_info "$host"
    
    echo ""
    echo "=== NETWORK CONNECTIVITY ==="
    for port in 5678 11434 6333 11235; do
        if nc -z "$host" "$port" 2>/dev/null; then
            echo "✓ Port $port: Open"
        else
            echo "✗ Port $port: Closed or filtered"
        fi
    done
}

create_security_group() {
    log "Creating enhanced security group with IP whitelisting..."
    
    # Get VPC ID first
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        error "Failed to retrieve default VPC ID"
        return 1
    fi
    
    # Get caller's IP for SSH whitelisting
    CALLER_IP=$(get_caller_ip)
    
    # Check if security group exists
    SG_ID=$(aws ec2 describe-security-groups \
        --group-names "${STACK_NAME}-sg" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -oE 'sg-[0-9a-fA-F]+' | head -n1)
    
    
    if [[ -z "$SG_ID" ]]; then
        # Create security group
        SG_ID=$(aws ec2 create-security-group \
            --group-name "${STACK_NAME}-sg" \
            --description "Security group for AI Starter Kit Intelligent Deployment" \
            --vpc-id "$VPC_ID" \
            --region "$AWS_REGION" \
            --query 'GroupId' \
            --output text)
        if [[ -z "$SG_ID" ]]; then
            error "Failed to create security group"
            return 1
        fi
    fi
    
    # Validate SG_ID format
    if [[ ! "$SG_ID" =~ ^sg-[0-9a-fA-F]+$ ]]; then
        error "Invalid security group ID: $SG_ID"
        return 1
    fi
    
    # Add security group rules with duplicate protection
    add_sg_rule_if_not_exists() {
        local sg_id="$1"
        local protocol="$2"
        local port="$3"
        local source_type="$4"
        local source_value="$5"
        
        # Check if rule already exists
        local existing_rule
        if [[ "$source_type" == "cidr" ]]; then
            existing_rule=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --region "$AWS_REGION" \
                --query "SecurityGroups[0].IpPermissions[?IpProtocol=='$protocol' && FromPort==$port && ToPort==$port && IpRanges[?CidrIp=='$source_value']]" \
                --output text 2>/dev/null)
        else
            existing_rule=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --region "$AWS_REGION" \
                --query "SecurityGroups[0].IpPermissions[?IpProtocol=='$protocol' && FromPort==$port && ToPort==$port && UserIdGroupPairs[?GroupId=='$source_value']]" \
                --output text 2>/dev/null)
        fi
        
        if [[ -z "$existing_rule" ]]; then
            if [[ "$source_type" == "cidr" ]]; then
                aws ec2 authorize-security-group-ingress \
                    --group-id "$sg_id" \
                    --protocol "$protocol" \
                    --port "$port" \
                    --cidr "$source_value" \
                    --region "$AWS_REGION" >/dev/null 2>&1 && \
                log "Added rule: $protocol/$port from $source_value" || \
                warning "Failed to add rule: $protocol/$port from $source_value"
            else
                aws ec2 authorize-security-group-ingress \
                    --group-id "$sg_id" \
                    --protocol "$protocol" \
                    --port "$port" \
                    --source-group "$source_value" \
                    --region "$AWS_REGION" >/dev/null 2>&1 && \
                log "Added rule: $protocol/$port from group $source_value" || \
                warning "Failed to add rule: $protocol/$port from group $source_value"
            fi
        fi
    }
    
    log "Adding security group rules with enhanced security..."
    
    # Essential inbound rules (with duplicate protection)
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "22" "cidr" "$CALLER_IP"      # SSH
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "80" "cidr" "0.0.0.0/0"       # HTTP
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "443" "cidr" "0.0.0.0/0"      # HTTPS
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "5678" "cidr" "$CALLER_IP"    # n8n
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "6333" "cidr" "$CALLER_IP"    # Qdrant
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "11434" "cidr" "$CALLER_IP"   # Ollama
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "11235" "cidr" "$CALLER_IP"   # Crawl4AI
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "5432" "group" "$SG_ID"       # PostgreSQL
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "2049" "group" "$SG_ID"      # NFS for EFS
    
    success "Created security group: $SG_ID"
    echo "$SG_ID" | tr -d '\n\r\t '
}

create_iam_role() {
    log "Creating IAM role for EC2 instances..."
    
    # Check if role exists
    if aws iam get-role --role-name "${STACK_NAME}-role" &> /dev/null; then
        warning "IAM role already exists"
        return 0
    fi        warning "Failed to register instance to n8n target group, but continuing..."
    }
    
    success "Created n8n target group: $TARGET_GROUP_ARN"
    echo "$TARGET_GROUP_ARN"
}

create_qdrant_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for qdrant..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    QDRANT_TG_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-qdrant-tg" \
        --protocol HTTP \
        --port 6333 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 6333 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to target group
    aws elbv2 register-targets \
        --target-group-arn "$QDRANT_TG_ARN" \
        --targets "Id=$INSTANCE_ID,Port=6333" \
        --region "$AWS_REGION" || {
        warning "Failed to register instance to qdrant target group, but continuing..."
    }
    
    success "Created qdrant target group: $QDRANT_TG_ARN"
    echo "$QDRANT_TG_ARN"
}

create_alb() {
    local SG_ID="$1"
    local TARGET_GROUP_ARN="$2"
    local QDRANT_TG_ARN="$3"
    
    log "Creating Application Load Balancer..."
    
    # Get subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --subnets $SUBNETS \
        --security-groups "$SG_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create listener for n8n (default)
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    # Create listener for qdrant
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 6333 \
        --default-actions Type=forward,TargetGroupArn="$QDRANT_TG_ARN" \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    export ALB_ARN
    success "Created ALB: $ALB_DNS"
    echo "$ALB_DNS"
}

setup_cloudfront() {
    local ALB_DNS="$1"
    
    log "Setting up CloudFront CDN..."
    
    # Create CloudFront distribution config file
    cat > cloudfront-config.json << EOF
{
    "CallerReference": "${STACK_NAME}-$(date +%s)",
    "Comment": "CloudFront distribution for AI Starter Kit",
    "DefaultCacheBehavior": {
        "TargetOriginId": "ALBOrigin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": true,
            "Headers": {
    # Create CloudFront distribution
    DISTRIBUTION_CONFIG='{
        "CallerReference": "'${STACK_NAME}'-'$(date +%s)'",
        "Comment": "CloudFront distribution for GeuseMaker",
        "DefaultCacheBehavior": {
            "TargetOriginId": "ALBOrigin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 7,
                "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                }
            },
            "ForwardedValues": {
                "QueryString": true,
                "Headers": {
                    "Quantity": 0
                }
            },
            "TrustedSigners": {
                "Enabled": false,
                "Quantity": 0
            },
            "Cookies": {
                "Forward": "none"
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "MinTTL": 0
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "ALBOrigin",
                "DomainName": "$ALB_DNS",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only"
                }
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}
EOF
    
    # Validate the CloudFront config file was created properly
    if [[ ! -f "cloudfront-config.json" ]]; then
        error "CloudFront config file was not created"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty cloudfront-config.json 2>/dev/null; then
        error "Invalid JSON in CloudFront config file"
        cat cloudfront-config.json
        return 1
    fi
    
    DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config file://cloudfront-config.json \
        --region "$AWS_REGION" \
        --query 'Distribution.Id' \
        --output text)
    
    DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --region "$AWS_REGION" \
        --query 'Distribution.DomainName' \
        --output text)
    
    export DISTRIBUTION_ID
    export DISTRIBUTION_DOMAIN
    success "Created CloudFront distribution: $DISTRIBUTION_DOMAIN"
}

wait_for_instance_ready() {
    local PUBLIC_IP="$1"
    
    log "🚀 Starting enhanced 3-phase instance readiness check..."
    
    local ssh_options="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ControlMaster=auto -o ControlPath=/tmp/ssh-control-%h-%p-%r -o ControlPersist=300"
    
    # =======================================================================
    # PHASE 1: SSH Connectivity (20 attempts, 15s each = 5 minutes max)
    # =======================================================================
    info "📡 Phase 1: Establishing SSH connectivity..."
    local ssh_ready=false
    
    for attempt in {1..20}; do
        if ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" "echo SSH_READY" &> /dev/null; then
            success "✅ SSH connection established! (attempt $attempt/20)"
            ssh_ready=true
            break
        fi
        
        # Progress indicator
        local progress=$((attempt * 5))
        info "🔄 SSH attempt $attempt/20 (${progress}%): Waiting for network interface... (${attempt}m${((attempt-1)*15%60)}s elapsed)"
        sleep 15
    done
    
    if [ "$ssh_ready" = false ]; then
        error "❌ SSH connectivity failed after 5 minutes"
        log "🔍 Checking EC2 instance status..."
        
        # Try to get instance status for debugging
        if command -v aws &> /dev/null; then
            local instance_id=$(aws ec2 describe-instances \
                --filters "Name=ip-address,Values=$PUBLIC_IP" \
                --region "$AWS_REGION" \
                --query 'Reservations[0].Instances[0].InstanceId' \
                --output text 2>/dev/null || echo "unknown")
            
            if [[ "$instance_id" != "unknown" && "$instance_id" != "None" ]]; then
                info "Instance ID: $instance_id"
                aws ec2 describe-instances --instance-ids "$instance_id" --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].{State:State.Name,Status:InstanceStatus.Status}' \
                    --output table 2>/dev/null || true
            fi
        fi
        
        echo -e "${YELLOW}Troubleshooting steps:${NC}"
        echo "1. Check security group allows SSH (port 22) from your IP"
        echo "2. Verify the instance is running: aws ec2 describe-instances --instance-ids <instance-id>"
        echo "3. Check system logs: aws ec2 get-console-output --instance-id <instance-id>"
        return 1
    fi
    
    # =======================================================================
    # PHASE 2: Cloud-init completion (40 attempts, 30s each = 20 minutes max)
    # =======================================================================
    info "☁️  Phase 2: Waiting for cloud-init completion..."
    local cloud_init_ready=false
    
    for attempt in {1..40}; do
        # Check cloud-init status with timeout
        local cloud_init_status=$(ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" \
            "timeout 10 cloud-init status --wait 2>/dev/null || echo 'timeout'" 2>/dev/null || echo "connection_failed")
        
        if [[ "$cloud_init_status" == *"done"* ]]; then
            success "✅ Cloud-init completed successfully! (attempt $attempt/40)"
            cloud_init_ready=true
            break
        elif [[ "$cloud_init_status" == "timeout" ]]; then
            # Still running
            local progress=$((attempt * 100 / 40))
            info "🔄 Cloud-init attempt $attempt/40 (${progress}%): Still initializing system... (${attempt}min elapsed)"
        elif [[ "$cloud_init_status" == "connection_failed" ]]; then
            warning "⚠️  SSH connection temporarily lost (attempt $attempt/40) - instance may be rebooting"
        else
            # Check for errors
            if [[ "$cloud_init_status" == *"error"* ]]; then
                error "❌ Cloud-init failed with error: $cloud_init_status"
                return 1
            fi
            info "🔄 Cloud-init status (attempt $attempt/40): $cloud_init_status"
        fi
        
        sleep 30
    done
    
    if [ "$cloud_init_ready" = false ]; then
        error "❌ Cloud-init failed to complete after 20 minutes"
        
        # Get diagnostic information
        local diagnostic_info=$(ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" '
            echo "=== CLOUD-INIT STATUS ==="
            cloud-init status || echo "Status check failed"
            echo "=== CLOUD-INIT LOGS (last 20 lines) ==="
            sudo tail -20 /var/log/cloud-init.log 2>/dev/null || echo "No cloud-init.log available"
            echo "=== CLOUD-INIT OUTPUT LOGS (last 20 lines) ==="
            sudo tail -20 /var/log/cloud-init-output.log 2>/dev/null || echo "No cloud-init-output.log available"
        ' 2>/dev/null || echo "Could not retrieve diagnostic information")
        
        echo -e "${RED}Diagnostic information:${NC}"
        echo "$diagnostic_info"
        return 1
    fi
    
    # =======================================================================
    # PHASE 3: User-data completion (60 attempts, 30s each = 30 minutes max)
    # =======================================================================
    info "📜 Phase 3: Waiting for user-data script completion..."
    local setup_complete=false
    local last_status=""
    
    for attempt in {1..60}; do
        # Use single SSH connection to check multiple things efficiently
        local ssh_result=$(ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" '
            # Check if setup is complete
            if [ -f /tmp/user-data-complete ]; then
                echo "COMPLETE"
            else
                echo "RUNNING"
            fi
            
            # Get current status (if available)
            if [ -f /tmp/user-data-latest-status ]; then
                cat /tmp/user-data-latest-status
            else
                echo "User-data script initializing..."
            fi
            
            # Check for errors
            ls /tmp/user-data-step-*ERROR* 2>/dev/null | head -1 || echo "NO_ERRORS"
            
            # Get completed step count
            ls /tmp/user-data-step-* 2>/dev/null | grep -v ERROR | wc -l || echo "0"
            
            # Get system resource status
            echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1 || echo "N/A")% | RAM: $(free | grep Mem | awk "{printf \"%.1f\", \$3/\$2 * 100.0}" || echo "N/A")%"
        ' 2>/dev/null || echo -e "CONNECTION_ISSUE\nConnection issue\nNO_ERRORS\n0\nSystem: N/A")
        
        # Parse the results
        IFS=$'\n' read -d '' -r completion_status current_status error_check completed_steps system_status <<< "$ssh_result" || true
        
        # Check if setup is complete
        if [[ "$completion_status" == "COMPLETE" ]]; then
            success "🎉 User-data script completed successfully! (attempt $attempt/60)"
            setup_complete=true
            break
        fi
        
        # Handle connection issues
        if [[ "$completion_status" == "CONNECTION_ISSUE" ]]; then
            if (( attempt % 3 == 0 )); then  # Only log every 3rd connection issue
                warning "⚠️  SSH connection issue (attempt $attempt/60) - instance may be under heavy load"
            fi
        else
            # Enhanced progress reporting
            local progress=$((attempt * 100 / 60))
            local elapsed_min=$((attempt / 2))
            
            # Only log if status changed or every 5 attempts
            if [[ "$current_status" != "$last_status" ]] || (( attempt % 5 == 0 )); then
                if [[ "$current_status" == "User-data script initializing..." ]]; then
                    info "🔄 User-data attempt $attempt/60 (${progress}%): Starting deployment script... (${elapsed_min}min elapsed)"
                else
                    info "📊 User-data attempt $attempt/60 (${progress}%): $current_status | $system_status (${elapsed_min}min elapsed)"
                fi
                last_status="$current_status"
                
                # Show step progress
                if [[ "$completed_steps" =~ ^[0-9]+$ ]] && [ "$completed_steps" -gt 0 ]; then
                    info "✅ Completed setup steps: $completed_steps/12"
                fi
            fi
            
            # Check for errors
            if [[ -n "$error_check" && "$error_check" != "NO_ERRORS" ]]; then
                error "❌ User-data script failed - error detected!"
                
                # Get detailed error information
                local error_details=$(ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" '
                    echo "=== ERROR DETAILS ==="
                    ls /tmp/user-data-step-*ERROR* 2>/dev/null | while read error_file; do
                        echo "Error file: $error_file"
                        cat "$error_file" 2>/dev/null || echo "Could not read error file"
                        echo "---"
                    done
                    echo "=== USER-DATA LOG (last 30 lines) ==="
                    tail -30 /var/log/user-data.log 2>/dev/null || echo "No user-data.log available"
                    echo "=== PROGRESS LOG (last 20 lines) ==="
                    tail -20 /var/log/user-data-progress.log 2>/dev/null || echo "No progress log available"
                ' 2>/dev/null || echo "Could not retrieve error details")
                
                echo -e "${RED}Error details:${NC}"
                echo "$error_details"
                
                echo -e "${YELLOW}For debugging, SSH into the instance:${NC}"
                echo "ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
                echo -e "${YELLOW}Check these files for troubleshooting:${NC}"
                echo "  - /var/log/user-data.log (complete setup log)"
                echo "  - /var/log/user-data-progress.log (progress tracking)"
                echo "  - /tmp/user-data-step-* (individual step status)"
                echo "  - /var/log/cloud-init-output.log (cloud-init output)"
                
                return 1
            fi
        fi
        
        sleep 30
    done
    
    if [ "$setup_complete" = false ]; then
        error "❌ User-data script failed to complete after 30 minutes"
        
        # Comprehensive final diagnostic
        local final_info=$(ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" '
            echo "=== FINAL DIAGNOSTIC REPORT ==="
            echo "Timestamp: $(date)"
            echo ""
            echo "=== CURRENT STATUS ==="
            cat /tmp/user-data-latest-status 2>/dev/null || echo "No status file available"
            echo ""
            echo "=== STEP COMPLETION ==="
            echo "Completed steps: $(ls /tmp/user-data-step-* 2>/dev/null | grep -v ERROR | wc -l)/12"
            echo "Error steps: $(ls /tmp/user-data-step-*ERROR* 2>/dev/null | wc -l)"
            echo ""
            echo "=== SYSTEM RESOURCES ==="
            echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1 || echo "N/A")%"
            echo "Memory: $(free -h | grep Mem | awk "{print \$3\"/\"\$2\" (\"\$3/\$2*100\"%)\"}") used"
            echo "Disk: $(df -h / | tail -1 | awk "{print \$3\"/\"\$2\" (\"\$5\")\"}")"
            echo ""
            echo "=== RECENT LOG ENTRIES ==="
            tail -30 /var/log/user-data.log 2>/dev/null || echo "No user-data.log available"
        ' 2>/dev/null || echo "Could not retrieve final diagnostic information")
        
        echo -e "${RED}Final diagnostic information:${NC}"
        echo "$final_info"
        
        echo -e "${YELLOW}For debugging, SSH into the instance:${NC}"
        echo "ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
        echo -e "${YELLOW}Recommended troubleshooting steps:${NC}"
        echo "1. Check /var/log/user-data.log for detailed setup logs"
        echo "2. Review /var/log/user-data-progress.log for progress tracking"
        echo "3. Examine /tmp/user-data-step-* files for individual step status"
        echo "4. Monitor system resources with 'htop' or 'top'"
        echo "5. Check Docker status with 'docker info' and 'docker ps'"
        
        return 1
    fi
    
    # =======================================================================
    # FINAL VALIDATION
    # =======================================================================
    log "🔍 Running final system validation checks..."
    
    local validation_result=$(ssh $ssh_options -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" '
        # Check GPU
        gpu_status="unknown"
        if command -v nvidia-smi &> /dev/null; then
            gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits 2>/dev/null || echo "0")
            gpu_driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "none")
            if [ "$gpu_count" -gt 0 ]; then
                gpu_status="detected:$gpu_count:$gpu_driver"
            else
                gpu_status="no_devices"
            fi
        else
            gpu_status="no_driver"
        fi
        echo "$gpu_status"
        
        # Check Docker
        if docker info >/dev/null 2>&1; then
            echo "running"
        else
            echo "not_running"
        fi
        
        # Check Docker Compose services (if any are running)
        if [ -f /home/ubuntu/ai-starter-kit/docker-compose.gpu-optimized.yml ]; then
            cd /home/ubuntu/ai-starter-kit
            running_services=$(docker compose -f docker-compose.gpu-optimized.yml ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
            echo "services:$running_services"
        else
            echo "services:0"
        fi
        
        # Check EFS mount
        if mountpoint -q /mnt/efs >/dev/null 2>&1; then
            echo "efs:mounted"
        else
            echo "efs:not_mounted"
        fi
    ' 2>/dev/null || echo -e "unknown\nunknown\nservices:0\nefs:unknown")
    
    # Parse validation results
    IFS=$'\n' read -d '' -r gpu_status docker_status services_status efs_status <<< "$validation_result" || true
    
    # Report validation results
    local validation_passed=true
    
    # GPU validation
    if [[ "$gpu_status" == detected:* ]]; then
        local gpu_count=$(echo "$gpu_status" | cut -d: -f2)
        local gpu_driver=$(echo "$gpu_status" | cut -d: -f3)
        success "✅ GPU validation: $gpu_count GPU(s) detected, driver v$gpu_driver"
    elif [[ "$gpu_status" == "no_devices" ]]; then
        warning "⚠️  GPU validation: Driver installed but no GPU devices detected"
        validation_passed=false
    elif [[ "$gpu_status" == "no_driver" ]]; then
        warning "⚠️  GPU validation: NVIDIA drivers not installed"
        validation_passed=false
    else
        warning "⚠️  GPU validation: Status unknown - manual verification recommended"
        validation_passed=false
    fi
    
    # Docker validation
    if [[ "$docker_status" == "running" ]]; then
        success "✅ Docker validation: Service is running"
    else
        warning "⚠️  Docker validation: Service not running - status: $docker_status"
        validation_passed=false
    fi
    
    # Services validation
    if [[ "$services_status" == services:* ]]; then
        local service_count=$(echo "$services_status" | cut -d: -f2)
        if [ "$service_count" -gt 0 ]; then
            success "✅ Container services: $service_count services running"
        else
            info "ℹ️  Container services: No services currently running (deployment may be needed)"
        fi
    fi
    
    # EFS validation
    if [[ "$efs_status" == "efs:mounted" ]]; then
        success "✅ EFS validation: Persistent storage mounted"
    else
        warning "⚠️  EFS validation: Persistent storage not mounted - status: $efs_status"
    fi
    
    # Close SSH control connection
    ssh $ssh_options -O exit "ubuntu@$PUBLIC_IP" 2>/dev/null || true
    
    if [ "$validation_passed" = true ]; then
        success "🎉 All validation checks passed! Instance is ready for deployment."
    else
        warning "⚠️  Some validation checks failed - manual verification recommended"
        info "💡 The instance is accessible, but some features may require troubleshooting"
    fi
    
    return 0
}

deploy_application() {
    local PUBLIC_IP="$1"
    local EFS_DNS="$2"
    local INSTANCE_ID="$3"
    
    log "Deploying GeuseMaker application..."
    
    # Create deployment script
    cat > deploy-app.sh << EOF
#!/bin/bash
set -euo pipefail

echo "Starting GeuseMaker deployment..."

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc $EFS_DNS:/ /mnt/efs
echo "$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | sudo tee -a /etc/fstab

# Clone repository if it doesn't exist
if [ ! -d "/home/ubuntu/GeuseMaker" ]; then
    git clone https://github.com/michael-pittman/001-starter-kit.git /home/ubuntu/GeuseMaker
fi
cd /home/ubuntu/GeuseMaker

# Update Docker images to latest versions (unless overridden)
if [ "\${USE_LATEST_IMAGES:-true}" = "true" ]; then
    echo "Updating Docker images to latest versions..."
    if [ -f "scripts/simple-update-images.sh" ]; then
        chmod +x scripts/simple-update-images.sh
        ./scripts/simple-update-images.sh update
    else
        echo "Warning: Image update script not found, using default versions"
    fi
fi

# Create comprehensive .env file with all required variables
cat > .env << EOFENV
# PostgreSQL Configuration
POSTGRES_DB=n8n_db
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=n8n_password_\$(openssl rand -hex 32)

# n8n Configuration
N8N_ENCRYPTION_KEY=\$(openssl rand -hex 32)
N8N_USER_MANAGEMENT_JWT_SECRET=\$(openssl rand -hex 32)
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5678

# n8n Security Settings
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=https://n8n.geuse.io,https://localhost:5678
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# AWS Configuration
EFS_DNS=$EFS_DNS
INSTANCE_ID=$INSTANCE_ID
AWS_DEFAULT_REGION=$AWS_REGION
INSTANCE_TYPE=g4dn.xlarge

# Image version control
USE_LATEST_IMAGES=$USE_LATEST_IMAGES

# API Keys (empty by default - can be configured via SSM)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=
EOFENV

# Start GPU-optimized services
export EFS_DNS=$EFS_DNS
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed!"
EOF

    # Copy the deployment script and run it
    log "Copying deployment script..."
    scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" deploy-app.sh "ubuntu@$PUBLIC_IP:/tmp/"
    
    # Copy the entire repository
    log "Copying application files..."
    rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '*.log' \
        -e "ssh -o StrictHostKeyChecking=no -i ${KEY_NAME}.pem" \
        ./ "ubuntu@$PUBLIC_IP:/home/ubuntu/GeuseMaker/"
    
    # Run deployment
    log "Running deployment script..."
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" \
        "chmod +x /tmp/deploy-app.sh && /tmp/deploy-app.sh"
    
    success "Application deployment completed!"
}

setup_monitoring() {
    local PUBLIC_IP="$1"
    
    log "Setting up monitoring and cost optimization..."
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${STACK_NAME}-high-gpu-utilization" \
        --alarm-description "Alert when GPU utilization is high" \
        --metric-name GPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 90 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --region "$AWS_REGION" || true
    
    success "Monitoring setup completed!"
}

validate_deployment() {
    local PUBLIC_IP="$1"
    
    log "Validating deployment with enhanced health monitoring..."
    
    # Wait for initial service startup
    log "Waiting 120 seconds for services to initialize..."
    sleep 120
    
    # Use enhanced health check instead of basic validation
    if enhanced_health_check "$PUBLIC_IP" 15; then
        success "All services are healthy and deployment is complete!"
        
        # Show comprehensive diagnostic information
        log "Running final service diagnostics..."
        comprehensive_service_diagnostics "$PUBLIC_IP"
        
        return 0
    else
        error "Deployment validation failed"
        warning "Running comprehensive diagnostics to identify issues..."
        comprehensive_service_diagnostics "$PUBLIC_IP"
        return 1
    fi
}

# =============================================================================
# POST-DEPLOYMENT COMPREHENSIVE VALIDATION
# =============================================================================

run_post_deployment_validation() {
    local PUBLIC_IP="$1"
    
    separator "═══════════════════════════════════════════════════════════════════"
    log "🚀 Running Comprehensive Post-Deployment Validation Suite"
    separator "═══════════════════════════════════════════════════════════════════"
    
    local validation_failed=false
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Export environment variables for validation scripts
    export KEY_NAME="${KEY_NAME}"
    export STACK_NAME="${STACK_NAME}"
    export AWS_REGION="${AWS_REGION}"
    
    # 1. Comprehensive Deployment Validation
    log "🔍 Step 1/4: Running comprehensive deployment validation..."
    if [[ -x "$script_dir/deployment-validator.sh" ]]; then
        if "$script_dir/deployment-validator.sh" "$PUBLIC_IP"; then
            success "✅ Deployment validation passed"
        else
            error "❌ Deployment validation failed"
            validation_failed=true
        fi
    else
        warning "⚠ Deployment validator script not found or not executable"
    fi
    
    echo ""
    
    # 2. Performance Benchmarking
    log "⚡ Step 2/4: Running performance benchmarks..."
    if [[ -x "$script_dir/performance-benchmark.sh" ]]; then
        if "$script_dir/performance-benchmark.sh" "$PUBLIC_IP"; then
            success "✅ Performance benchmarks completed"
        else
            warning "⚠ Performance benchmarks encountered issues (non-critical)"
        fi
    else
        warning "⚠ Performance benchmark script not found or not executable"
    fi
    
    echo ""
    
    # 3. Security Audit
    log "🔒 Step 3/4: Running security audit..."
    if [[ -x "$script_dir/security-audit.sh" ]]; then
        if "$script_dir/security-audit.sh" "$PUBLIC_IP"; then
            success "✅ Security audit passed"
        else
            error "❌ Security audit found critical issues"
            validation_failed=true
        fi
    else
        warning "⚠ Security audit script not found or not executable"
    fi
    
    echo ""
    
    # 4. Generate Comprehensive Report
    log "📊 Step 4/4: Generating comprehensive deployment report..."
    
    local report_file="deployment-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "AI STARTER KIT - DEPLOYMENT VALIDATION REPORT"
        echo "=============================================="
        echo "Generated: $(date)"
        echo "Instance IP: $PUBLIC_IP"
        echo "Region: $AWS_REGION"
        echo "Stack Name: $STACK_NAME"
        echo ""
        
        echo "VALIDATION SUMMARY:"
        echo "==================="
        
        if [[ "$validation_failed" == "false" ]]; then
            echo "✅ Overall Status: PASSED"
            echo "✅ All critical validations passed"
            echo "✅ Deployment is ready for production use"
        else
            echo "❌ Overall Status: FAILED"
            echo "❌ Some critical validations failed"
            echo "⚠️  Review the detailed logs above for specific issues"
        fi
        
        echo ""
        echo "NEXT STEPS:"
        echo "==========="
        echo "1. Access your services:"
        echo "   • n8n Workflow Automation: http://$PUBLIC_IP:5678"
        echo "   • Ollama LLM API: http://$PUBLIC_IP:11434"
        echo "   • Qdrant Vector Database: http://$PUBLIC_IP:6333"
        echo "   • Crawl4AI Web Scraper: http://$PUBLIC_IP:8000"
        echo ""
        echo "2. Security recommendations:"
        echo "   • Review security audit findings above"
        echo "   • Implement additional security hardening as needed"
        echo "   • Set up monitoring and alerting"
        echo ""
        echo "3. Performance optimization:"
        echo "   • Review performance benchmark results"
        echo "   • Monitor resource usage and scale as needed"
        echo "   • Optimize container configurations based on workload"
        echo ""
        echo "4. Maintenance:"
        echo "   • Regular security updates: sudo apt update && sudo apt upgrade"
        echo "   • Monitor costs and resource usage"
        echo "   • Backup important data and configurations"
        echo ""
        
        if [[ "$validation_failed" == "true" ]]; then
            echo "TROUBLESHOOTING:"
            echo "================"
            echo "If validation failed, you can:"
            echo "1. Re-run individual validation scripts:"
            echo "   ./scripts/deployment-validator.sh $PUBLIC_IP"
            echo "   ./scripts/security-audit.sh $PUBLIC_IP"
            echo ""
            echo "2. Check service logs:"
            echo "   ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
            echo "   cd ai-starter-kit"
            echo "   docker compose -f docker-compose.gpu-optimized.yml logs"
            echo ""
            echo "3. Get help:"
            echo "   • Review the troubleshooting section in CLAUDE.md"
            echo "   • Check AWS CloudWatch logs for detailed error information"
            echo "   • Ensure security groups allow required ports"
        fi
        
    } > "$report_file"
    
    success "📋 Comprehensive report generated: $report_file"
    
    # Display final status
    separator "═══════════════════════════════════════════════════════════════════"
    if [[ "$validation_failed" == "false" ]]; then
        success "🎉 POST-DEPLOYMENT VALIDATION COMPLETED SUCCESSFULLY!"
        success "🚀 Your AI Starter Kit is ready for production use!"
        info "📋 Detailed report saved to: $report_file"
    else
        error "❌ POST-DEPLOYMENT VALIDATION FAILED"
        warning "🔧 Please review the issues above and re-run validation scripts"
        warning "📋 Detailed report with troubleshooting steps: $report_file"
    fi
    separator "═══════════════════════════════════════════════════════════════════"
    
    return $([ "$validation_failed" == "false" ] && echo 0 || echo 1)
}

# =============================================================================
# APPLICATION LOAD BALANCER SETUP
# =============================================================================

setup_alb() {
    local INSTANCE_ID="$1"
    local SG_ID="$2"
    
    if [ "$SETUP_ALB" != "true" ]; then
        log "Skipping ALB setup (not requested)"
        return 0
    fi
    
    log "Setting up Application Load Balancer..."
    
    # Get VPC ID from the security group
    local VPC_ID
    VPC_ID=$(aws ec2 describe-security-groups \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].VpcId' \
        --output text)
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        error "Could not determine VPC ID from security group $SG_ID"
        return 1
    fi
    
    # Get at least 2 subnets for ALB (ALB requires multiple AZs)
    local subnet_ids
    mapfile -t subnet_ids < <(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' \
        --output text | tr '\t' '\n' | head -2)
    
    if [ ${#subnet_ids[@]} -lt 2 ]; then
        warn "Need at least 2 public subnets for ALB. Attempting to use default VPC subnets..."
        
        # Try to get subnets from default VPC
        mapfile -t subnet_ids < <(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
            --query 'Subnets[].SubnetId' \
            --output text | tr '\t' '\n' | head -2)
        
        if [ ${#subnet_ids[@]} -lt 2 ]; then
            warn "Still don't have enough subnets for ALB. Skipping ALB setup."
            return 0
        fi
    fi
    
    # Create ALB
    local ALB_ARN
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --subnets "${subnet_ids[@]}" \
        --security-groups "$SG_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null)
    
    if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
        warn "Failed to create Application Load Balancer. Continuing without ALB."
        return 0
    fi
    
    # Create target groups for main services
    local services=("n8n:5678" "ollama:11434" "qdrant:6333" "crawl4ai:11235")
    
    for service in "${services[@]}"; do
        local service_name="${service%:*}"
        local service_port="${service#*:}"
        
        log "Creating target group for $service_name..."
        
        # Create target group
        local TG_ARN
        TG_ARN=$(aws elbv2 create-target-group \
            --name "${STACK_NAME}-${service_name}-tg" \
            --protocol HTTP \
            --port "$service_port" \
            --vpc-id "$VPC_ID" \
            --health-check-protocol HTTP \
            --health-check-path "/" \
            --health-check-interval-seconds 30 \
            --health-check-timeout-seconds 5 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null)
        
        if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
            # Register instance with target group
            aws elbv2 register-targets \
                --target-group-arn "$TG_ARN" \
                --targets Id="$INSTANCE_ID",Port="$service_port" \
                2>/dev/null
            
            # Create listener (different ports for different services)
            local listener_port
            case "$service_name" in
                "n8n") listener_port=80 ;;
                "ollama") listener_port=8080 ;;
                "qdrant") listener_port=8081 ;;
                "crawl4ai") listener_port=8082 ;;
                *) listener_port=$((8000 + service_port % 1000)) ;;
            esac
            
            aws elbv2 create-listener \
                --load-balancer-arn "$ALB_ARN" \
                --protocol HTTP \
                --port "$listener_port" \
                --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
                2>/dev/null > /dev/null
            
            success "✓ Created target group and listener for $service_name on port $listener_port"
        fi
    done
    
    # Get ALB DNS name
    ALB_DNS_NAME=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    success "Application Load Balancer setup completed!"
    log "ALB DNS: $ALB_DNS_NAME"
    log "Service URLs:"
    log "  • n8n:      http://$ALB_DNS_NAME (port 80)"
    log "  • Ollama:   http://$ALB_DNS_NAME:8080"
    log "  • Qdrant:   http://$ALB_DNS_NAME:8081"
    log "  • Crawl4AI: http://$ALB_DNS_NAME:8082"
    
    return 0
}

# =============================================================================
# CLOUDFRONT SETUP
# =============================================================================

setup_cloudfront() {
    local ALB_DNS_NAME="$1"
    
    if [ "$SETUP_CLOUDFRONT" != "true" ]; then
        log "Skipping CloudFront setup (not requested)"
        return 0
    fi
    
    if [ -z "$ALB_DNS_NAME" ]; then
        warn "No ALB DNS name provided. CloudFront requires ALB. Skipping CloudFront setup."
        return 0
    fi
    
    log "Setting up CloudFront distribution..."
    
    # Create CloudFront distribution configuration
    local distribution_config
    distribution_config=$(cat << EOF
{
    "CallerReference": "${STACK_NAME}-$(date +%s)",
    "Comment": "GeuseMaker CDN Distribution for ${STACK_NAME}",
    "DefaultCacheBehavior": {
        "TargetOriginId": "${STACK_NAME}-alb-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {
                "Forward": "all"
            },
            "Headers": {
                "Quantity": 1,
                "Items": ["*"]
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 31536000
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "${STACK_NAME}-alb-origin",
                "DomainName": "$ALB_DNS_NAME",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    }
                }
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}
EOF
)
    
    # Create the distribution
    local distribution_result
    distribution_result=$(aws cloudfront create-distribution \
        --distribution-config "$distribution_config" \
        2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$distribution_result" ]; then
        local CLOUDFRONT_ID
        local CLOUDFRONT_DOMAIN
        
        CLOUDFRONT_ID=$(echo "$distribution_result" | jq -r '.Distribution.Id' 2>/dev/null || echo "")
        CLOUDFRONT_DOMAIN=$(echo "$distribution_result" | jq -r '.Distribution.DomainName' 2>/dev/null || echo "")
        
        if [ -n "$CLOUDFRONT_ID" ] && [ "$CLOUDFRONT_ID" != "null" ]; then
            success "CloudFront distribution created!"
            log "Distribution ID: $CLOUDFRONT_ID"
            log "Distribution Domain: $CLOUDFRONT_DOMAIN"
            log "CloudFront URL: https://$CLOUDFRONT_DOMAIN"
            
            log "Note: CloudFront distribution is being deployed. It may take 15-20 minutes to become fully available."
            
            # Store for later use
            echo "$CLOUDFRONT_ID" > "/tmp/${STACK_NAME}-cloudfront-id"
            echo "$CLOUDFRONT_DOMAIN" > "/tmp/${STACK_NAME}-cloudfront-domain"
        else
            warn "CloudFront distribution creation returned unexpected results. Continuing without CloudFront."
        fi
        
        return 0
    else
        warn "Failed to create CloudFront distribution. This is optional and deployment will continue."
        return 0
    fi
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ___    ____   _____ __             __              __ ____ __ 
   /   |  /  _/  / ___// /_____ ______/ /____  _____  / //_  //_/_
  / /| |  / /    \__ \/ __/ __ `/ ___/ __/ _ \/ ___/ / //_/ /_/ __/
 / ___ |_/ /    ___/ / /_/ /_/ / /  / /_/  __/ /    / / _  __/ /_  
/_/  |_/___/   /____/\__/\__,_/_/   \__/\___/_/    /_/ /_/ /\__/  
                                                                  
🤖 INTELLIGENT GPU DEPLOYMENT SYSTEM 🚀
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Multi-Architecture | Cost-Optimized | AI-Powered Selection${NC}"
    echo -e "${PURPLE}Automatic AMI & Instance Selection | Real-time Pricing Analysis${NC}"
    echo ""
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    
    log "Starting AWS infrastructure deployment..."
    
    # Mark that we're starting to create resources  
    RESOURCES_CREATED=true
    
    create_key_pair
    create_iam_role
    
    # Set up secure credentials first
    setup_secure_credentials
    
    # Use parallel infrastructure setup for better performance
    INFRA_RESULTS=$(setup_infrastructure_parallel)
    
    # Parse results from parallel setup
    SG_ID=$(echo "$INFRA_RESULTS" | cut -d: -f1)
    EFS_DNS=$(echo "$INFRA_RESULTS" | cut -d: -f2)
    
    # Extract EFS_ID from EFS_DNS for mount target creation
    EFS_ID=$(echo "$EFS_DNS" | cut -d. -f1)
    export EFS_ID
    
    # Validate EFS_ID was extracted properly
    if [[ -z "${EFS_ID:-}" ]]; then
        error "Failed to extract EFS_ID from EFS_DNS: $EFS_DNS"
        return 1
    fi
    
    # Launch single spot instance directly (no ASG to avoid multiple instances)
    log "Launching single spot instance with multi-AZ fallback..."
    INSTANCE_INFO=$(launch_spot_instance "$SG_ID" "$EFS_DNS" "$ENABLE_CROSS_REGION")
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | cut -d: -f1)
    PUBLIC_IP=$(echo "$INSTANCE_INFO" | cut -d: -f2)
    INSTANCE_AZ=$(echo "$INSTANCE_INFO" | cut -d: -f3)
    
    # Validate critical variables were extracted properly
    if [[ -z "${INSTANCE_ID:-}" ]]; then
        error "Failed to extract INSTANCE_ID from INSTANCE_INFO: $INSTANCE_INFO"
        return 1
    fi
    if [[ -z "${PUBLIC_IP:-}" ]]; then
        error "Failed to extract PUBLIC_IP from INSTANCE_INFO: $INSTANCE_INFO"
        return 1
    fi
    if [[ -z "${INSTANCE_AZ:-}" ]]; then
        error "Failed to extract INSTANCE_AZ from INSTANCE_INFO: $INSTANCE_INFO"
        return 1
    fi

    # Now create EFS mount target in the AZ where instance was actually launched
    create_efs_mount_target "$SG_ID" "$INSTANCE_AZ"

    TARGET_GROUP_ARN=$(create_target_group "$SG_ID" "$INSTANCE_ID")
    QDRANT_TG_ARN=$(create_qdrant_target_group "$SG_ID" "$INSTANCE_ID")
    ALB_DNS=$(create_alb "$SG_ID" "$TARGET_GROUP_ARN" "$QDRANT_TG_ARN")
    
    # Validate critical variables were set properly
    if [[ -z "${TARGET_GROUP_ARN:-}" ]]; then
        error "Failed to create target group"
        return 1
    fi
    if [[ -z "${QDRANT_TG_ARN:-}" ]]; then
        error "Failed to create qdrant target group"
        return 1
    fi
    if [[ -z "${ALB_DNS:-}" ]]; then
        error "Failed to create ALB"
        return 1
    fi
    
    setup_cloudfront "$ALB_DNS"
    
    wait_for_instance_ready "$PUBLIC_IP"
    deploy_application "$PUBLIC_IP" "$EFS_DNS" "$INSTANCE_ID"
    setup_monitoring "$PUBLIC_IP"
    validate_deployment "$PUBLIC_IP"
    
    # Run comprehensive post-deployment validation
    run_post_deployment_validation "$PUBLIC_IP"
    # Setup ALB and CloudFront if requested
    local ALB_DNS=""
    if [ "$SETUP_ALB" = "true" ]; then
        setup_alb "$INSTANCE_ID" "$SG_ID"
        if [ -n "$ALB_DNS_NAME" ]; then
            ALB_DNS="$ALB_DNS_NAME"
        fi
    fi
    
    if [ "$SETUP_CLOUDFRONT" = "true" ]; then
        setup_cloudfront "$ALB_DNS"
    fi
    
    display_results "$PUBLIC_IP" "$INSTANCE_ID" "$EFS_DNS" "$INSTANCE_AZ"
    
    # Clean up temporary files
    rm -f user-data.sh trust-policy.json custom-policy.json deploy-app.sh cloudfront-config.json
    
    success "GeuseMaker deployment completed successfully!"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "🚀 GeuseMaker - Intelligent AWS GPU Deployment"
    echo "================================================="
    echo ""
    echo "This script intelligently deploys GPU-optimized AI infrastructure on AWS"
    echo "Features:"
    echo "  🤖 Intelligent AMI and instance type selection"
    echo "  💰 Cost optimization with spot pricing analysis"
    echo "  🏗️  Multi-architecture support (Intel x86_64 & ARM64)"
    echo "  📊 Real-time pricing comparison across configurations"
    echo "  🎯 Automatic best price/performance selection"
    echo "  📈 Real-time setup progress monitoring"
    echo "  🔍 Advanced error detection and debugging"
    echo ""
    echo "Supported Configurations:"
    echo "  📦 G4DN instances (Intel + NVIDIA T4):"
    echo "      - g4dn.xlarge  (4 vCPUs, 16GB RAM, 1x T4)"
    echo "      - g4dn.2xlarge (8 vCPUs, 32GB RAM, 1x T4)"
    echo "  📦 G5G instances (ARM Graviton2 + NVIDIA T4G):"
    echo "      - g5g.xlarge   (4 vCPUs, 8GB RAM, 1x T4G)"  
    echo "      - g5g.2xlarge  (8 vCPUs, 16GB RAM, 1x T4G)"
    echo ""
    echo "AMI Sources:"
    echo "  🔧 AWS Deep Learning AMIs with pre-installed:"
    echo "      - NVIDIA drivers (optimized versions)"
    echo "      - Docker with GPU container runtime"
    echo "      - CUDA toolkit and libraries"
    echo "      - Python ML frameworks"
    echo ""
    echo "Requirements:"
    echo "  ✅ Valid AWS credentials configured"
    echo "  ✅ Docker and AWS CLI installed"
    echo "  ✅ jq and bc utilities (auto-installed if missing)"
    echo ""
    echo "Commands:"
    echo "  deploy                       Deploy the AI starter kit (default if no command given)"
    echo "  check-status IP [KEY]        Check setup status of running instance"
    echo "                              IP: Public IP address of the instance"
    echo "                              KEY: SSH key file path (optional, defaults to stack key)"
    echo "  diagnostics IP [KEY]         Run comprehensive service diagnostics"
    echo "                              IP: Public IP address of the instance"
    echo "                              KEY: SSH key file path (optional, defaults to stack key)"
    echo "  validate IP [KEY]            Run comprehensive deployment validation"
    echo "                              IP: Public IP address of the instance"
    echo "                              KEY: SSH key file path (optional, defaults to stack key)"
    echo "  benchmark IP [TYPE] [KEY]    Run performance benchmarks"
    echo "                              IP: Public IP address of the instance"
    echo "                              TYPE: all|gpu|container|network|system (default: all)"
    echo "                              KEY: SSH key file path (optional, defaults to stack key)"
    echo "  security-audit IP [TYPE] [KEY] Run security audit"
    echo "                              IP: Public IP address of the instance"
    echo "                              TYPE: all|network|iam|system|container|credential|compliance (default: all)"
    echo "                              KEY: SSH key file path (optional, defaults to stack key)"
    echo ""
    echo "Deploy Options:"
    echo "  --region REGION         AWS region (default: us-east-1)"
    echo "  --instance-type TYPE    Instance type or 'auto' for intelligent selection"
    echo "                         Valid: auto, g4dn.xlarge, g4dn.2xlarge, g5g.xlarge, g5g.2xlarge"
    echo "                         (default: auto)"
    echo "  --max-spot-price PRICE  Maximum spot price budget (default: 2.00)"
    echo "  --cross-region          Enable cross-region analysis for best pricing"
    echo "  --key-name NAME         SSH key name (default: GeuseMaker-key)"
    echo "  --stack-name NAME       Stack name (default: GeuseMaker)"
    echo "  --use-pinned-images     Use specific pinned image versions instead of latest"
    echo "  --setup-alb             Setup Application Load Balancer (ALB)"
    echo "  --setup-cloudfront      Setup CloudFront CDN distribution"
    echo "  --setup-cdn             Setup both ALB and CloudFront (convenience flag)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  🎯 Intelligent deployment (recommended):"
    echo "    $0                                    # Auto-select best config within budget"
    echo "    $0 deploy --max-spot-price 1.50      # Auto-select with \$1.50/hour budget"
    echo ""
    echo "  🎚️  Manual deployment:"
    echo "    $0 deploy --instance-type g4dn.xlarge    # Force specific instance type"
    echo "    $0 deploy --instance-type g5g.2xlarge    # Use ARM-based instance"
    echo ""
    echo "  🌍 Regional deployment:"
    echo "    $0 deploy --region us-west-2         # Deploy in different region"
    echo "    $0 deploy --region eu-central-1      # Deploy in Europe"
    echo "    $0 deploy --cross-region             # Find best region automatically"
    echo ""
    echo "  🔍 Status monitoring:"
    echo "    $0 check-status 52.1.2.3            # Check instance setup progress"
    echo "    $0 check-status 52.1.2.3 my-key.pem # Use custom SSH key"
    echo "    $0 diagnostics 52.1.2.3             # Run comprehensive diagnostics"
    echo ""
    echo "  🛡️ Validation and security:"
    echo "    $0 validate 52.1.2.3                # Comprehensive deployment validation"
    echo "    $0 benchmark 52.1.2.3 gpu           # Run GPU performance benchmarks"
    echo "    $0 security-audit 52.1.2.3          # Complete security audit"
    echo "    $0 security-audit 52.1.2.3 network  # Network security audit only"
    echo ""
    echo "New Monitoring Features:"
    echo "  📈 Real-time progress tracking during setup"
    echo "  🔍 Detailed error detection and reporting"
    echo "  ⏱️  Step-by-step setup monitoring"
    echo "  🚨 Automatic error diagnosis with suggestions"
    echo "  📊 Setup progress indicators (12 tracked stages)"
    echo "  🔧 Service health validation"
    echo "    $0 --region us-west-2                # Deploy in different region"
    echo "    $0 --region eu-central-1             # Deploy in Europe" 
    echo "    $0 --cross-region                    # Find best region automatically"
    echo ""
    echo "  🌐 Load balancer and CDN:"
    echo "    $0 --setup-alb                       # Deploy with Application Load Balancer"
    echo "    $0 --setup-cloudfront                # Deploy with CloudFront CDN"
    echo "    $0 --setup-cdn                       # Deploy with both ALB and CloudFront"
    echo "    $0 --setup-cdn --cross-region        # Full setup with best region"
    echo ""
    echo "Cost Optimization Features:"
    echo "  💡 Automatic spot pricing analysis across all AZs"
    echo "  💡 Price/performance ratio calculation"
    echo "  💡 Multi-AZ fallback for instance availability"
    echo "  💡 Real-time cost comparison display"
    echo "  💡 Optimal configuration recommendations"
    echo ""
    echo "Progress Monitoring:"
    echo "  The script now provides real-time feedback during instance setup:"
    echo "  📊 INIT → SYSTEM_UPDATE → GPU_VERIFY → DOCKER_VERIFY → DOCKER_COMPOSE"
    echo "  📊 NVIDIA_RUNTIME → GPU_TEST → TOOLS_INSTALL → CLOUDWATCH → SERVICES"
    echo "  📊 GPU_SCRIPT → FINAL_CHECK → SETUP_COMPLETE"
    echo ""
    echo "Debugging:"
    echo "  If deployment fails, the script provides:"
    echo "  🔍 Detailed error logs and location"
    echo "  📋 List of completed vs failed steps"
    echo "  💡 SSH commands for manual investigation"
    echo "  📊 Real-time status during 30-minute setup window"
    echo ""
    echo "Note: Script automatically handles AMI availability and finds the best"
    echo "      configuration based on current pricing and performance metrics."
}

# Parse command line arguments
COMMAND="deploy"  # Default command

# Check if first argument is a command
if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    case $1 in
        deploy)
            COMMAND="deploy"
            shift
            ;;
        check-status)
            COMMAND="check-status"
            shift
            if [[ $# -lt 1 ]]; then
                error "check-status command requires an IP address"
                echo "Usage: $0 check-status <IP_ADDRESS> [SSH_KEY_FILE]"
                exit 1
            fi
            STATUS_IP="$1"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                STATUS_KEY="$1"
                shift
            fi
            ;;
        diagnostics)
            COMMAND="diagnostics"
            shift
            if [[ $# -lt 1 ]]; then
                error "diagnostics command requires an IP address"
                echo "Usage: $0 diagnostics <IP_ADDRESS> [SSH_KEY_FILE]"
                exit 1
            fi
            DIAGNOSTICS_IP="$1"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                DIAGNOSTICS_KEY="$1"
                shift
            fi
            ;;
        validate)
            COMMAND="validate"
            shift
            if [[ $# -lt 1 ]]; then
                error "validate command requires an IP address"
                echo "Usage: $0 validate <IP_ADDRESS> [SSH_KEY_FILE]"
                exit 1
            fi
            VALIDATE_IP="$1"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                VALIDATE_KEY="$1"
                shift
            fi
            ;;
        benchmark)
            COMMAND="benchmark"
            shift
            if [[ $# -lt 1 ]]; then
                error "benchmark command requires an IP address"
                echo "Usage: $0 benchmark <IP_ADDRESS> [benchmark-type] [SSH_KEY_FILE]"
                exit 1
            fi
            BENCHMARK_IP="$1"
            shift
            BENCHMARK_TYPE="all"
            if [[ $# -gt 0 && "$1" != --* ]]; then
                BENCHMARK_TYPE="$1"
                shift
            fi
            if [[ $# -gt 0 && "$1" != --* ]]; then
                BENCHMARK_KEY="$1"
                shift
            fi
            ;;
        security-audit)
            COMMAND="security-audit"
            shift
            if [[ $# -lt 1 ]]; then
                error "security-audit command requires an IP address"
                echo "Usage: $0 security-audit <IP_ADDRESS> [audit-type] [SSH_KEY_FILE]"
                exit 1
            fi
            SECURITY_IP="$1"
            shift
            SECURITY_TYPE="all"
            if [[ $# -gt 0 && "$1" != --* ]]; then
                SECURITY_TYPE="$1"
                shift
            fi
            if [[ $# -gt 0 && "$1" != --* ]]; then
                SECURITY_KEY="$1"
                shift
            fi
            ;;
        --help|help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
fi

# Parse remaining arguments (options)
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --max-spot-price)
            MAX_SPOT_PRICE="$2"
            shift 2
            ;;
        --cross-region)
            ENABLE_CROSS_REGION="true"
            shift
            ;;
        --key-name)
            KEY_NAME="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --use-pinned-images)
            USE_LATEST_IMAGES=false
            shift
            ;;
        --setup-alb)
            SETUP_ALB=true
            shift
            ;;
        --setup-cloudfront)
            SETUP_CLOUDFRONT=true
            shift
            ;;
        --setup-cdn)
            # Convenience flag to enable both ALB and CloudFront
            SETUP_ALB=true
            SETUP_CLOUDFRONT=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Execute the appropriate command
case $COMMAND in
    deploy)
        # Run main deployment function
        main "$@"
        ;;
    check-status)
        # Run status check function
        check_instance_setup_status "$STATUS_IP" "${STATUS_KEY:-${KEY_NAME}.pem}"
        ;;
    diagnostics)
        # Run comprehensive diagnostics
        if [[ -z "$DIAGNOSTICS_KEY" ]]; then
            log "Using default SSH key: ${KEY_NAME}.pem"
            DIAGNOSTICS_KEY="${KEY_NAME}.pem"
        fi
        
        if [[ ! -f "$DIAGNOSTICS_KEY" ]]; then
            error "SSH key file not found: $DIAGNOSTICS_KEY"
            exit 1
        fi
        
        KEY_NAME=$(basename "$DIAGNOSTICS_KEY" .pem)
        comprehensive_service_diagnostics "$DIAGNOSTICS_IP"
        ;;
    validate)
        # Run comprehensive deployment validation
        if [[ -z "$VALIDATE_KEY" ]]; then
            log "Using default SSH key: ${KEY_NAME}.pem"
            VALIDATE_KEY="${KEY_NAME}.pem"
        fi
        
        if [[ ! -f "$VALIDATE_KEY" ]]; then
            error "SSH key file not found: $VALIDATE_KEY"
            exit 1
        fi
        
        KEY_NAME=$(basename "$VALIDATE_KEY" .pem)
        export KEY_NAME
        export STACK_NAME
        export AWS_REGION
        
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -x "$script_dir/deployment-validator.sh" ]]; then
            "$script_dir/deployment-validator.sh" "$VALIDATE_IP"
        else
            error "Deployment validator script not found or not executable: $script_dir/deployment-validator.sh"
            exit 1
        fi
        ;;
    benchmark)
        # Run performance benchmarks
        if [[ -z "$BENCHMARK_KEY" ]]; then
            log "Using default SSH key: ${KEY_NAME}.pem"
            BENCHMARK_KEY="${KEY_NAME}.pem"
        fi
        
        if [[ ! -f "$BENCHMARK_KEY" ]]; then
            error "SSH key file not found: $BENCHMARK_KEY"
            exit 1
        fi
        
        KEY_NAME=$(basename "$BENCHMARK_KEY" .pem)
        export KEY_NAME
        
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -x "$script_dir/performance-benchmark.sh" ]]; then
            "$script_dir/performance-benchmark.sh" "$BENCHMARK_IP" "$BENCHMARK_TYPE"
        else
            error "Performance benchmark script not found or not executable: $script_dir/performance-benchmark.sh"
            exit 1
        fi
        ;;
    security-audit)
        # Run security audit
        if [[ -z "$SECURITY_KEY" ]]; then
            log "Using default SSH key: ${KEY_NAME}.pem"
            SECURITY_KEY="${KEY_NAME}.pem"
        fi
        
        if [[ ! -f "$SECURITY_KEY" ]]; then
            error "SSH key file not found: $SECURITY_KEY"
            exit 1
        fi
        
        KEY_NAME=$(basename "$SECURITY_KEY" .pem)
        export KEY_NAME
        export STACK_NAME
        export AWS_REGION
        
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -x "$script_dir/security-audit.sh" ]]; then
            "$script_dir/security-audit.sh" "$SECURITY_IP" "$SECURITY_TYPE"
        else
            error "Security audit script not found or not executable: $script_dir/security-audit.sh"
            exit 1
        fi
        ;;
    *)
        error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac 