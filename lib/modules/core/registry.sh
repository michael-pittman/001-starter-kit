#!/usr/bin/env bash
# =============================================================================
# Modern Resource Registry
# Advanced resource tracking with associative arrays and dependency management
# Requires: bash 5.3.3+
# =============================================================================

# Require bash 5.3+ for modern features
if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3))); then
    echo "ERROR: This module requires bash 5.3+ for modern resource tracking" >&2
    echo "Current version: ${BASH_VERSION}" >&2
    echo "Consider using legacy wrapper: lib/modules/compatibility/legacy_wrapper.sh" >&2
    return 1
fi

# Prevent multiple sourcing
[ -n "${_REGISTRY_SH_LOADED:-}" ] && return 0
declare -gr _REGISTRY_SH_LOADED=1

# Bash version validation for modules (non-exiting)
if [[ -z "${BASH_VERSION_VALIDATED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/bash_version.sh"
    if ! bash_533_available; then
        echo "WARNING: core/registry.sh requires bash 5.3.3+ but found $(get_current_bash_version)" >&2
    fi
fi

# =============================================================================
# MODERN RESOURCE TRACKING WITH ASSOCIATIVE ARRAYS
# =============================================================================

# Resource registry file
RESOURCE_REGISTRY_FILE="${RESOURCE_REGISTRY_FILE:-/tmp/deployment-registry-$$.json}"

# Modern resource tracking with associative arrays for performance
declare -gA RESOURCE_METADATA=()      # resource_id -> JSON metadata
declare -gA RESOURCE_STATUS=()        # resource_id -> status
declare -gA RESOURCE_DEPENDENCIES=()  # resource_id -> space-separated dependencies
declare -gA RESOURCE_CLEANUP_COMMANDS=()  # resource_id -> cleanup command
declare -gA RESOURCE_TYPES=()         # resource_id -> type
declare -gA RESOURCE_TIMESTAMPS=()    # resource_id -> creation timestamp
declare -gA RESOURCE_TAGS=()          # resource_id -> JSON tags

# Performance optimization: resource lookup by type
declare -gA RESOURCES_BY_TYPE=()      # type -> space-separated resource_ids

# Dependency graph for ordered cleanup
declare -gA DEPENDENCY_GRAPH=()       # parent_id -> space-separated child_ids

# Modern resource data management with type safety and performance
get_resource_data() {
    local resource_id="$1"
    local data_type="${2:-metadata}"  # metadata, status, dependencies, cleanup, tags
    
    case "$data_type" in
        "metadata")
            echo "${RESOURCE_METADATA[$resource_id]:-{}}"
            ;;
        "status")
            echo "${RESOURCE_STATUS[$resource_id]:-$STATUS_PENDING}"
            ;;
        "dependencies")
            echo "${RESOURCE_DEPENDENCIES[$resource_id]:-}"
            ;;
        "cleanup")
            echo "${RESOURCE_CLEANUP_COMMANDS[$resource_id]:-}"
            ;;
        "type")
            echo "${RESOURCE_TYPES[$resource_id]:-unknown}"
            ;;
        "timestamp")
            echo "${RESOURCE_TIMESTAMPS[$resource_id]:-}"
            ;;
        "tags")
            echo "${RESOURCE_TAGS[$resource_id]:-{}}"
            ;;
        *)
            echo "ERROR: Unknown data type: $data_type" >&2
            return 1
            ;;
    esac
}

