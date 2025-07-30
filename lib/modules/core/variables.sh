#!/usr/bin/env bash
# =============================================================================
# Core Variables Module
# Uniform variable management and naming conventions
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CORE_VARIABLES_SH_LOADED:-}" ] && return 0
_CORE_VARIABLES_SH_LOADED=1

# =============================================================================
# VARIABLE STORE CONFIGURATION
# =============================================================================

# Variable store paths
VARIABLE_STORE_DIR="${CONFIG_DIR:-./config}/variables"
VARIABLE_STORE_FILE="${VARIABLE_STORE_DIR}/deployment-variables.json"
VARIABLE_STORE_BACKUP="${VARIABLE_STORE_DIR}/deployment-variables.backup.json"

# Variable scopes
VARIABLE_SCOPE_GLOBAL="global"
VARIABLE_SCOPE_STACK="stack"
VARIABLE_SCOPE_ENVIRONMENT="environment"
VARIABLE_SCOPE_TEMPORARY="temporary"

# Variable types
VARIABLE_TYPE_STRING="string"
VARIABLE_TYPE_NUMBER="number"
VARIABLE_TYPE_BOOLEAN="boolean"
VARIABLE_TYPE_ARRAY="array"
VARIABLE_TYPE_OBJECT="object"

# =============================================================================
# NAMING CONVENTIONS
# =============================================================================

# Resource naming patterns
RESOURCE_NAME_PATTERN="^[a-zA-Z][a-zA-Z0-9-]{2,30}$"
STACK_NAME_PATTERN="^[a-zA-Z][a-zA-Z0-9-]{2,30}$"
TAG_NAME_PATTERN="^[a-zA-Z][a-zA-Z0-9-]{0,127}$"

# AWS resource naming conventions (templates - will be populated with actual stack name)
AWS_VPC_NAME_PATTERN="{stack_name}-vpc"
AWS_SUBNET_NAME_PATTERN="{stack_name}-subnet-{type}-{az}"
AWS_SECURITY_GROUP_NAME_PATTERN="{stack_name}-sg-{type}"
AWS_LAUNCH_TEMPLATE_NAME_PATTERN="{stack_name}-lt"
AWS_ASG_NAME_PATTERN="{stack_name}-asg"
AWS_ALB_NAME_PATTERN="{stack_name}-alb"
AWS_TARGET_GROUP_NAME_PATTERN="{stack_name}-tg-{port}"
AWS_CLOUDFRONT_NAME_PATTERN="{stack_name}-cf"
AWS_EFS_NAME_PATTERN="{stack_name}-efs"

# =============================================================================
# DEFAULT VALUES
# =============================================================================

# AWS Configuration
DEFAULT_AWS_REGION="us-east-1"
DEFAULT_AWS_PROFILE="default"
DEFAULT_AWS_AVAILABILITY_ZONES=("us-east-1a" "us-east-1b" "us-east-1c")

# Network Configuration
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_PUBLIC_SUBNET_CIDRS=("10.0.1.0/24" "10.0.2.0/24" "10.0.3.0/24")
DEFAULT_PRIVATE_SUBNET_CIDRS=("10.0.11.0/24" "10.0.12.0/24" "10.0.13.0/24")
DEFAULT_ISOLATED_SUBNET_CIDRS=("10.0.21.0/24" "10.0.22.0/24" "10.0.23.0/24")

# Instance Configuration
DEFAULT_INSTANCE_TYPE="t3.micro"
DEFAULT_SPOT_INSTANCE_TYPE="t3.micro"
DEFAULT_ONDEMAND_INSTANCE_TYPE="t3.small"
DEFAULT_GPU_INSTANCE_TYPE="g4dn.xlarge"

# Auto Scaling Configuration
DEFAULT_MIN_CAPACITY=1
DEFAULT_MAX_CAPACITY=3
DEFAULT_DESIRED_CAPACITY=1
DEFAULT_HEALTH_CHECK_GRACE_PERIOD=300
DEFAULT_HEALTH_CHECK_TYPE="EC2"

