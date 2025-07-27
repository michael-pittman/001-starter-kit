#!/bin/bash
# EC2 Compute Provisioner with Enhanced Retry Logic
# Handles EC2 instance provisioning with fallback strategies

set -euo pipefail

# Prevent multiple sourcing
[ -n "${_PROVISIONER_SH_LOADED:-}" ] && return 0
_PROVISIONER_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$PROJECT_ROOT/lib/modules/core/variables.sh"
source "$PROJECT_ROOT/lib/modules/core/registry.sh"
source "$PROJECT_ROOT/lib/modules/errors/error_types.sh"

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Retry configuration
readonly DEFAULT_MAX_RETRIES=3
readonly DEFAULT_RETRY_DELAY=30
readonly DEFAULT_INSTANCE_TIMEOUT=300

# Instance type and region fallback chains (bash 3.x compatible)
# Use function-based lookups instead of associative arrays

get_instance_type_fallbacks() {
    local instance_type="$1"
    case "$instance_type" in
        "g4dn.xlarge") echo "g4dn.large g5.xlarge g4dn.2xlarge" ;;
        "g4dn.large") echo "g4dn.xlarge g5.large t3.large" ;;
        "g5.xlarge") echo "g4dn.xlarge g5.large g4dn.2xlarge" ;;
        "g5.large") echo "g4dn.large g5.xlarge t3.large" ;;
        "t3.large") echo "t3.xlarge m5.large t2.large" ;;
        "t3.xlarge") echo "t3.large m5.xlarge t2.xlarge" ;;
        *) echo "" ;;
    esac
}

get_region_fallbacks() {
    local region="$1"
    case "$region" in
        "us-east-1") echo "us-east-2 us-west-2 us-west-1" ;;
        "us-east-2") echo "us-east-1 us-west-2 us-west-1" ;;
        "us-west-1") echo "us-west-2 us-east-1 us-east-2" ;;
        "us-west-2") echo "us-west-1 us-east-2 us-east-1" ;;
        "eu-west-1") echo "eu-west-2 eu-central-1 us-east-1" ;;
        "eu-west-2") echo "eu-west-1 eu-central-1 us-east-1" ;;
        "eu-central-1") echo "eu-west-1 eu-west-2 us-east-1" ;;
        *) echo "" ;;
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_info() { echo -e "\033[0;32m[PROVISIONER INFO]\033[0m $*" >&2; }
log_warn() { echo -e "\033[1;33m[PROVISIONER WARN]\033[0m $*" >&2; }
log_error() { echo -e "\033[0;31m[PROVISIONER ERROR]\033[0m $*" >&2; }

# Calculate exponential backoff delay
calculate_backoff_delay() {
    local attempt="$1"
    local base_delay="${2:-$DEFAULT_RETRY_DELAY}"
    
    echo $((base_delay * (2 ** (attempt - 1))))
}

# Check if instance type is available in region
check_instance_type_availability() {
    local instance_type="$1"
    local region="${2:-$(get_variable 'AWS_REGION')}"
    
    log_info "Checking availability of $instance_type in $region"
    
    if aws ec2 describe-instance-type-offerings \
        --location-type availability-zone \
        --filters "Name=instance-type,Values=$instance_type" \
        --region "$region" \
        --query 'InstanceTypeOfferings[0].InstanceType' \
        --output text 2>/dev/null | grep -q "$instance_type"; then
        return 0
    else
        log_warn "Instance type $instance_type not available in $region"
        return 1
    fi
}

# Get available instance types in region
get_available_instance_types() {
    local region="${1:-$(get_variable 'AWS_REGION')}"
    local instance_family="${2:-g4dn}"
    
    aws ec2 describe-instance-type-offerings \
        --location-type availability-zone \
        --filters "Name=instance-type,Values=${instance_family}.*" \
        --region "$region" \
        --query 'InstanceTypeOfferings[].InstanceType' \
        --output text 2>/dev/null || echo ""
}

# =============================================================================
# PREFLGHT VALIDATION
# =============================================================================

validate_prerequisites() {
    local stack_name="$1"
    local instance_type="$2"
    local region="$3"
    
    log_info "Validating prerequisites for deployment"
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        error_config_missing_parameter "aws-cli"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_auth_invalid_credentials "aws-cli"
        return 1
    fi
    
    # Check required variables
    local required_vars=("STACK_NAME" "AWS_REGION" "INSTANCE_TYPE")
    for var in "${required_vars[@]}"; do
        if [[ -z "$(get_variable "$var")" ]]; then
            error_config_missing_parameter "$var"
            return 1
        fi
    done
    
    # Check instance type availability
    if ! check_instance_type_availability "$instance_type" "$region"; then
        error_ec2_insufficient_capacity "$instance_type" "$region"
        return 1
    fi
    
    log_info "Prerequisites validation passed"
    return 0
}

