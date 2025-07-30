#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Input Validation Framework
# Provides comprehensive input validation and sanitization functions
# =============================================================================

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh" || {
    echo "ERROR: Failed to source logging module" >&2
    exit 1
}

# Validate AWS resource ID format
validate_aws_resource_id() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        vpc)
            [[ "$resource_id" =~ ^vpc-[a-f0-9]{8,17}$ ]]
            ;;
        subnet)
            [[ "$resource_id" =~ ^subnet-[a-f0-9]{8,17}$ ]]
            ;;
        sg|security-group)
            [[ "$resource_id" =~ ^sg-[a-f0-9]{8,17}$ ]]
            ;;
        instance|ec2)
            [[ "$resource_id" =~ ^i-[a-f0-9]{8,17}$ ]]
            ;;
        efs)
            [[ "$resource_id" =~ ^fs-[a-f0-9]{8,17}$ ]]
            ;;
        ami)
            [[ "$resource_id" =~ ^ami-[a-f0-9]{8,17}$ ]]
            ;;
        snap|snapshot)
            [[ "$resource_id" =~ ^snap-[a-f0-9]{8,17}$ ]]
            ;;
        vol|volume)
            [[ "$resource_id" =~ ^vol-[a-f0-9]{8,17}$ ]]
            ;;
        igw|internet-gateway)
            [[ "$resource_id" =~ ^igw-[a-f0-9]{8,17}$ ]]
            ;;
        rtb|route-table)
            [[ "$resource_id" =~ ^rtb-[a-f0-9]{8,17}$ ]]
            ;;
        acl|network-acl)
            [[ "$resource_id" =~ ^acl-[a-f0-9]{8,17}$ ]]
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Sanitize input for AWS tags
sanitize_aws_tag() {
    local input="$1"
    local max_length="${2:-255}"
    
    # Remove invalid characters, keep only alphanumeric, spaces, and limited special chars
    local sanitized
    sanitized=$(echo "$input" | sed 's/[^a-zA-Z0-9 _.\-:/]//g')
    
    # Truncate to max length
    echo "${sanitized:0:$max_length}"
}

# Validate and sanitize stack name
validate_stack_name() {
    local stack_name="$1"
    
    # Check if empty
    if [[ -z "$stack_name" ]]; then
        log_error "Stack name cannot be empty"
        return 1
    fi
    
    # Check length (CloudFormation limit is 128 chars)
    if [[ ${#stack_name} -gt 128 ]]; then
        log_error "Stack name too long (max 128 characters)"
        return 1
    fi
    
    # Check format (alphanumeric and hyphens only, must start with letter)
    if ! [[ "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        log_error "Invalid stack name format. Must start with letter and contain only alphanumeric and hyphens"
        return 1
    fi
    
    return 0
}

# Validate CIDR block
validate_cidr() {
    local cidr="$1"
    
    # Basic CIDR format validation
    if ! [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    
    # Validate IP octets
    local ip="${cidr%/*}"
    local mask="${cidr#*/}"
    
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done
    
    # Validate mask
    if [[ $mask -gt 32 || $mask -lt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Validate AWS region
validate_aws_region() {
    local region="$1"
    
    # List of valid AWS regions (as of 2024)
    local valid_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "af-south-1" "ap-east-1" "ap-south-1" "ap-south-2"
        "ap-northeast-1" "ap-northeast-2" "ap-northeast-3"
        "ap-southeast-1" "ap-southeast-2" "ap-southeast-3" "ap-southeast-4"
        "ca-central-1" "eu-central-1" "eu-central-2"
        "eu-west-1" "eu-west-2" "eu-west-3"
        "eu-north-1" "eu-south-1" "eu-south-2"
        "me-south-1" "me-central-1"
        "sa-east-1"
    )
    
    for valid_region in "${valid_regions[@]}"; do
        if [[ "$region" == "$valid_region" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Validate EC2 instance type
validate_instance_type() {
    local instance_type="$1"
    
    # Basic format validation
    if ! [[ "$instance_type" =~ ^[a-z][0-9][a-z]?\.[a-z0-9]+$ ]]; then
        return 1
    fi
    
    return 0
}

# Validate port number
validate_port() {
    local port="$1"
    
    # Check if numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check range (1-65535)
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        return 1
    fi
    
    return 0
}

# Validate email address
validate_email() {
    local email="$1"
    
    # Basic email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    
    return 1
}

# Validate URL
validate_url() {
    local url="$1"
    
    # Basic URL validation
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        return 0
    fi
    
    return 1
}

# Escape special characters for safe shell usage
escape_shell_arg() {
    local arg="$1"
    printf '%q' "$arg"
}

# Sanitize file path
sanitize_file_path() {
    local path="$1"
    
    # Remove dangerous characters and sequences
    local sanitized
    sanitized=$(echo "$path" | sed 's/[;&|`$<>]//g')
    
    # Remove directory traversal attempts
    sanitized=$(echo "$sanitized" | sed 's/\.\.//g')
    
    # Remove leading/trailing whitespace
    sanitized=$(echo "$sanitized" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "$sanitized"
}

# Validate integer
validate_integer() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    
    # Check if integer
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        return 1
    fi
    
    # Check min bound
    if [[ -n "$min" && $value -lt $min ]]; then
        return 1
    fi
    
    # Check max bound
    if [[ -n "$max" && $value -gt $max ]]; then
        return 1
    fi
    
    return 0
}

# Validate boolean
validate_boolean() {
    local value="$1"
    
    case "${value,,}" in
        true|false|yes|no|1|0|on|off)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Normalize boolean value
normalize_boolean() {
    local value="$1"
    
    case "${value,,}" in
        true|yes|1|on)
            echo "true"
            ;;
        false|no|0|off)
            echo "false"
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

# Validate environment name
validate_environment() {
    local env="$1"
    
    case "$env" in
        dev|development|test|testing|stage|staging|prod|production)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Export all validation functions
export -f validate_aws_resource_id
export -f sanitize_aws_tag
export -f validate_stack_name
export -f validate_cidr
export -f validate_aws_region
export -f validate_instance_type
export -f validate_port
export -f validate_email
export -f validate_url
export -f escape_shell_arg
export -f sanitize_file_path
export -f validate_integer
export -f validate_boolean
export -f normalize_boolean
export -f validate_environment