set_resource_data() {
    local resource_id="$1"
    local data_type="$2"
    local value="$3"
    
    # Validate resource_id format
    if [[ ! "$resource_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid resource ID format: $resource_id" >&2
        return 1
    fi
    
    case "$data_type" in
        "metadata")
            RESOURCE_METADATA["$resource_id"]="$value"
            ;;
        "status")
            RESOURCE_STATUS["$resource_id"]="$value"
            ;;
        "dependencies")
            RESOURCE_DEPENDENCIES["$resource_id"]="$value"
            ;;
        "cleanup")
            RESOURCE_CLEANUP_COMMANDS["$resource_id"]="$value"
            ;;
        "type")
            RESOURCE_TYPES["$resource_id"]="$value"
            # Update type index
            local current_resources="${RESOURCES_BY_TYPE[$value]:-}"
            if [[ " $current_resources " != *" $resource_id "* ]]; then
                RESOURCES_BY_TYPE["$value"]="${current_resources} $resource_id"
            fi
            ;;
        "timestamp")
            RESOURCE_TIMESTAMPS["$resource_id"]="$value"
            ;;
        "tags")
            RESOURCE_TAGS["$resource_id"]="$value"
            ;;
        *)
            echo "ERROR: Unknown data type: $data_type" >&2
            return 1
            ;;
    esac
}

# Get all resource IDs of a specific type
get_resources_by_type() {
    local resource_type="$1"
    echo "${RESOURCES_BY_TYPE[$resource_type]:-}" | xargs -n1 | sort -u | xargs
}

# Get all registered resource IDs
get_all_resource_ids() {
    printf '%s\n' "${!RESOURCE_TYPES[@]}" | sort
}

# Enhanced status constants with additional states
if [[ -z "${STATUS_PENDING:-}" ]]; then
    declare -gr STATUS_PENDING="pending"
    declare -gr STATUS_CREATING="creating"
    declare -gr STATUS_CREATED="created"
    declare -gr STATUS_UPDATING="updating"
    declare -gr STATUS_FAILED="failed"
    declare -gr STATUS_DELETING="deleting"
    declare -gr STATUS_DELETED="deleted"
    declare -gr STATUS_UNKNOWN="unknown"
    
    # Status validation array
    declare -gA VALID_STATUSES=(
        ["$STATUS_PENDING"]=1
        ["$STATUS_CREATING"]=1
        ["$STATUS_CREATED"]=1
        ["$STATUS_UPDATING"]=1
        ["$STATUS_FAILED"]=1
        ["$STATUS_DELETING"]=1
        ["$STATUS_DELETED"]=1
        ["$STATUS_UNKNOWN"]=1
    )
fi

# Validate status value
validate_status() {
    local status="$1"
    [[ -v VALID_STATUSES["$status"] ]]
}

