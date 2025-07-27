#!/bin/bash
# =============================================================================
# Resource Registry
# Tracks all created resources for cleanup and management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_REGISTRY_SH_LOADED:-}" ] && return 0
_REGISTRY_SH_LOADED=1

# =============================================================================
# RESOURCE TRACKING WITH DEPENDENCIES
# =============================================================================

# Resource registry file
RESOURCE_REGISTRY_FILE="${RESOURCE_REGISTRY_FILE:-/tmp/deployment-registry-$$.json}"

# Resource status tracking (bash 3.x compatible)
# Use function-based approach instead of associative arrays
RESOURCE_STATUS_KEYS=""
RESOURCE_DEPENDENCIES_KEYS=""
RESOURCE_CLEANUP_COMMANDS_KEYS=""

# Function-based registry for resource tracking
get_resource_data() {
    local key="$1"
    local type="$2"
    local varname="RESOURCE_${type}_${key}"
    local value
    eval "value=\${${varname}:-}"
    echo "$value"
}

set_resource_data() {
    local key="$1"
    local type="$2"
    local value="$3"
    local varname="RESOURCE_${type}_${key}"
    local keys_var="RESOURCE_${type}_KEYS"
    
    # Export the value
    export "${varname}=${value}"
    
    # Add to keys list if not already present
    local current_keys
    eval "current_keys=\${${keys_var}}"
    if [[ " $current_keys " != *" $key "* ]]; then
        export "${keys_var}=${current_keys} ${key}"
    fi
}

get_resource_keys() {
    local type="$1"
    local keys_var="RESOURCE_${type}_KEYS"
    local keys
    eval "keys=\${${keys_var}}"
    echo "$keys"
}

# Status constants (avoid readonly redeclaration)
if [[ -z "${STATUS_PENDING:-}" ]]; then
    readonly STATUS_PENDING="pending"
    readonly STATUS_CREATING="creating"
    readonly STATUS_CREATED="created"
    readonly STATUS_FAILED="failed"
    readonly STATUS_DELETING="deleting"
    readonly STATUS_DELETED="deleted"
fi

# Initialize registry
initialize_registry() {
    local stack_name="${1:-$STACK_NAME}"
    
    if [ ! -f "$RESOURCE_REGISTRY_FILE" ]; then
        cat > "$RESOURCE_REGISTRY_FILE" <<EOF
{
    "stack_name": "$stack_name",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "region": "${AWS_REGION:-us-east-1}",
    "resources": {
        "instances": [],
        "volumes": [],
        "security_groups": [],
        "key_pairs": [],
        "iam_roles": [],
        "iam_policies": [],
        "vpc": [],
        "subnets": [],
        "internet_gateways": [],
        "route_tables": [],
        "elastic_ips": [],
        "network_interfaces": [],
        "target_groups": [],
        "load_balancers": [],
        "efs_filesystems": [],
        "efs_mount_targets": [],
        "spot_requests": []
    }
}
EOF
    fi
}

# Sanitize JSON string to remove control characters and fix formatting
sanitize_json_string() {
    local input="$1"
    
    # Return empty object if input is empty or null
    if [ -z "$input" ] || [ "$input" = "null" ] || [ "$input" = "{}" ]; then
        echo "{}"
        return 0
    fi
    
    # Remove control characters, newlines, and fix common JSON issues
    # First, clean up the string
    local cleaned
    cleaned=$(echo "$input" | tr -d '\n\r\t' | tr -d '\000-\037' | sed 's/\\n//g; s/\\r//g; s/\\t//g')
    
    # Ensure we have valid JSON structure
    if [[ ! "$cleaned" =~ ^[[:space:]]*\{ ]]; then
        # If it doesn't start with {, wrap it as a simple object
        cleaned="{\"value\": \"$(echo "$cleaned" | sed 's/"/\\"/g')\"}"
    fi
    
    # Test if it's valid JSON
    if echo "$cleaned" | jq . >/dev/null 2>&1; then
        echo "$cleaned"
    else
        # If still invalid, return empty object
        echo "{}"
    fi
}

# Register a resource
register_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local metadata="${3:-{}}"
    local cleanup_command="${4:-}"
    
    # Ensure registry exists
    initialize_registry
    
    # Store cleanup command if provided
    if [[ -n "$cleanup_command" ]]; then
        set_resource_data "${resource_id}" "CLEANUP_COMMANDS" "$cleanup_command"
    fi
    
    # Sanitize and validate metadata JSON
    local validated_metadata
    validated_metadata=$(sanitize_json_string "$metadata")
    
    # Double-check that we have valid JSON
    if ! echo "$validated_metadata" | jq . >/dev/null 2>&1; then
        echo "WARNING: Failed to sanitize metadata for resource '$resource_id', using empty object" >&2
        validated_metadata="{}"
    fi
    
    # Add resource to registry
    local temp_file=$(mktemp)
    jq --arg type "$resource_type" \
       --arg id "$resource_id" \
       --argjson metadata "$validated_metadata" \
       '.resources[$type] += [{
           "id": $id,
           "created_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
           "metadata": $metadata
       }]' "$RESOURCE_REGISTRY_FILE" > "$temp_file" && \
    mv "$temp_file" "$RESOURCE_REGISTRY_FILE"
}