# Load Balancer Configuration
DEFAULT_ALB_PORT=80
DEFAULT_ALB_PROTOCOL="HTTP"
DEFAULT_ALB_HEALTH_CHECK_PATH="/health"
DEFAULT_ALB_HEALTH_CHECK_INTERVAL=30
DEFAULT_ALB_HEALTH_CHECK_TIMEOUT=5
DEFAULT_ALB_HEALTH_CHECK_THRESHOLD=2
DEFAULT_ALB_HEALTH_CHECK_UNHEALTHY_THRESHOLD=2

# EFS Configuration
DEFAULT_EFS_PERFORMANCE_MODE="generalPurpose"
DEFAULT_EFS_THROUGHPUT_MODE="bursting"
DEFAULT_EFS_ENCRYPTED=true
DEFAULT_EFS_LIFECYCLE_POLICY="AFTER_30_DAYS"

# CloudFront Configuration
DEFAULT_CLOUDFRONT_PRICE_CLASS="PriceClass_100"
DEFAULT_CLOUDFRONT_DEFAULT_TTL=86400
DEFAULT_CLOUDFRONT_MIN_TTL=0
DEFAULT_CLOUDFRONT_MAX_TTL=31536000

# Monitoring Configuration
DEFAULT_CLOUDWATCH_METRIC_INTERVAL=60
DEFAULT_CLOUDWATCH_ALARM_EVALUATION_PERIODS=2
DEFAULT_CLOUDWATCH_ALARM_PERIOD=300

# =============================================================================
# VARIABLE STORE FUNCTIONS
# =============================================================================