# Initialize registry
initialize_registry() {
    local stack_name="${1:-${STACK_NAME:-default}}"
    
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
    
    # Return empty object if input is empty, null, or the string "null"
    if [ -z "$input" ] || [ "$input" = "null" ] || [ "$input" = "{}" ]; then
        echo "{}"
        return 0
    fi
    
    # Remove control characters, newlines, and fix common JSON issues
    # First, clean up the string
    local cleaned
    cleaned=$(echo "$input" | tr -d '\n\r\t' | tr -d '\000-\037' | sed 's/\\n//g; s/\\r//g; s/\\t//g')
    
    # Check if the input is already valid JSON
    if echo "$cleaned" | jq . >/dev/null 2>&1; then
        echo "$cleaned"
        return 0
    fi
    
    # If not valid JSON, try to construct valid JSON
    # Handle key:value pairs that might not be properly quoted
    if [[ "$cleaned" =~ ^[[:space:]]*\{ ]]; then
        # Try to fix common JSON issues
        local fixed
        # Use simpler sed commands for macOS compatibility
        fixed=$(echo "$cleaned" | sed 's/\([{,]\)[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*:/\1"\2":/g')
        
        if echo "$fixed" | jq . >/dev/null 2>&1; then
            echo "$fixed"
            return 0
        fi
    fi
    
    # If still not valid, wrap as a simple object
    local escaped
    escaped=$(echo "$cleaned" | sed 's/"/\\"/g')
    echo "{\"value\": \"$escaped\"}"
}

# Enhanced resource registration with dependency tracking and validation
register_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local metadata="${3:-{}}"
    local cleanup_command="${4:-}"
    local dependencies="${5:-}"  # Space-separated list of resource IDs this depends on
    local tags="${6:-{}}"
    
    # Validate inputs
    if [[ -z "$resource_type" || -z "$resource_id" ]]; then
        echo "ERROR: Resource type and ID are required" >&2
        return 1
    fi
    
    # Check for duplicate registration
    if [[ -v RESOURCE_TYPES["$resource_id"] ]]; then
        echo "WARNING: Resource '$resource_id' already registered, updating..." >&2
    fi
    
    # Ensure registry exists
    initialize_registry
    
    # Validate and sanitize metadata JSON
    local validated_metadata
    validated_metadata=$(sanitize_json_string "$metadata")
    
    if ! echo "$validated_metadata" | jq . >/dev/null 2>&1; then
        echo "WARNING: Invalid metadata JSON for resource '$resource_id', using empty object" >&2
        validated_metadata="{}"
    fi
    
    # Validate and sanitize tags JSON
    local validated_tags
    validated_tags=$(sanitize_json_string "$tags")
    
    if ! echo "$validated_tags" | jq . >/dev/null 2>&1; then
        echo "WARNING: Invalid tags JSON for resource '$resource_id', using empty object" >&2
        validated_tags="{}"
    fi
    
    # Validate dependencies exist
    if [[ -n "$dependencies" ]]; then
        local invalid_deps=()
        for dep in $dependencies; do
            if [[ ! -v RESOURCE_TYPES["$dep"] ]]; then
                invalid_deps+=("$dep")
            fi
        done
        
        if (( ${#invalid_deps[@]} > 0 )); then
            echo "WARNING: Invalid dependencies for '$resource_id': ${invalid_deps[*]}" >&2
            # Remove invalid dependencies
            local valid_deps=()
            for dep in $dependencies; do
                if [[ -v RESOURCE_TYPES["$dep"] ]]; then
                    valid_deps+=("$dep")
                fi
            done
            dependencies="${valid_deps[*]}"
        fi
    fi
    
    # Register resource in memory structures
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    set_resource_data "$resource_id" "type" "$resource_type"
    set_resource_data "$resource_id" "metadata" "$validated_metadata"
    set_resource_data "$resource_id" "status" "$STATUS_CREATING"
    set_resource_data "$resource_id" "timestamp" "$timestamp"
    set_resource_data "$resource_id" "tags" "$validated_tags"
    
    [[ -n "$cleanup_command" ]] && set_resource_data "$resource_id" "cleanup" "$cleanup_command"
    [[ -n "$dependencies" ]] && set_resource_data "$resource_id" "dependencies" "$dependencies"
    
    # Update dependency graph for cleanup ordering
    if [[ -n "$dependencies" ]]; then
        for dep in $dependencies; do
            local current_children="${DEPENDENCY_GRAPH[$dep]:-}"
            if [[ " $current_children " != *" $resource_id "* ]]; then
                DEPENDENCY_GRAPH["$dep"]="${current_children} $resource_id"
            fi
        done
    fi
    
    # Update JSON registry file
    update_json_registry "$resource_type" "$resource_id" "$validated_metadata" "$timestamp"
    
    echo "Resource registered: $resource_type/$resource_id" >&2
    return 0
}

# Update JSON registry file (separated for performance)
update_json_registry() {
    local resource_type="$1"
    local resource_id="$2"
    local metadata="$3"
    local timestamp="$4"
    
    local temp_file
    temp_file=$(mktemp)
    
    # Use jq to safely update the JSON registry
    if jq --arg type "$resource_type" \
          --arg id "$resource_id" \
          --argjson metadata "$metadata" \
          --arg timestamp "$timestamp" \
          '.resources[$type] += [{
              "id": $id,
              "created_at": $timestamp,
              "metadata": $metadata
          }]' "$RESOURCE_REGISTRY_FILE" > "$temp_file"; then
        mv "$temp_file" "$RESOURCE_REGISTRY_FILE"
    else
        echo "WARNING: Failed to update JSON registry for $resource_id" >&2
        rm -f "$temp_file"
    fi
}

# Enhanced resource status management with validation and history
update_resource_status() {
    local resource_id="$1"
    local new_status="$2"
    local reason="${3:-}"  # Optional reason for status change
    
    # Validate resource exists
    if [[ ! -v RESOURCE_TYPES["$resource_id"] ]]; then
        echo "ERROR: Cannot update status for unregistered resource: $resource_id" >&2
        return 1
    fi
    
    # Validate status value
    if ! validate_status "$new_status"; then
        echo "ERROR: Invalid status value: $new_status" >&2
        echo "Valid statuses: ${!VALID_STATUSES[*]}" >&2
        return 1
    fi
    
    local old_status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
    
    # Check for valid status transitions
    if ! is_valid_status_transition "$old_status" "$new_status"; then
        echo "WARNING: Invalid status transition for $resource_id: $old_status -> $new_status" >&2
    fi
    
    # Update status
    set_resource_data "$resource_id" "status" "$new_status"
    
    # Log status change
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Resource status updated: $resource_id ($old_status -> $new_status) at $timestamp" >&2
    
    if [[ -n "$reason" ]]; then
        echo "Reason: $reason" >&2
    fi
    
    return 0
}

# Validate status transitions
is_valid_status_transition() {
    local from_status="$1"
    local to_status="$2"
    
    # Define valid status transitions
    case "$from_status" in
        "$STATUS_PENDING")
            [[ "$to_status" =~ ^($STATUS_CREATING|$STATUS_FAILED)$ ]]
            ;;
        "$STATUS_CREATING")
            [[ "$to_status" =~ ^($STATUS_CREATED|$STATUS_FAILED)$ ]]
            ;;
        "$STATUS_CREATED")
            [[ "$to_status" =~ ^($STATUS_UPDATING|$STATUS_DELETING|$STATUS_FAILED)$ ]]
            ;;
        "$STATUS_UPDATING")
            [[ "$to_status" =~ ^($STATUS_CREATED|$STATUS_FAILED)$ ]]
            ;;
        "$STATUS_DELETING")
            [[ "$to_status" =~ ^($STATUS_DELETED|$STATUS_FAILED)$ ]]
            ;;
        "$STATUS_FAILED")
            [[ "$to_status" =~ ^($STATUS_CREATING|$STATUS_DELETING)$ ]]
            ;;
        "$STATUS_DELETED")
            # Deleted resources shouldn't change status
            [[ "$to_status" == "$STATUS_DELETED" ]]
            ;;
        *)
            # Unknown status - allow any transition
            true
            ;;
    esac
}

