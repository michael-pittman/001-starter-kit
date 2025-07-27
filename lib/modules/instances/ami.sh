#!/bin/bash
# =============================================================================
# AMI Selection Module
# Centralized AMI selection and validation
# =============================================================================

# Prevent multiple sourcing
[ -n "${_AMI_SH_LOADED:-}" ] && return 0
_AMI_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# AMI PATTERNS
# =============================================================================

# Define AMI name patterns
declare -r NVIDIA_GPU_PATTERN="Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"
declare -r NVIDIA_FALLBACK_PATTERN="Deep Learning OSS Nvidia Driver AMI GPU *"
declare -r UBUNTU_PATTERN="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
declare -r UBUNTU_ARM_PATTERN="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"

# AMI owners
declare -r CANONICAL_OWNER="099720109477"  # Canonical
declare -r AMAZON_OWNER="amazon"           # Amazon

# =============================================================================
# AMI SELECTION
# =============================================================================

# Get AMI for instance type
get_ami_for_instance() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    case "$instance_type" in
        g4dn.*|g5.*|p3.*|p4d.*)
            # GPU instances - need NVIDIA drivers
            get_nvidia_gpu_ami "$region"
            ;;
        g5g.*)
            # ARM GPU instances
            get_nvidia_gpu_ami "$region" "arm64"
            ;;
        t3.*|m5.*|c5.*)
            # Standard x86 instances
            get_ubuntu_ami "$region"
            ;;
        t4g.*|m6g.*|c6g.*)
            # ARM instances
            get_ubuntu_ami "$region" "arm64"
            ;;
        *)
            throw_error $ERROR_INVALID_ARGUMENT "Unknown instance type: $instance_type"
            ;;
    esac
}

# Get NVIDIA GPU-optimized AMI
get_nvidia_gpu_ami() {
    local region="$1"
    local architecture="${2:-x86_64}"
    
    echo "Searching for NVIDIA GPU AMI in region: $region" >&2
    
    # Try primary pattern
    local ami_id
    ami_id=$(search_ami "$NVIDIA_GPU_PATTERN" "$AMAZON_OWNER" "$region" "$architecture")
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        echo "Primary GPU AMI not found, trying fallback pattern..." >&2
        ami_id=$(search_ami "$NVIDIA_FALLBACK_PATTERN" "$AMAZON_OWNER" "$region" "$architecture")
    fi
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        # Final fallback - use Ubuntu and install drivers
        echo "WARNING: No NVIDIA GPU AMI found, using Ubuntu base" >&2
        echo "NOTE: NVIDIA drivers will need to be installed manually" >&2
        ami_id=$(get_ubuntu_ami "$region" "$architecture")
    fi
    
    validate_ami "$ami_id" "$region"
    echo "$ami_id"
}

# Get Ubuntu AMI
get_ubuntu_ami() {
    local region="$1"
    local architecture="${2:-x86_64}"
    
    echo "Searching for Ubuntu 22.04 AMI in region: $region" >&2
    
    local pattern="$UBUNTU_PATTERN"
    [ "$architecture" = "arm64" ] && pattern="$UBUNTU_ARM_PATTERN"
    
    local ami_id
    ami_id=$(search_ami "$pattern" "$CANONICAL_OWNER" "$region" "$architecture")
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        throw_error $ERROR_RESOURCE_NOT_FOUND "No Ubuntu AMI found in region $region"
    fi
    
    validate_ami "$ami_id" "$region"
    echo "$ami_id"
}

# Search for AMI
search_ami() {
    local name_pattern="$1"
    local owner="$2"
    local region="$3"
    local architecture="${4:-x86_64}"
    
    aws ec2 describe-images \
        --region "$region" \
        --owners "$owner" \
        --filters \
            "Name=name,Values=$name_pattern" \
            "Name=state,Values=available" \
            "Name=architecture,Values=$architecture" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null
}

# Validate AMI exists and is available
validate_ami() {
    local ami_id="$1"
    local region="$2"
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        throw_error $ERROR_RESOURCE_NOT_FOUND "Invalid AMI ID: $ami_id"
    fi
    
    # Verify AMI exists
    local state
    state=$(aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].State' \
        --output text 2>/dev/null) || {
        throw_error $ERROR_AWS_API "Failed to describe AMI: $ami_id"
    }
    
    if [ "$state" != "available" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "AMI $ami_id is not available (state: $state)"
    fi
    
    echo "AMI validated: $ami_id (state: $state)" >&2
}

