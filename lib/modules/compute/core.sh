#!/usr/bin/env bash
# =============================================================================
# Compute Core Module
# Base functionality for EC2 compute resource management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_CORE_SH_LOADED:-}" ] && return 0
_COMPUTE_CORE_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# COMPUTE CONFIGURATION DEFAULTS
# =============================================================================

# Instance configuration defaults
readonly COMPUTE_DEFAULT_INSTANCE_TYPE="t3.micro"
readonly COMPUTE_DEFAULT_SPOT_INSTANCE_TYPE="t3.micro"
readonly COMPUTE_DEFAULT_ONDEMAND_INSTANCE_TYPE="t3.small"
readonly COMPUTE_DEFAULT_GPU_INSTANCE_TYPE="g4dn.xlarge"

# Volume configuration defaults
readonly COMPUTE_DEFAULT_VOLUME_SIZE=100
readonly COMPUTE_DEFAULT_VOLUME_TYPE="gp3"
readonly COMPUTE_DEFAULT_DELETE_ON_TERMINATION=true
readonly COMPUTE_DEFAULT_ENCRYPTED=true

# Instance metadata options
readonly COMPUTE_DEFAULT_HTTP_TOKENS="required"
readonly COMPUTE_DEFAULT_HTTP_PUT_RESPONSE_HOP_LIMIT=2

# Timeout and retry configuration
readonly COMPUTE_DEFAULT_INSTANCE_TIMEOUT=300
readonly COMPUTE_DEFAULT_MAX_RETRIES=3
readonly COMPUTE_DEFAULT_RETRY_DELAY=30

# =============================================================================
# COMPUTE HELPER FUNCTIONS
# =============================================================================

# Generate resource name with timestamp
generate_compute_resource_name() {
    local resource_type="$1"
    local stack_name="$2"
    local suffix="${3:-}"
    local timestamp=$(date +%Y%m%d%H%M%S)
    
    if [ -n "$suffix" ]; then
        echo "${stack_name}-${resource_type}-${suffix}-${timestamp}"
    else
        echo "${stack_name}-${resource_type}-${timestamp}"
    fi
}

# Validate resource name
validate_compute_resource_name() {
    local name="$1"
    local resource_type="$2"
    
    # Check length (AWS max is usually 255 chars, but some resources have less)
    local max_length=63  # Conservative default
    case "$resource_type" in
        instance|launch-template|asg) max_length=255 ;;
        security-group) max_length=255 ;;
        *) max_length=63 ;;
    esac
    
    if [ ${#name} -gt $max_length ]; then
        log_error "Resource name too long: ${#name} chars (max: $max_length)" "COMPUTE"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, some allow underscores)
    if ! [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid resource name format: $name" "COMPUTE"
        return 1
    fi
    
    return 0
}

# Get instance architecture
get_instance_architecture() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    # ARM instance types
    if [[ "$instance_type" =~ ^(t4g|m6g|c6g|g5g|r6g|x2g|i4g|im4g|is4g|c7g|m7g|r7g)\. ]]; then
        echo "arm64"
        return 0
    fi
    
    # Default to x86_64
    echo "x86_64"
}

# Check if instance type is GPU-enabled
is_gpu_instance() {
    local instance_type="$1"
    
    if [[ "$instance_type" =~ ^(g4dn|g5|g5g|p3|p4d|p4de|p5|gr6)\. ]]; then
        return 0
    else
        return 1
    fi
}

# Get instance family
get_instance_family() {
    local instance_type="$1"
    echo "$instance_type" | cut -d'.' -f1
}

# Get instance size
get_instance_size() {
    local instance_type="$1"
    echo "$instance_type" | cut -d'.' -f2
}

# =============================================================================
# INSTANCE TYPE VALIDATION
# =============================================================================

# Check if instance type is available in region
check_instance_type_availability() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    log_info "Checking availability of $instance_type in $region" "COMPUTE"
    
    local available
    available=$(aws ec2 describe-instance-type-offerings \
        --location-type availability-zone \
        --filters "Name=instance-type,Values=$instance_type" \
        --region "$region" \
        --query 'InstanceTypeOfferings[0].InstanceType' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$available" = "$instance_type" ]; then
        return 0
    else
        log_warn "Instance type $instance_type not available in $region" "COMPUTE"
        return 1
    fi
}

# Get available instance types in region
get_available_instance_types() {
    local region="${1:-$AWS_REGION}"
    local instance_family="${2:-}"
    
    local filter=""
    if [ -n "$instance_family" ]; then
        filter="Name=instance-type,Values=${instance_family}.*"
    fi
    
    if [ -n "$filter" ]; then
        aws ec2 describe-instance-type-offerings \
            --location-type availability-zone \
            --filters "$filter" \
            --region "$region" \
            --query 'InstanceTypeOfferings[].InstanceType' \
            --output text 2>/dev/null || echo ""
    else
        aws ec2 describe-instance-type-offerings \
            --location-type availability-zone \
            --region "$region" \
            --query 'InstanceTypeOfferings[].InstanceType' \
            --output text 2>/dev/null || echo ""
    fi
}