# Update resource status (new function for compatibility)
update_resource_status() {
    local resource_id="$1"
    local status="$2"
    set_resource_data "${resource_id}" "STATUS" "$status"
}

# Get resources by type
get_resources() {
    local resource_type="$1"
    
    [ -f "$RESOURCE_REGISTRY_FILE" ] || return 1
    
    jq -r --arg type "$resource_type" \
        '.resources[$type][]?.id' "$RESOURCE_REGISTRY_FILE" 2>/dev/null
}

# Get all resources
get_all_resources() {
    [ -f "$RESOURCE_REGISTRY_FILE" ] || return 1
    
    jq -r '.resources | to_entries[] | .key as $type | .value[]? | "\($type):\(.id)"' \
        "$RESOURCE_REGISTRY_FILE" 2>/dev/null
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    [ -f "$RESOURCE_REGISTRY_FILE" ] || return 1
    
    jq -e --arg type "$resource_type" --arg id "$resource_id" \
        '.resources[$type][]? | select(.id == $id)' \
        "$RESOURCE_REGISTRY_FILE" >/dev/null 2>&1
}

# Remove resource from registry
unregister_resource() {
    local resource_type="$1"
    local resource_id="$2"
    
    [ -f "$RESOURCE_REGISTRY_FILE" ] || return 0
    
    local temp_file=$(mktemp)
    jq --arg type "$resource_type" \
       --arg id "$resource_id" \
       '.resources[$type] |= map(select(.id != $id))' \
       "$RESOURCE_REGISTRY_FILE" > "$temp_file" && \
    mv "$temp_file" "$RESOURCE_REGISTRY_FILE"
}

# =============================================================================
# TAGGING SUPPORT
# =============================================================================

# Generate standard tags
generate_tags() {
    local stack_name="${1:-$STACK_NAME}"
    local additional_tags="${2:-}"
    
    local base_tags=$(cat <<EOF
{
    "Name": "$stack_name",
    "Stack": "$stack_name",
    "ManagedBy": "aws-deployment-modular",
    "CreatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "Environment": "${ENVIRONMENT:-production}",
    "DeploymentType": "${DEPLOYMENT_TYPE:-spot}"
}
EOF
)
    
    if [ -n "$additional_tags" ]; then
        # Ensure additional_tags is valid JSON before merging
        if echo "$additional_tags" | jq . >/dev/null 2>&1; then
            # Use safe merging to handle potential conflicts
            echo "$base_tags" | jq -s --argjson additional "$additional_tags" '.[0] * $additional' 2>/dev/null || {
                echo "Warning: JSON merge failed for additional_tags, using base tags only" >&2
                echo "$base_tags"
            }
        else
            echo "Warning: Invalid JSON in additional_tags '$additional_tags', using base tags only" >&2
            echo "$base_tags"
        fi
    else
        echo "$base_tags"
    fi
}

# Convert tags to AWS CLI format
tags_to_cli_format() {
    local tags_json="$1"
    
    echo "$tags_json" | jq -r 'to_entries | map("Key=\(.key),Value=\(.value)") | join(" ")'
}