# Check service quotas
check_service_quotas() {
    local instance_type="$1"
    local region="${2:-$(get_variable 'AWS_REGION')}"
    
    log_info "Checking service quotas for $instance_type in $region"
    
    # Get current instance count
    local current_count
    current_count=$(aws ec2 describe-instances \
        --region "$region" \
        --filters "Name=instance-state-name,Values=running,pending" \
                  "Name=instance-type,Values=$instance_type" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null || echo "0")
    
    # Get service quota (simplified check)
    local quota_limit=20  # Default EC2 limit, should be queried from Service Quotas API
    
    if [[ "$current_count" -ge "$quota_limit" ]]; then
        error_ec2_instance_limit_exceeded "$instance_type"
        return 1
    fi
    
    log_info "Service quota check passed: $current_count/$quota_limit instances"
    return 0
}

# =============================================================================
# INSTANCE PROVISIONING
# =============================================================================

provision_instance() {
    local stack_name="$1"
    local instance_type="$2"
    local region="$3"
    local additional_params="${4:-}"
    
    log_info "Provisioning instance: $instance_type in $region"
    
    # Register resource in registry
    local resource_id="${stack_name}-instance-${instance_type}"
    register_resource "$resource_id" "ec2-instance" "" \
        "aws ec2 terminate-instances --instance-ids \$INSTANCE_ID --region $region"
    
    update_resource_status "$resource_id" "$STATUS_CREATING"
    
    # Build run-instances command
    local ami_id
    ami_id=$(get_optimal_ami "$region" "$instance_type")
    
    if [[ -z "$ami_id" ]]; then
        error_config_missing_parameter "ami-id"
        update_resource_status "$resource_id" "$STATUS_FAILED"
        return 1
    fi
    
    local subnet_id
    subnet_id=$(get_variable "SUBNET_ID")
    
    local security_group_id
    security_group_id=$(get_variable "SECURITY_GROUP_ID")
    
    local key_name
    key_name=$(get_variable "KEY_NAME")
    
    # Create user data
    local user_data_file="/tmp/user-data-${stack_name}.sh"
    generate_user_data "$stack_name" > "$user_data_file"
    
    # Build tags
    local tags
    tags=$(generate_tags "$stack_name" | tags_to_tag_spec "instance")
    
    # Launch instance
    local instance_result
    instance_result=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type "$instance_type" \
        --key-name "$key_name" \
        --security-group-ids "$security_group_id" \
        --subnet-id "$subnet_id" \
        --user-data "file://$user_data_file" \
        --tag-specifications "$tags" \
        --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2" \
        --monitoring "Enabled=true" \
        --region "$region" \
        $additional_params \
        --output json 2>&1) || {
        
        local exit_code=$?
        local instance_id="unknown"
        
        # Parse error message
        if echo "$instance_result" | grep -q "InsufficientInstanceCapacity"; then
            error_ec2_insufficient_capacity "$instance_type" "$region"
        elif echo "$instance_result" | grep -q "InstanceLimitExceeded"; then
            error_ec2_instance_limit_exceeded "$instance_type"
        elif echo "$instance_result" | grep -q "UnauthorizedOperation"; then
            error_auth_insufficient_permissions "ec2:RunInstances" "$instance_type"
        else
            log_error "Instance launch failed: $instance_result"
        fi
        
        update_resource_status "$resource_id" "$STATUS_FAILED"
        return $exit_code
    }
    
    # Extract instance ID
    local instance_id
    instance_id=$(echo "$instance_result" | jq -r '.Instances[0].InstanceId')
    
    if [[ -z "$instance_id" ]] || [[ "$instance_id" == "null" ]]; then
        log_error "Failed to extract instance ID from response"
        update_resource_status "$resource_id" "$STATUS_FAILED"
        return 1
    fi
    
    log_info "Instance launched: $instance_id"
    
    # Update resource registry with actual instance ID
    unregister_resource "ec2-instance" "$resource_id"
    register_resource "$instance_id" "ec2-instance" "" \
        "aws ec2 terminate-instances --instance-ids $instance_id --region $region"
    
    # Wait for instance to be running
    if wait_for_instance_running "$instance_id" "$region"; then
        update_resource_status "$instance_id" "$STATUS_CREATED"
        
        # Store instance details
        set_variable "INSTANCE_ID" "$instance_id"
        set_variable "INSTANCE_TYPE_USED" "$instance_type"
        set_variable "REGION_USED" "$region"
        
        log_info "Instance provisioning completed: $instance_id"
        return 0
    else
        update_resource_status "$instance_id" "$STATUS_FAILED"
        return 1
    fi
}