# =============================================================================
# INSTANCE TYPE RECOMMENDATIONS
# =============================================================================

# Get instance type fallback chain
get_instance_type_fallbacks() {
    local instance_type="$1"
    
    case "$instance_type" in
        # GPU instances
        "g4dn.xlarge") echo "g4dn.large g5.xlarge g4dn.2xlarge" ;;
        "g4dn.large") echo "g4dn.xlarge g5.large t3.large" ;;
        "g5.xlarge") echo "g4dn.xlarge g5.large g4dn.2xlarge" ;;
        "g5.large") echo "g4dn.large g5.xlarge t3.large" ;;
        
        # General purpose
        "t3.micro") echo "t3.small t2.micro t3a.micro" ;;
        "t3.small") echo "t3.micro t3.medium t3a.small" ;;
        "t3.medium") echo "t3.small t3.large t3a.medium" ;;
        "t3.large") echo "t3.xlarge m5.large t2.large" ;;
        "t3.xlarge") echo "t3.large m5.xlarge t2.xlarge" ;;
        
        # Compute optimized
        "c5.large") echo "c5.xlarge c5a.large m5.large" ;;
        "c5.xlarge") echo "c5.large c5.2xlarge c5a.xlarge" ;;
        
        # Memory optimized
        "r5.large") echo "r5.xlarge r5a.large m5.large" ;;
        "r5.xlarge") echo "r5.large r5.2xlarge r5a.xlarge" ;;
        
        # ARM instances
        "t4g.micro") echo "t4g.small t4g.medium" ;;
        "t4g.small") echo "t4g.micro t4g.medium" ;;
        "t4g.medium") echo "t4g.small t4g.large" ;;
        
        *) echo "" ;;
    esac
}

# Recommend instance type based on requirements
recommend_instance_type() {
    local vcpus="${1:-2}"
    local memory_gb="${2:-4}"
    local gpu_required="${3:-false}"
    local region="${4:-$AWS_REGION}"
    
    log_info "Recommending instance type: vCPUs=$vcpus, Memory=${memory_gb}GB, GPU=$gpu_required" "COMPUTE"
    
    # GPU instances
    if [ "$gpu_required" = "true" ]; then
        if [ "$vcpus" -le 4 ] && [ "$memory_gb" -le 16 ]; then
            echo "g4dn.xlarge"
        elif [ "$vcpus" -le 8 ] && [ "$memory_gb" -le 32 ]; then
            echo "g4dn.2xlarge"
        else
            echo "g4dn.4xlarge"
        fi
        return 0
    fi
    
    # General purpose
    if [ "$vcpus" -le 2 ] && [ "$memory_gb" -le 1 ]; then
        echo "t3.micro"
    elif [ "$vcpus" -le 2 ] && [ "$memory_gb" -le 2 ]; then
        echo "t3.small"
    elif [ "$vcpus" -le 2 ] && [ "$memory_gb" -le 4 ]; then
        echo "t3.medium"
    elif [ "$vcpus" -le 2 ] && [ "$memory_gb" -le 8 ]; then
        echo "t3.large"
    elif [ "$vcpus" -le 4 ] && [ "$memory_gb" -le 16 ]; then
        echo "t3.xlarge"
    elif [ "$vcpus" -le 8 ] && [ "$memory_gb" -le 32 ]; then
        echo "m5.2xlarge"
    else
        echo "m5.4xlarge"
    fi
}

# =============================================================================
# TAGS AND METADATA
# =============================================================================