# Enhanced resource querying with filtering and sorting
get_resources() {
    local resource_type="$1"
    local status_filter="${2:-}"  # Optional status filter
    local sort_by="${3:-timestamp}"  # timestamp, id, status
    local limit="${4:-}"  # Optional limit
    
    # Use in-memory data for better performance
    local resource_ids
    resource_ids=$(get_resources_by_type "$resource_type")
    
    if [[ -z "$resource_ids" ]]; then
        return 1
    fi
    
    # Apply status filter if specified
    local filtered_ids=()
    for resource_id in $resource_ids; do
        if [[ -n "$status_filter" ]]; then
            local resource_status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
            [[ "$resource_status" == "$status_filter" ]] || continue
        fi
        filtered_ids+=("$resource_id")
    done
    
    # Sort resources
    local sorted_ids=()
    case "$sort_by" in
        "timestamp")
            # Sort by creation timestamp (newest first)
            while IFS= read -r -d '' resource_id; do
                sorted_ids+=("$resource_id")
            done < <(
                for resource_id in "${filtered_ids[@]}"; do
                    local timestamp="${RESOURCE_TIMESTAMPS[$resource_id]:-0}"
                    printf '%s\0' "$resource_id"
                done | sort -z -k1,1
            )
            ;;
        "id")
            # Sort alphabetically by ID
            IFS=$'\n' read -d '' -ra sorted_ids < <(
                printf '%s\n' "${filtered_ids[@]}" | sort
            )
            ;;
        "status")
            # Sort by status
            while IFS= read -r resource_id; do
                sorted_ids+=("$resource_id")
            done < <(
                for resource_id in "${filtered_ids[@]}"; do
                    local status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
                    echo "$status $resource_id"
                done | sort | cut -d' ' -f2-
            )
            ;;
        *)
            sorted_ids=("${filtered_ids[@]}")
            ;;
    esac
    
    # Apply limit if specified
    if [[ -n "$limit" && "$limit" =~ ^[0-9]+$ ]]; then
        sorted_ids=("${sorted_ids[@]:0:$limit}")
    fi
    
    # Output results
    for resource_id in "${sorted_ids[@]}"; do
        echo "$resource_id"
    done
    
    return 0
}