# Wait for instance to reach running state
wait_for_instance_running() {
    local instance_id="$1"
    local region="$2"
    local timeout="${3:-$DEFAULT_INSTANCE_TIMEOUT}"
    
    log_info "Waiting for instance $instance_id to be running (timeout: ${timeout}s)"
    
    local elapsed=0
    local interval=15
    
    while [[ $elapsed -lt $timeout ]]; do
        local state
        state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$region" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")
        
        case "$state" in
            "running")
                log_info "Instance $instance_id is running"
                return 0
                ;;
            "pending")
                log_info "Instance $instance_id is still pending..."
                ;;
            "terminated"|"terminating"|"stopped"|"stopping")
                log_error "Instance $instance_id unexpected state: $state"
                return 1
                ;;
            *)
                log_warn "Instance $instance_id unknown state: $state"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    error_timeout_operation "wait-for-instance-running" "$timeout"
    return 1
}

# =============================================================================
# FALLBACK STRATEGIES
# =============================================================================

provision_with_fallback() {
    local stack_name="$1"
    local preferred_instance_type="$2"
    local preferred_region="$3"
    local max_retries="${4:-$DEFAULT_MAX_RETRIES}"
    
    log_info "Starting provisioning with fallback strategy"
    
    # Try preferred configuration first
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        log_info "Attempt $attempt: $preferred_instance_type in $preferred_region"
        
        if provision_instance "$stack_name" "$preferred_instance_type" "$preferred_region"; then
            return 0
        fi
        
        if should_retry_error "EC2_INSUFFICIENT_CAPACITY" "$max_retries"; then
            local delay=$(calculate_backoff_delay "$attempt")
            log_info "Retrying in ${delay}s..."
            sleep "$delay"
        else
            break
        fi
        
        ((attempt++))
    done
    
    # Try instance type fallbacks in preferred region
    log_info "Trying instance type fallbacks in $preferred_region"
    local fallback_types="$(get_instance_type_fallbacks "$preferred_instance_type")"
    
    for fallback_type in $fallback_types; do
        if [[ -n "$fallback_type" ]]; then
            log_info "Trying fallback instance type: $fallback_type"
            
            if check_instance_type_availability "$fallback_type" "$preferred_region"; then
                if provision_instance "$stack_name" "$fallback_type" "$preferred_region"; then
                    return 0
                fi
            fi
        fi
    done
    
    # Try region fallbacks with original instance type
    log_info "Trying region fallbacks with $preferred_instance_type"
    local fallback_regions="$(get_region_fallbacks "$preferred_region")"
    
    for fallback_region in $fallback_regions; do
        if [[ -n "$fallback_region" ]]; then
            log_info "Trying fallback region: $fallback_region"
            
            if check_instance_type_availability "$preferred_instance_type" "$fallback_region"; then
                if provision_instance "$stack_name" "$preferred_instance_type" "$fallback_region"; then
                    return 0
                fi
            fi
        fi
    done
    
    log_error "All provisioning attempts failed"
    return 1
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_optimal_ami() {
    local region="$1"
    local instance_type="$2"
    
    # Get architecture for instance type
    local architecture
    architecture=$(aws ec2 describe-instance-types \
        --instance-types "$instance_type" \
        --region "$region" \
        --query 'InstanceTypes[0].ProcessorInfo.SupportedArchitectures[0]' \
        --output text 2>/dev/null || echo "x86_64")
    
    # Find Ubuntu 22.04 LTS AMI
    aws ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-*-server-*" \
                  "Name=architecture,Values=$architecture" \
                  "Name=state,Values=available" \
        --region "$region" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null || echo ""
}

generate_user_data() {
    local stack_name="$1"
    
    cat <<'EOF'
#!/bin/bash
set -euo pipefail

# Update system
apt-get update
apt-get install -y docker.io docker-compose-v2 awscli jq

# Start Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install NVIDIA drivers if GPU instance
if lspci | grep -i nvidia >/dev/null 2>&1; then
    apt-get install -y ubuntu-drivers-common
    ubuntu-drivers autoinstall
    
    # Install NVIDIA Docker runtime
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L "https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list" | tee /etc/apt/sources.list.d/nvidia-docker.list
    apt-get update
    apt-get install -y nvidia-docker2
    systemctl restart docker
fi

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack placeholder --resource AutoScalingGroup --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region)
EOF
}

# =============================================================================
# MAIN PROVISIONING FUNCTION
# =============================================================================

provision_compute_resources() {
    local stack_name="${1:-$(get_variable 'STACK_NAME')}"
    local instance_type="${2:-$(get_variable 'INSTANCE_TYPE' 'g4dn.xlarge')}"
    local region="${3:-$(get_variable 'AWS_REGION')}"
    
    log_info "Starting compute resource provisioning"
    log_info "Stack: $stack_name, Instance: $instance_type, Region: $region"
    
    # Validate prerequisites
    if ! validate_prerequisites "$stack_name" "$instance_type" "$region"; then
        return 1
    fi
    
    # Check service quotas
    if ! check_service_quotas "$instance_type" "$region"; then
        return 1
    fi
    
    # Provision with fallback
    if provision_with_fallback "$stack_name" "$instance_type" "$region"; then
        log_info "Compute resource provisioning completed successfully"
        return 0
    else
        log_error "Compute resource provisioning failed"
        return 1
    fi
}