# =============================================================================
# AMI CACHING
# =============================================================================

# Cache file for AMI lookups
AMI_CACHE_FILE="${AMI_CACHE_FILE:-/tmp/ami-cache.json}"
AMI_CACHE_TTL="${AMI_CACHE_TTL:-3600}"  # 1 hour

# Initialize AMI cache
init_ami_cache() {
    if [ ! -f "$AMI_CACHE_FILE" ]; then
        echo '{}' > "$AMI_CACHE_FILE"
    fi
}

# Get cached AMI
get_cached_ami() {
    local cache_key="$1"
    
    init_ami_cache
    
    # Check if cache entry exists and is not expired
    local cache_entry
    cache_entry=$(jq -r --arg key "$cache_key" '.[$key] // empty' "$AMI_CACHE_FILE")
    
    if [ -n "$cache_entry" ]; then
        local cached_time=$(echo "$cache_entry" | jq -r '.timestamp')
        local cached_ami=$(echo "$cache_entry" | jq -r '.ami_id')
        local current_time=$(date +%s)
        
        if [ $((current_time - cached_time)) -lt "$AMI_CACHE_TTL" ]; then
            echo "Using cached AMI: $cached_ami" >&2
            echo "$cached_ami"
            return 0
        fi
    fi
    
    return 1
}

# Cache AMI lookup
cache_ami() {
    local cache_key="$1"
    local ami_id="$2"
    
    init_ami_cache
    
    local temp_file=$(mktemp)
    jq --arg key "$cache_key" \
       --arg ami "$ami_id" \
       --arg ts "$(date +%s)" \
       '.[$key] = {ami_id: $ami, timestamp: ($ts | tonumber)}' \
       "$AMI_CACHE_FILE" > "$temp_file" && \
    mv "$temp_file" "$AMI_CACHE_FILE"
}

# =============================================================================
# CROSS-REGION AMI SEARCH
# =============================================================================

# Find best AMI across regions
find_best_ami_across_regions() {
    local instance_type="$1"
    local preferred_regions=("${@:2}")
    
    # Default region list if none provided
    if [ ${#preferred_regions[@]} -eq 0 ]; then
        preferred_regions=(
            "us-east-1"
            "us-west-2"
            "eu-west-1"
            "ap-southeast-1"
        )
    fi
    
    echo "Searching for AMI across regions..." >&2
    
    for region in "${preferred_regions[@]}"; do
        echo "Checking region: $region" >&2
        
        local ami_id
        ami_id=$(get_ami_for_instance "$instance_type" "$region" 2>/dev/null) || continue
        
        if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
            echo "Found AMI in region $region: $ami_id" >&2
            cat <<EOF
{
    "region": "$region",
    "ami_id": "$ami_id"
}
EOF
            return 0
        fi
    done
    
    throw_error $ERROR_RESOURCE_NOT_FOUND "No suitable AMI found in any region"
}

# =============================================================================
# AMI INFORMATION
# =============================================================================

# Get AMI details
get_ami_details() {
    local ami_id="$1"
    local region="${2:-$AWS_REGION}"
    
    aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].{
            Name: Name,
            Description: Description,
            Architecture: Architecture,
            VirtualizationType: VirtualizationType,
            RootDeviceType: RootDeviceType,
            BlockDeviceMappings: BlockDeviceMappings,
            CreationDate: CreationDate,
            OwnerId: OwnerId,
            State: State
        }' \
        --output json
}

# Check if AMI has GPU support
ami_has_gpu_support() {
    local ami_id="$1"
    local region="${2:-$AWS_REGION}"
    
    local ami_name
    ami_name=$(aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].Name' \
        --output text 2>/dev/null)
    
    # Check if name contains GPU-related keywords
    if [[ "$ami_name" =~ (GPU|NVIDIA|CUDA|Deep Learning) ]]; then
        return 0
    else
        return 1
    fi
}