# Enhanced get all resources with detailed information
get_all_resources() {
    local format="${1:-simple}"  # simple, detailed, json
    local status_filter="${2:-}"  # Optional status filter
    
    case "$format" in
        "json")
            echo "{"
            local first=true
            for resource_id in "${!RESOURCE_TYPES[@]}"; do
                local status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
                
                # Apply status filter
                [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue
                
                [[ "$first" == "false" ]] && echo ","
                first=false
                
                local resource_type="${RESOURCE_TYPES[$resource_id]}"
                local metadata="${RESOURCE_METADATA[$resource_id]:-{}}"
                local timestamp="${RESOURCE_TIMESTAMPS[$resource_id]:-}"
                local dependencies="${RESOURCE_DEPENDENCIES[$resource_id]:-}"
                local tags="${RESOURCE_TAGS[$resource_id]:-{}}"
                
                echo -n "  \"$resource_id\": {"
                echo -n "\"type\": \"$resource_type\","
                echo -n "\"status\": \"$status\","
                echo -n "\"timestamp\": \"$timestamp\","
                echo -n "\"dependencies\": \"$dependencies\","
                echo -n "\"metadata\": $metadata,"
                echo -n "\"tags\": $tags"
                echo -n "}"
            done
            echo
            echo "}"
            ;;
        "detailed")
            printf "%-20s %-15s %-12s %-20s %-30s\n" "RESOURCE_ID" "TYPE" "STATUS" "TIMESTAMP" "DEPENDENCIES"
            printf "%-20s %-15s %-12s %-20s %-30s\n" "-----------" "----" "------" "---------" "------------"
            
            for resource_id in $(printf '%s\n' "${!RESOURCE_TYPES[@]}" | sort); do
                local resource_type="${RESOURCE_TYPES[$resource_id]}"
                local status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
                local timestamp="${RESOURCE_TIMESTAMPS[$resource_id]:-}"
                local dependencies="${RESOURCE_DEPENDENCIES[$resource_id]:-}"
                
                # Apply status filter
                [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue
                
                # Truncate long values for display
                local short_timestamp="${timestamp:0:19}"  # Remove seconds and timezone
                local short_deps="${dependencies:0:29}"
                
                printf "%-20s %-15s %-12s %-20s %-30s\n" \
                    "${resource_id:0:19}" "${resource_type:0:14}" "$status" \
                    "$short_timestamp" "$short_deps"
            done
            ;;
        "simple"|*)
            for resource_id in $(printf '%s\n' "${!RESOURCE_TYPES[@]}" | sort); do
                local resource_type="${RESOURCE_TYPES[$resource_id]}"
                local status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
                
                # Apply status filter
                [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue
                
                echo "${resource_type}:${resource_id}:${status}"
            done
            ;;
    esac
}

# Enhanced resource existence checking with status validation
resource_exists() {
    local resource_id="$1"
    local expected_status="${2:-}"  # Optional expected status
    
    # Check if resource is registered
    if [[ ! -v RESOURCE_TYPES["$resource_id"] ]]; then
        return 1
    fi
    
    # Check status if specified
    if [[ -n "$expected_status" ]]; then
        local current_status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
        [[ "$current_status" == "$expected_status" ]]
    else
        return 0
    fi
}