# Generate standard tags for compute resources
generate_compute_tags() {
    local stack_name="$1"
    local resource_type="${2:-instance}"
    local additional_tags="${3:-}"
    
    local tags=$(cat <<EOF
[
    {"Key": "Name", "Value": "${stack_name}-${resource_type}"},
    {"Key": "Stack", "Value": "$stack_name"},
    {"Key": "Environment", "Value": "${ENVIRONMENT:-dev}"},
    {"Key": "ManagedBy", "Value": "GeuseMaker"},
    {"Key": "CreatedAt", "Value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
)
    
    # Add additional tags if provided
    if [ -n "$additional_tags" ]; then
        tags=$(echo "$tags" | sed 's/]$/,/')
        tags="${tags}${additional_tags}]"
    else
        tags="${tags}]"
    fi
    
    echo "$tags"
}

# Convert tags to tag specification format
tags_to_tag_spec() {
    local tags_json="$1"
    local resource_type="$2"
    
    cat <<EOF
{
    "ResourceType": "$resource_type",
    "Tags": $tags_json
}
EOF
}

# =============================================================================
# BLOCK DEVICE CONFIGURATION
# =============================================================================

# Generate block device mapping
generate_block_device_mapping() {
    local volume_size="${1:-$COMPUTE_DEFAULT_VOLUME_SIZE}"
    local volume_type="${2:-$COMPUTE_DEFAULT_VOLUME_TYPE}"
    local encrypted="${3:-$COMPUTE_DEFAULT_ENCRYPTED}"
    local delete_on_termination="${4:-$COMPUTE_DEFAULT_DELETE_ON_TERMINATION}"
    
    cat <<EOF
[
    {
        "DeviceName": "/dev/sda1",
        "Ebs": {
            "VolumeSize": $volume_size,
            "VolumeType": "$volume_type",
            "DeleteOnTermination": $delete_on_termination,
            "Encrypted": $encrypted
        }
    }
]
EOF
}

# =============================================================================
# METADATA OPTIONS
# =============================================================================

# Generate instance metadata options
generate_metadata_options() {
    local http_tokens="${1:-$COMPUTE_DEFAULT_HTTP_TOKENS}"
    local http_endpoint="${2:-enabled}"
    local http_put_response_hop_limit="${3:-$COMPUTE_DEFAULT_HTTP_PUT_RESPONSE_HOP_LIMIT}"
    
    cat <<EOF
{
    "HttpEndpoint": "$http_endpoint",
    "HttpTokens": "$http_tokens",
    "HttpPutResponseHopLimit": $http_put_response_hop_limit
}
EOF
}

# =============================================================================
# SERVICE QUOTA CHECKING
# =============================================================================

# Check service quotas for instance type
check_service_quotas() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    log_info "Checking service quotas for $instance_type in $region" "COMPUTE"
    
    # Get current instance count
    local current_count
    current_count=$(aws ec2 describe-instances \
        --region "$region" \
        --filters "Name=instance-state-name,Values=running,pending" \
                  "Name=instance-type,Values=$instance_type" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null || echo "0")
    
    # Get service quota using AWS Service Quotas API
    local quota_limit=20  # Default fallback EC2 limit
    
    # Try to get actual quota from Service Quotas API
    if command -v aws >/dev/null 2>&1; then
        local quota_value
        quota_value=$(aws service-quotas get-service-quota \
            --service-code ec2 \
            --quota-code L-1216C47A \
            --region "$region" \
            --query 'Quota.Value' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$quota_value" ]] && [[ "$quota_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            quota_limit="${quota_value%.*}"  # Convert to integer
            log_debug "Retrieved EC2 instance quota: $quota_limit" "COMPUTE"
        else
            log_debug "Using default EC2 instance quota: $quota_limit" "COMPUTE"
        fi
    fi
    
    if [[ "$current_count" -ge "$quota_limit" ]]; then
        log_error "Service quota exceeded: $current_count/$quota_limit instances" "COMPUTE"
        return 1
    fi
    
    log_info "Service quota check passed: $current_count/$quota_limit instances" "COMPUTE"
    return 0
}

# =============================================================================
# ERROR HANDLING HELPERS
# =============================================================================

# Calculate exponential backoff delay
calculate_backoff_delay() {
    local attempt="$1"
    local base_delay="${2:-$COMPUTE_DEFAULT_RETRY_DELAY}"
    
    echo $((base_delay * (2 ** (attempt - 1))))
}

# Parse AWS error response
parse_aws_error() {
    local error_output="$1"
    local error_code=""
    local error_message=""
    
    # Try to extract error code
    if echo "$error_output" | grep -q "InsufficientInstanceCapacity"; then
        error_code="InsufficientInstanceCapacity"
    elif echo "$error_output" | grep -q "InstanceLimitExceeded"; then
        error_code="InstanceLimitExceeded"
    elif echo "$error_output" | grep -q "UnauthorizedOperation"; then
        error_code="UnauthorizedOperation"
    elif echo "$error_output" | grep -q "SpotMaxPriceTooLow"; then
        error_code="SpotMaxPriceTooLow"
    elif echo "$error_output" | grep -q "InvalidAMIID"; then
        error_code="InvalidAMIID"
    else
        error_code="Unknown"
    fi
    
    # Extract error message
    error_message=$(echo "$error_output" | grep -o "message.*" | cut -d'"' -f3 || echo "$error_output")
    
    echo "$error_code:$error_message"
}

# =============================================================================
# COMPUTE MODULE INITIALIZATION
# =============================================================================

# Initialize compute module
init_compute_module() {
    log_info "Initializing compute core module" "COMPUTE"
    
    # Validate AWS CLI availability
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI not found. Please install AWS CLI." "COMPUTE"
        return 1
    fi
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid" "COMPUTE"
        return 1
    fi
    
    # Set default region if not set
    if [ -z "${AWS_REGION:-}" ]; then
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_REGION
    fi
    
    log_info "Compute module initialized. Region: $AWS_REGION" "COMPUTE"
    return 0
}

# Auto-initialize on source
init_compute_module || true