# Convert tags to tag specification format
tags_to_tag_spec() {
    local tags_json="$1"
    local resource_type="${2:-instance}"
    
    echo "$tags_json" | jq -c --arg type "$resource_type" \
        '{ResourceType: $type, Tags: (to_entries | map({Key: .key, Value: .value}))}'
}

# =============================================================================
# CLEANUP HELPERS
# =============================================================================

# Get cleanup order (reverse dependency order)
get_cleanup_order() {
    cat <<EOF
spot_requests
instances
network_interfaces
elastic_ips
efs_mount_targets
efs_filesystems
target_groups
load_balancers
route_tables
internet_gateways
subnets
security_groups
vpc
iam_policies
iam_roles
volumes
key_pairs
EOF
}

# Generate cleanup script from registry
generate_cleanup_script() {
    local output_file="${1:-cleanup-script.sh}"
    
    [ -f "$RESOURCE_REGISTRY_FILE" ] || {
        echo "ERROR: No resource registry found" >&2
        return 1
    }
    
    cat > "$output_file" <<'EOF'
#!/bin/bash
# Auto-generated cleanup script
set -euo pipefail

echo "Starting resource cleanup..."

# Source AWS region
EOF
    
    echo "export AWS_REGION='$(jq -r .region "$RESOURCE_REGISTRY_FILE")'" >> "$output_file"
    echo "" >> "$output_file"
    
    # Add cleanup commands for each resource type
    for resource_type in $(get_cleanup_order); do
        local resources=($(get_resources "$resource_type"))
        
        if [ ${#resources[@]} -gt 0 ]; then
            echo "# Cleanup $resource_type" >> "$output_file"
            
            case "$resource_type" in
                instances)
                    for id in "${resources[@]}"; do
                        echo "aws ec2 terminate-instances --instance-ids '$id' || true" >> "$output_file"
                    done
                    ;;
                security_groups)
                    for id in "${resources[@]}"; do
                        echo "aws ec2 delete-security-group --group-id '$id' || true" >> "$output_file"
                    done
                    ;;
                key_pairs)
                    for name in "${resources[@]}"; do
                        echo "aws ec2 delete-key-pair --key-name '$name' || true" >> "$output_file"
                    done
                    ;;
                # Add more resource types as needed
            esac
            
            echo "" >> "$output_file"
        fi
    done
    
    echo "echo 'Cleanup completed.'" >> "$output_file"
    chmod +x "$output_file"
}

# =============================================================================
# PERSISTENCE
# =============================================================================

# Save registry to S3 or local backup
backup_registry() {
    local backup_location="${1:-./registry-backups}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="registry_${STACK_NAME}_${timestamp}.json"
    
    if [[ "$backup_location" =~ ^s3:// ]]; then
        # Backup to S3
        aws s3 cp "$RESOURCE_REGISTRY_FILE" "${backup_location}/${backup_file}"
    else
        # Local backup
        mkdir -p "$backup_location"
        cp "$RESOURCE_REGISTRY_FILE" "${backup_location}/${backup_file}"
    fi
    
    echo "Registry backed up to: ${backup_location}/${backup_file}"
}

# Restore registry from backup
restore_registry() {
    local backup_file="$1"
    
    if [[ "$backup_file" =~ ^s3:// ]]; then
        # Restore from S3
        aws s3 cp "$backup_file" "$RESOURCE_REGISTRY_FILE"
    else
        # Local restore
        cp "$backup_file" "$RESOURCE_REGISTRY_FILE"
    fi
    
    echo "Registry restored from: $backup_file"
}

# =============================================================================
# COMPATIBILITY ALIASES AND FUNCTIONS
# =============================================================================

# Initialize registry for a specific stack (compatibility alias)
init_registry() {
    local stack_name="${1:-$STACK_NAME}"
    export STACK_NAME="$stack_name"
    initialize_registry
}

# Cleanup registry (remove registry file)
cleanup_registry() {
    local stack_name="${1:-$STACK_NAME}"
    
    if [ -f "$RESOURCE_REGISTRY_FILE" ]; then
        echo "Cleaning up resource registry for: $stack_name" >&2
        rm -f "$RESOURCE_REGISTRY_FILE"
    fi
}