# Check if resource exists and is in a healthy state
resource_is_healthy() {
    local resource_id="$1"
    
    resource_exists "$resource_id" && {
        local status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
        [[ "$status" =~ ^($STATUS_CREATED|$STATUS_UPDATING)$ ]]
    }
}

# Check if resource exists and has failed
resource_has_failed() {
    local resource_id="$1"
    
    resource_exists "$resource_id" && {
        local status="${RESOURCE_STATUS[$resource_id]:-$STATUS_UNKNOWN}"
        [[ "$status" == "$STATUS_FAILED" ]]
    }
}

# Enhanced resource unregistration with dependency cleanup
unregister_resource() {
    local resource_id="$1"
    local force="${2:-false}"  # Force removal even with dependencies
    
    # Check if resource exists
    if [[ ! -v RESOURCE_TYPES["$resource_id"] ]]; then
        echo "WARNING: Resource '$resource_id' not found in registry" >&2
        return 0
    fi
    
    # Check for dependent resources
    local dependents="${DEPENDENCY_GRAPH[$resource_id]:-}"
    if [[ -n "$dependents" && "$force" != "true" ]]; then
        echo "ERROR: Cannot remove resource '$resource_id' - has dependents: $dependents" >&2
        echo "Use force=true to override or remove dependents first" >&2
        return 1
    fi
    
    local resource_type="${RESOURCE_TYPES[$resource_id]}"
    
    # Remove from in-memory structures
    unset RESOURCE_TYPES["$resource_id"]
    unset RESOURCE_METADATA["$resource_id"]
    unset RESOURCE_STATUS["$resource_id"]
    unset RESOURCE_DEPENDENCIES["$resource_id"]
    unset RESOURCE_CLEANUP_COMMANDS["$resource_id"]
    unset RESOURCE_TIMESTAMPS["$resource_id"]
    unset RESOURCE_TAGS["$resource_id"]
    
    # Update type index
    local type_resources="${RESOURCES_BY_TYPE[$resource_type]:-}"
    local updated_resources=()
    for res_id in $type_resources; do
        [[ "$res_id" != "$resource_id" ]] && updated_resources+=("$res_id")
    done
    RESOURCES_BY_TYPE["$resource_type"]="${updated_resources[*]}"
    
    # Clean up dependency graph
    unset DEPENDENCY_GRAPH["$resource_id"]
    for parent_id in "${!DEPENDENCY_GRAPH[@]}"; do
        local children="${DEPENDENCY_GRAPH[$parent_id]}"
        local updated_children=()
        for child_id in $children; do
            [[ "$child_id" != "$resource_id" ]] && updated_children+=("$child_id")
        done
        DEPENDENCY_GRAPH["$parent_id"]="${updated_children[*]}"
    done
    
    # Update JSON registry file
    if [[ -f "$RESOURCE_REGISTRY_FILE" ]]; then
        local temp_file
        temp_file=$(mktemp)
        
        if jq --arg type "$resource_type" \
              --arg id "$resource_id" \
              '.resources[$type] |= map(select(.id != $id))' \
              "$RESOURCE_REGISTRY_FILE" > "$temp_file"; then
            mv "$temp_file" "$RESOURCE_REGISTRY_FILE"
        else
            echo "WARNING: Failed to update JSON registry during unregistration" >&2
            rm -f "$temp_file"
        fi
    fi
    
    echo "Resource unregistered: $resource_type/$resource_id" >&2
    return 0
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

# Convert tags to IAM CLI format (individual JSON objects)
tags_to_iam_format() {
    local tags_json="$1"
    
    echo "$tags_json" | jq -r 'to_entries | map("{\"Key\": \"\(.key)\", \"Value\": \"\(.value)\"}") | join(" ")'
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