# Initialize variable store
init_variable_store() {
    local stack_name="${1:-}"
    local environment="${2:-development}"
    
    # Create variable store directory
    mkdir -p "${VARIABLE_STORE_DIR}"
    
    # Initialize variable store file if it doesn't exist
    if [[ ! -f "${VARIABLE_STORE_FILE}" ]]; then
        cat > "${VARIABLE_STORE_FILE}" << EOF
{
    "metadata": {
        "version": "1.0.0",
        "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "last_modified": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    },
    "global": {},
    "stacks": {},
    "environments": {},
    "temporary": {}
}
EOF
    fi
    
    # Set default variables for stack
    if [[ -n "$stack_name" ]]; then
        set_variable "STACK_NAME" "$stack_name" "$VARIABLE_SCOPE_STACK"
        set_variable "ENVIRONMENT" "$environment" "$VARIABLE_SCOPE_STACK"
        set_variable "AWS_REGION" "${AWS_REGION:-$DEFAULT_AWS_REGION}" "$VARIABLE_SCOPE_STACK"
        set_variable "AWS_PROFILE" "${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}" "$VARIABLE_SCOPE_STACK"
    fi
}

# Set variable in store
set_variable() {
    local name="$1"
    local value="$2"
    local scope="${3:-$VARIABLE_SCOPE_STACK}"
    local type="${4:-$VARIABLE_TYPE_STRING}"
    
    # Validate variable name
    if [[ ! "$name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        log_error "Invalid variable name: $name (must be uppercase, start with letter, contain only letters, numbers, and underscores)"
        return 1
    fi
    
    # Create backup
    cp "${VARIABLE_STORE_FILE}" "${VARIABLE_STORE_BACKUP}" 2>/dev/null || true
    
    # Update variable store
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg name "$name" \
       --arg value "$value" \
       --arg scope "$scope" \
       --arg type "$type" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.metadata.last_modified = $timestamp | 
        .[$scope][$name] = {
            "value": $value,
            "type": $type,
            "scope": $scope,
            "set_at": $timestamp
        }' "${VARIABLE_STORE_FILE}" > "$temp_file"
    
    mv "$temp_file" "${VARIABLE_STORE_FILE}"
    
    # Export variable for current session
    export "$name"="$value"
}

# Get variable from store
get_variable() {
    local name="$1"
    local scope="${2:-$VARIABLE_SCOPE_STACK}"
    local default_value="${3:-}"
    
    # Check if variable exists in store
    if [[ -f "${VARIABLE_STORE_FILE}" ]]; then
        local value
        value=$(jq -r --arg name "$name" --arg scope "$scope" '.[$scope][$name].value // empty' "${VARIABLE_STORE_FILE}" 2>/dev/null)
        
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    # Return default value if provided
    if [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    fi
    
    # Return empty string if not found
    return 1
}

# Get all variables for a scope
get_variables_for_scope() {
    local scope="${1:-$VARIABLE_SCOPE_STACK}"
    
    if [[ -f "${VARIABLE_STORE_FILE}" ]]; then
        jq -r --arg scope "$scope" '.[$scope] | to_entries[] | "\(.key)=\(.value.value)"' "${VARIABLE_STORE_FILE}" 2>/dev/null
    fi
}

# Delete variable from store
delete_variable() {
    local name="$1"
    local scope="${2:-$VARIABLE_SCOPE_STACK}"
    
    # Create backup
    cp "${VARIABLE_STORE_FILE}" "${VARIABLE_STORE_BACKUP}" 2>/dev/null || true
    
    # Remove variable from store
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg name "$name" \
       --arg scope "$scope" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.metadata.last_modified = $timestamp | 
        .[$scope] |= del(.[$name])' "${VARIABLE_STORE_FILE}" > "$temp_file"
    
    mv "$temp_file" "${VARIABLE_STORE_FILE}"
    
    # Unset variable from current session
    unset "$name" 2>/dev/null || true
}

# Clear temporary variables
clear_temporary_variables() {
    # Create backup
    cp "${VARIABLE_STORE_FILE}" "${VARIABLE_STORE_BACKUP}" 2>/dev/null || true
    
    # Clear temporary scope
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.metadata.last_modified = $timestamp | 
        .temporary = {}' "${VARIABLE_STORE_FILE}" > "$temp_file"
    
    mv "$temp_file" "${VARIABLE_STORE_FILE}"
}

# =============================================================================
# RESOURCE NAMING FUNCTIONS
# =============================================================================

# Generate resource name
generate_resource_name() {
    local resource_type="$1"
    local stack_name="${2:-$(get_variable STACK_NAME)}"
    local suffix="${3:-}"
    local az="${4:-}"
    
    # Validate stack name
    if [[ ! "$stack_name" =~ $STACK_NAME_PATTERN ]]; then
        log_error "Invalid stack name for resource naming: $stack_name"
        return 1
    fi
    
    # Generate name based on resource type
    case "$resource_type" in
        "vpc")
            echo "${stack_name}-vpc"
            ;;
        "subnet")
            if [[ -n "$suffix" && -n "$az" ]]; then
                echo "${stack_name}-subnet-${suffix}-${az}"
            elif [[ -n "$suffix" ]]; then
                echo "${stack_name}-subnet-${suffix}"
            else
                echo "${stack_name}-subnet"
            fi
            ;;
        "security-group")
            if [[ -n "$suffix" ]]; then
                echo "${stack_name}-sg-${suffix}"
            else
                echo "${stack_name}-sg"
            fi
            ;;
        "launch-template")
            echo "${stack_name}-lt"
            ;;
        "auto-scaling-group")
            echo "${stack_name}-asg"
            ;;
        "load-balancer")
            echo "${stack_name}-alb"
            ;;
        "target-group")
            if [[ -n "$suffix" ]]; then
                echo "${stack_name}-tg-${suffix}"
            else
                echo "${stack_name}-tg"
            fi
            ;;
        "cloudfront")
            echo "${stack_name}-cf"
            ;;
        "efs")
            echo "${stack_name}-efs"
            ;;
        "iam-role")
            if [[ -n "$suffix" ]]; then
                echo "${stack_name}-role-${suffix}"
            else
                echo "${stack_name}-role"
            fi
            ;;
        "iam-policy")
            if [[ -n "$suffix" ]]; then
                echo "${stack_name}-policy-${suffix}"
            else
                echo "${stack_name}-policy"
            fi
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Generate tag set
generate_tags() {
    local stack_name="${1:-$(get_variable STACK_NAME)}"
    local environment="${2:-$(get_variable ENVIRONMENT)}"
    local additional_tags="${3:-}"
    
    # Base tags
    local tags=(
        "Name=${stack_name}"
        "Environment=${environment}"
        "Project=GeuseMaker"
        "ManagedBy=DeploymentScript"
        "CreatedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    )
    
    # Add additional tags if provided
    if [[ -n "$additional_tags" ]]; then
        # Parse additional tags (format: "key1=value1,key2=value2")
        IFS=',' read -ra ADDTAGS <<< "$additional_tags"
        for tag in "${ADDTAGS[@]}"; do
            if [[ "$tag" =~ ^[A-Za-z][A-Za-z0-9-]*=.*$ ]]; then
                tags+=("$tag")
            else
                log_warn "Invalid tag format: $tag (skipping)"
            fi
        done
    fi
    
    # Convert to AWS CLI format
    local aws_tags=""
    for tag in "${tags[@]}"; do
        if [[ -n "$aws_tags" ]]; then
            aws_tags="${aws_tags} "
        fi
        aws_tags="${aws_tags}Key=$(echo "$tag" | cut -d'=' -f1),Value=$(echo "$tag" | cut -d'=' -f2-)"
    done
    
    echo "$aws_tags"
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Load environment configuration
load_environment_config() {
    local environment="${1:-development}"
    local config_file="${ENV_DIR}/${environment}.yml"
    
    # Check if environment config exists
    if [[ ! -f "$config_file" ]]; then
        log_warn "Environment config not found: $config_file (using defaults)"
        return 0
    fi
    
    # Load configuration using yq or jq
    if command -v yq >/dev/null 2>&1; then
        # Parse YAML configuration
        while IFS='=' read -r key value; do
            if [[ -n "$key" && "$key" != "#"* ]]; then
                set_variable "$key" "$value" "$VARIABLE_SCOPE_ENVIRONMENT"
            fi
        done < <(yq eval 'to_entries | .[] | .key + "=" + (.value | tostring)' "$config_file")
    else
        log_warn "yq not found, skipping environment configuration loading"
    fi
}

# Get configuration value with fallback
get_config_value() {
    local key="$1"
    local default_value="${2:-}"
    
    # Try to get from environment scope first
    local value
    value=$(get_variable "$key" "$VARIABLE_SCOPE_ENVIRONMENT")
    if [[ $? -eq 0 ]]; then
        echo "$value"
        return 0
    fi
    
    # Try to get from stack scope
    value=$(get_variable "$key" "$VARIABLE_SCOPE_STACK")
    if [[ $? -eq 0 ]]; then
        echo "$value"
        return 0
    fi
    
    # Try to get from global scope
    value=$(get_variable "$key" "$VARIABLE_SCOPE_GLOBAL")
    if [[ $? -eq 0 ]]; then
        echo "$value"
        return 0
    fi
    
    # Return default value
    echo "$default_value"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate resource name
validate_resource_name() {
    local name="$1"
    local resource_type="${2:-}"
    
    # Check basic pattern
    if [[ ! "$name" =~ $RESOURCE_NAME_PATTERN ]]; then
        log_error "Invalid resource name: $name"
        return 1
    fi
    
    # Check length limits for specific resource types
    case "$resource_type" in
        "vpc")
            if [[ ${#name} -gt 255 ]]; then
                log_error "VPC name too long: $name (max 255 characters)"
                return 1
            fi
            ;;
        "subnet")
            if [[ ${#name} -gt 255 ]]; then
                log_error "Subnet name too long: $name (max 255 characters)"
                return 1
            fi
            ;;
        "security-group")
            if [[ ${#name} -gt 255 ]]; then
                log_error "Security group name too long: $name (max 255 characters)"
                return 1
            fi
            ;;
        "iam-role")
            if [[ ${#name} -gt 64 ]]; then
                log_error "IAM role name too long: $name (max 64 characters)"
                return 1
            fi
            ;;
        "iam-policy")
            if [[ ${#name} -gt 128 ]]; then
                log_error "IAM policy name too long: $name (max 128 characters)"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Validate CIDR block
validate_cidr_block() {
    local cidr="$1"
    
    # Check CIDR format
    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid CIDR format: $cidr"
        return 1
    fi
    
    # Extract network and prefix
    local network="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Validate network octets
    IFS='.' read -ra OCTETS <<< "$network"
    for octet in "${OCTETS[@]}"; do
        if [[ "$octet" -lt 0 || "$octet" -gt 255 ]]; then
            log_error "Invalid network octet in CIDR: $cidr"
            return 1
        fi
    done
    
    # Validate prefix length
    if [[ "$prefix" -lt 0 || "$prefix" -gt 32 ]]; then
        log_error "Invalid prefix length in CIDR: $cidr"
        return 1
    fi
    
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Export all variables for a scope
export_scope_variables() {
    local scope="${1:-$VARIABLE_SCOPE_STACK}"
    
    # Get all variables for the scope
    while IFS='=' read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            export "$key"="$value"
        fi
    done < <(get_variables_for_scope "$scope")
}

# Get variable store statistics
get_variable_store_stats() {
    if [[ -f "${VARIABLE_STORE_FILE}" ]]; then
        echo "Variable Store Statistics:"
        echo "  Global variables: $(jq '.global | length' "${VARIABLE_STORE_FILE}")"
        echo "  Stack variables: $(jq '.stacks | length' "${VARIABLE_STORE_FILE}")"
        echo "  Environment variables: $(jq '.environments | length' "${VARIABLE_STORE_FILE}")"
        echo "  Temporary variables: $(jq '.temporary | length' "${VARIABLE_STORE_FILE}")"
        echo "  Last modified: $(jq -r '.metadata.last_modified' "${VARIABLE_STORE_FILE}")"
    else
        echo "Variable store not initialized"
    fi
}

# Backup variable store
backup_variable_store() {
    local backup_file="${VARIABLE_STORE_BACKUP}.$(date +%Y%m%d-%H%M%S)"
    
    if [[ -f "${VARIABLE_STORE_FILE}" ]]; then
        cp "${VARIABLE_STORE_FILE}" "$backup_file"
        log_info "Variable store backed up to: $backup_file"
    else
        log_warn "Variable store file not found, nothing to backup"
    fi
}

# Restore variable store from backup
restore_variable_store() {
    local backup_file="$1"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "${VARIABLE_STORE_FILE}"
        log_info "Variable store restored from: $backup_file"
    else
        log_error "Backup file not found: $backup_file"
        return 1
    fi
}

# =============================================================================
# VERSION UTILITIES
# =============================================================================

# Compare two version strings
# Returns: 0 if equal, 1 if version1 > version2, 2 if version1 < version2
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Handle empty versions
    if [[ -z "$version1" && -z "$version2" ]]; then
        return 0
    elif [[ -z "$version1" ]]; then
        return 2
    elif [[ -z "$version2" ]]; then
        return 1
    fi
    
    # Split versions into arrays
    IFS='.' read -ra V1 <<< "$version1"
    IFS='.' read -ra V2 <<< "$version2"
    
    # Pad arrays to same length
    local max_parts=$((${#V1[@]} > ${#V2[@]} ? ${#V1[@]} : ${#V2[@]}))
    
    for ((i=0; i<max_parts; i++)); do
        local part1="${V1[i]:-0}"
        local part2="${V2[i]:-0}"
        
        # Remove any non-numeric suffix (e.g., "-rc1", "-alpha")
        part1="${part1%%-*}"
        part2="${part2%%-*}"
        
        # Convert to numbers for comparison
        if [[ "$part1" -gt "$part2" ]]; then
            return 1
        elif [[ "$part1" -lt "$part2" ]]; then
            return 2
        fi
    done
    
    return 0
}

