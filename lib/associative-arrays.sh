#!/usr/bin/env bash
# =============================================================================
# Associative Array Utilities Library
# Modern bash 5.3.3+ utilities for comprehensive associative array operations
# Requires: bash 5.3.3+
# =============================================================================

# Bash version validation
if [[ -z "${BASH_VERSION_VALIDATED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/modules/core/bash_version.sh"
    require_bash_533 "associative-arrays.sh"
    export BASH_VERSION_VALIDATED=true
fi

# Prevent multiple sourcing
if [[ "${ASSOCIATIVE_ARRAYS_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly ASSOCIATIVE_ARRAYS_LIB_LOADED=true

# =============================================================================
# LIBRARY METADATA
# =============================================================================

readonly ASSOCIATIVE_ARRAYS_VERSION="1.0.0"
readonly ASSOCIATIVE_ARRAYS_REQUIRED_BASH="5.3.3"

# =============================================================================
# CORE ASSOCIATIVE ARRAY OPERATIONS
# =============================================================================

# Get value from associative array with optional default
# Usage: aa_get array_name key [default_value]
aa_get() {
    local -n arr_ref="$1"
    local key="$2"
    local default="${3:-}"
    
    if [[ -v "arr_ref[$key]" ]]; then
        echo "${arr_ref[$key]}"
    else
        echo "$default"
    fi
}

# Set value in associative array
# Usage: aa_set array_name key value
aa_set() {
    local -n arr_ref="$1"
    local key="$2"
    local value="$3"
    
    arr_ref["$key"]="$value"
}

# Check if key exists in associative array
# Usage: aa_has_key array_name key
aa_has_key() {
    local -n arr_ref="$1"
    local key="$2"
    
    [[ -v "arr_ref[$key]" ]]
}

# Delete key from associative array
# Usage: aa_delete array_name key
aa_delete() {
    local -n arr_ref="$1"
    local key="$2"
    
    if [[ -v "arr_ref[$key]" ]]; then
        unset "arr_ref[$key]"
        return 0
    else
        return 1
    fi
}

# Get all keys from associative array
# Usage: aa_keys array_name
aa_keys() {
    local -n arr_ref="$1"
    printf '%s\n' "${!arr_ref[@]}"
}

# Get all values from associative array
# Usage: aa_values array_name
aa_values() {
    local -n arr_ref="$1"
    printf '%s\n' "${arr_ref[@]}"
}

# Get size/length of associative array
# Usage: aa_size array_name
aa_size() {
    local -n arr_ref="$1"
    echo "${#arr_ref[@]}"
}

# Check if associative array is empty
# Usage: aa_is_empty array_name
aa_is_empty() {
    local -n arr_ref="$1"
    [[ ${#arr_ref[@]} -eq 0 ]]
}

# Clear all elements from associative array
# Usage: aa_clear array_name
aa_clear() {
    local -n arr_ref="$1"
    local key
    
    for key in "${!arr_ref[@]}"; do
        unset "arr_ref[$key]"
    done
}

# =============================================================================
# ADVANCED OPERATIONS
# =============================================================================

# Merge two associative arrays (source into target)
# Usage: aa_merge target_array source_array [overwrite_flag]
aa_merge() {
    local -n target_ref="$1"
    local -n source_ref="$2"
    local overwrite="${3:-true}"
    local key
    
    for key in "${!source_ref[@]}"; do
        if [[ "$overwrite" == "true" ]] || ! aa_has_key target_ref "$key"; then
            target_ref["$key"]="${source_ref[$key]}"
        fi
    done
}

# Copy associative array to another array
# Usage: aa_copy source_array target_array
aa_copy() {
    local -n source_ref="$1"
    local -n target_ref="$2"
    local key
    
    # Clear target array first
    aa_clear target_ref
    
    # Copy all elements
    for key in "${!source_ref[@]}"; do
        target_ref["$key"]="${source_ref[$key]}"
    done
}

# Filter associative array by key pattern
# Usage: aa_filter_keys array_name pattern target_array
aa_filter_keys() {
    local -n source_ref="$1"
    local pattern="$2"
    local -n target_ref="$3"
    local key
    
    # Clear target array
    aa_clear target_ref
    
    # Copy matching keys
    for key in "${!source_ref[@]}"; do
        if [[ "$key" =~ $pattern ]]; then
            target_ref["$key"]="${source_ref[$key]}"
        fi
    done
}

# Filter associative array by value pattern
# Usage: aa_filter_values array_name pattern target_array
aa_filter_values() {
    local -n source_ref="$1"
    local pattern="$2"
    local -n target_ref="$3"
    local key
    
    # Clear target array
    aa_clear target_ref
    
    # Copy matching values
    for key in "${!source_ref[@]}"; do
        if [[ "${source_ref[$key]}" =~ $pattern ]]; then
            target_ref["$key"]="${source_ref[$key]}"
        fi
    done
}

# Transform values in associative array using function
# Usage: aa_transform array_name transform_function
aa_transform() {
    local -n arr_ref="$1"
    local transform_func="$2"
    local key value
    
    for key in "${!arr_ref[@]}"; do
        value="${arr_ref[$key]}"
        arr_ref["$key"]="$($transform_func "$value")"
    done
}

# =============================================================================
# SERIALIZATION AND PERSISTENCE
# =============================================================================

# Serialize associative array to JSON
# Usage: aa_to_json array_name [pretty_flag]
aa_to_json() {
    local -n arr_ref="$1"
    local pretty="${2:-false}"
    local key value
    local first=true
    local json="{"
    
    for key in "${!arr_ref[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        
        if [[ "$pretty" == "true" ]]; then
            json+="\n  "
        fi
        
        # Escape key and value for JSON
        key=$(printf '%s' "$key" | sed 's/\\/\\\\/g; s/"/\\"/g')
        value=$(printf '%s' "${arr_ref[$key]}" | sed 's/\\/\\\\/g; s/"/\\"/g')
        
        json+="\"$key\": \"$value\""
    done
    
    if [[ "$pretty" == "true" && "$first" == "false" ]]; then
        json+="\n"
    fi
    
    json+="}"
    echo "$json"
}

# Load associative array from JSON string
# Usage: aa_from_json array_name json_string
aa_from_json() {
    local -n arr_ref="$1"
    local json_string="$2"
    
    # Clear target array
    aa_clear arr_ref
    
    # Use jq if available for robust JSON parsing
    if command -v jq >/dev/null 2>&1; then
        local key value
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                key=$(echo "$line" | cut -d$'\t' -f1)
                value=$(echo "$line" | cut -d$'\t' -f2-)
                arr_ref["$key"]="$value"
            fi
        done < <(echo "$json_string" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' 2>/dev/null)
    else
        # Fallback to basic parsing (limited functionality)
        echo "Warning: jq not available, using basic JSON parsing" >&2
        return 1
    fi
}

# Save associative array to file
# Usage: aa_save array_name filename [format]
aa_save() {
    local -n arr_ref="$1"
    local filename="$2"
    local format="${3:-json}"
    
    case "$format" in
        json)
            aa_to_json arr_ref true > "$filename"
            ;;
        key_value)
            local key
            for key in "${!arr_ref[@]}"; do
                printf '%s=%s\n' "$key" "${arr_ref[$key]}"
            done > "$filename"
            ;;
        *)
            echo "Error: Unsupported format: $format" >&2
            return 1
            ;;
    esac
}

# Load associative array from file
# Usage: aa_load array_name filename [format]
aa_load() {
    local -n arr_ref="$1"
    local filename="$2"
    local format="${3:-json}"
    
    if [[ ! -f "$filename" ]]; then
        echo "Error: File not found: $filename" >&2
        return 1
    fi
    
    case "$format" in
        json)
            aa_from_json arr_ref "$(cat "$filename")"
            ;;
        key_value)
            aa_clear arr_ref
            local line key value
            while IFS='=' read -r key value; do
                if [[ -n "$key" && -n "$value" ]]; then
                    arr_ref["$key"]="$value"
                fi
            done < "$filename"
            ;;
        *)
            echo "Error: Unsupported format: $format" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# VALIDATION AND ANALYSIS
# =============================================================================

# Validate associative array structure
# Usage: aa_validate array_name validation_rules
aa_validate() {
    local -n arr_ref="$1"
    local -n rules_ref="$2"
    local key value rule
    local errors=()
    
    # Check required keys
    if aa_has_key rules_ref "required_keys"; then
        local required_keys="${rules_ref[required_keys]}"
        for key in $required_keys; do
            if ! aa_has_key arr_ref "$key"; then
                errors+=("Missing required key: $key")
            fi
        done
    fi
    
    # Check forbidden keys
    if aa_has_key rules_ref "forbidden_keys"; then
        local forbidden_keys="${rules_ref[forbidden_keys]}"
        for key in $forbidden_keys; do
            if aa_has_key arr_ref "$key"; then
                errors+=("Forbidden key present: $key")
            fi
        done
    fi
    
    # Check value patterns
    if aa_has_key rules_ref "value_patterns"; then
        local patterns="${rules_ref[value_patterns]}"
        for key in "${!arr_ref[@]}"; do
            value="${arr_ref[$key]}"
            if ! [[ "$value" =~ $patterns ]]; then
                errors+=("Invalid value for key '$key': $value")
            fi
        done
    fi
    
    # Check key patterns
    if aa_has_key rules_ref "key_patterns"; then
        local patterns="${rules_ref[key_patterns]}"
        for key in "${!arr_ref[@]}"; do
            if ! [[ "$key" =~ $patterns ]]; then
                errors+=("Invalid key format: $key")
            fi
        done
    fi
    
    # Check size limits
    if aa_has_key rules_ref "max_size"; then
        local max_size="${rules_ref[max_size]}"
        local current_size=$(aa_size arr_ref)
        if [[ $current_size -gt $max_size ]]; then
            errors+=("Array too large: $current_size > $max_size")
        fi
    fi
    
    if aa_has_key rules_ref "min_size"; then
        local min_size="${rules_ref[min_size]}"
        local current_size=$(aa_size arr_ref)
        if [[ $current_size -lt $min_size ]]; then
            errors+=("Array too small: $current_size < $min_size")
        fi
    fi
    
    # Return validation results
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    else
        return 0
    fi
}

# Get statistics about associative array
# Usage: aa_stats array_name stats_array
aa_stats() {
    local -n arr_ref="$1"
    local -n stats_ref="$2"
    local key value
    local total_key_length=0
    local total_value_length=0
    local max_key_length=0
    local max_value_length=0
    local min_key_length=999999
    local min_value_length=999999
    
    aa_clear stats_ref
    
    stats_ref["size"]=$(aa_size arr_ref)
    
    if aa_is_empty arr_ref; then
        stats_ref["avg_key_length"]=0
        stats_ref["avg_value_length"]=0
        stats_ref["max_key_length"]=0
        stats_ref["max_value_length"]=0
        stats_ref["min_key_length"]=0
        stats_ref["min_value_length"]=0
        return 0
    fi
    
    for key in "${!arr_ref[@]}"; do
        value="${arr_ref[$key]}"
        
        local key_len=${#key}
        local value_len=${#value}
        
        total_key_length=$((total_key_length + key_len))
        total_value_length=$((total_value_length + value_len))
        
        if [[ $key_len -gt $max_key_length ]]; then
            max_key_length=$key_len
        fi
        if [[ $value_len -gt $max_value_length ]]; then
            max_value_length=$value_len
        fi
        if [[ $key_len -lt $min_key_length ]]; then
            min_key_length=$key_len
        fi
        if [[ $value_len -lt $min_value_length ]]; then
            min_value_length=$value_len
        fi
    done
    
    local size=$(aa_size arr_ref)
    stats_ref["avg_key_length"]=$((total_key_length / size))
    stats_ref["avg_value_length"]=$((total_value_length / size))
    stats_ref["max_key_length"]=$max_key_length
    stats_ref["max_value_length"]=$max_value_length
    stats_ref["min_key_length"]=$min_key_length
    stats_ref["min_value_length"]=$min_value_length
    stats_ref["total_memory"]=$((total_key_length + total_value_length))
}

# =============================================================================
# DEBUGGING AND DISPLAY
# =============================================================================

# Print associative array in human-readable format
# Usage: aa_print array_name [title] [sort_flag]
aa_print() {
    local -n arr_ref="$1"
    local title="${2:-Associative Array}"
    local sort_keys="${3:-false}"
    local key
    local keys=()
    
    echo "=== $title ==="
    echo "Size: $(aa_size arr_ref)"
    
    if aa_is_empty arr_ref; then
        echo "(empty)"
        return 0
    fi
    
    # Collect keys
    for key in "${!arr_ref[@]}"; do
        keys+=("$key")
    done
    
    # Sort keys if requested
    if [[ "$sort_keys" == "true" ]]; then
        IFS=$'\n' keys=($(sort <<<"${keys[*]}"))
        unset IFS
    fi
    
    # Print key-value pairs
    for key in "${keys[@]}"; do
        printf "  %-20s: %s\n" "$key" "${arr_ref[$key]}"
    done
    echo
}

# Print associative array as a table
# Usage: aa_print_table array_name [key_header] [value_header]
aa_print_table() {
    local -n arr_ref="$1"
    local key_header="${2:-Key}"
    local value_header="${3:-Value}"
    local key
    local max_key_width=${#key_header}
    local max_value_width=${#value_header}
    
    # Calculate column widths
    for key in "${!arr_ref[@]}"; do
        if [[ ${#key} -gt $max_key_width ]]; then
            max_key_width=${#key}
        fi
        if [[ ${#arr_ref[$key]} -gt $max_value_width ]]; then
            max_value_width=${#arr_ref[$key]}
        fi
    done
    
    # Add padding
    max_key_width=$((max_key_width + 2))
    max_value_width=$((max_value_width + 2))
    
    # Print header
    printf "%-*s | %-*s\n" $max_key_width "$key_header" $max_value_width "$value_header"
    printf "%*s-|-%*s\n" $max_key_width "" $max_value_width "" | tr ' ' '-'
    
    # Print rows
    for key in "${!arr_ref[@]}"; do
        printf "%-*s | %-*s\n" $max_key_width "$key" $max_value_width "${arr_ref[$key]}"
    done
}

# Export differences between two associative arrays
# Usage: aa_diff array1 array2 diff_array
aa_diff() {
    local -n arr1_ref="$1"
    local -n arr2_ref="$2"
    local -n diff_ref="$3"
    local key
    
    aa_clear diff_ref
    
    # Check for added/changed keys
    for key in "${!arr2_ref[@]}"; do
        if ! aa_has_key arr1_ref "$key"; then
            diff_ref["$key"]="ADDED: ${arr2_ref[$key]}"
        elif [[ "${arr1_ref[$key]}" != "${arr2_ref[$key]}" ]]; then
            diff_ref["$key"]="CHANGED: ${arr1_ref[$key]} -> ${arr2_ref[$key]}"
        fi
    done
    
    # Check for removed keys
    for key in "${!arr1_ref[@]}"; do
        if ! aa_has_key arr2_ref "$key"; then
            diff_ref["$key"]="REMOVED: ${arr1_ref[$key]}"
        fi
    done
}

# =============================================================================
# SPECIALIZED OPERATIONS FOR GEUSMAKER
# =============================================================================

# Create pricing data structure for AWS instances
# Usage: aa_create_pricing_data pricing_array
aa_create_pricing_data() {
    local -n pricing_ref="$1"
    
    aa_clear pricing_ref
    
    # Initialize with common instance types and regions
    pricing_ref["g4dn.xlarge:us-east-1:spot"]="0.00"
    pricing_ref["g4dn.xlarge:us-east-1:ondemand"]="0.526"
    pricing_ref["g4dn.2xlarge:us-east-1:spot"]="0.00"
    pricing_ref["g4dn.2xlarge:us-east-1:ondemand"]="0.752"
    pricing_ref["g5.xlarge:us-east-1:spot"]="0.00"
    pricing_ref["g5.xlarge:us-east-1:ondemand"]="1.006"
    
    # Add cache metadata
    pricing_ref["_cache_timestamp"]="$(date +%s)"
    pricing_ref["_cache_ttl"]="3600"  # 1 hour
}

# Create instance capability matrix
# Usage: aa_create_capability_matrix capabilities_array
aa_create_capability_matrix() {
    local -n cap_ref="$1"
    
    aa_clear cap_ref
    
    # GPU capabilities
    cap_ref["g4dn.xlarge:gpu_memory"]="16"
    cap_ref["g4dn.xlarge:gpu_type"]="T4"
    cap_ref["g4dn.xlarge:vcpus"]="4"
    cap_ref["g4dn.xlarge:memory"]="16"
    cap_ref["g4dn.xlarge:network"]="Up to 25 Gbps"
    cap_ref["g4dn.xlarge:suitable_for"]="ml,inference,development"
    
    cap_ref["g4dn.2xlarge:gpu_memory"]="16"
    cap_ref["g4dn.2xlarge:gpu_type"]="T4"
    cap_ref["g4dn.2xlarge:vcpus"]="8"
    cap_ref["g4dn.2xlarge:memory"]="32"
    cap_ref["g4dn.2xlarge:network"]="Up to 25 Gbps"
    cap_ref["g4dn.2xlarge:suitable_for"]="ml,training,production"
    
    cap_ref["g5.xlarge:gpu_memory"]="24"
    cap_ref["g5.xlarge:gpu_type"]="A10G"
    cap_ref["g5.xlarge:vcpus"]="4"
    cap_ref["g5.xlarge:memory"]="16"
    cap_ref["g5.xlarge:network"]="Up to 10 Gbps"
    cap_ref["g5.xlarge:suitable_for"]="ml,inference,graphics"
}

# Create deployment state tracking structure
# Usage: aa_create_deployment_state state_array stack_name
aa_create_deployment_state() {
    local -n state_ref="$1"
    local stack_name="$2"
    
    aa_clear state_ref
    
    state_ref["stack_name"]="$stack_name"
    state_ref["status"]="initializing"
    state_ref["start_time"]="$(date +%s)"
    state_ref["last_update"]="$(date +%s)"
    state_ref["phase"]="validation"
    state_ref["progress"]="0"
    state_ref["total_phases"]="5"
    state_ref["current_phase_name"]="Pre-deployment validation"
    state_ref["error_count"]="0"
    state_ref["warning_count"]="0"
}

# =============================================================================
# LIBRARY INITIALIZATION AND EXPORTS
# =============================================================================

# Validate bash version on load
if [[ "${BASH_VERSINFO[0]}" -lt 5 ]] || 
   [[ "${BASH_VERSINFO[0]}" -eq 5 && "${BASH_VERSINFO[1]}" -lt 3 ]] ||
   [[ "${BASH_VERSINFO[0]}" -eq 5 && "${BASH_VERSINFO[1]}" -eq 3 && "${BASH_VERSINFO[2]}" -lt 3 ]]; then
    echo "Error: This library requires bash 5.3.3 or later" >&2
    echo "Current version: ${BASH_VERSION}" >&2
    return 1 2>/dev/null || exit 1
fi

# Export all functions
export -f aa_get aa_set aa_has_key aa_delete aa_keys aa_values aa_size aa_is_empty aa_clear
export -f aa_merge aa_copy aa_filter_keys aa_filter_values aa_transform
export -f aa_to_json aa_from_json aa_save aa_load
export -f aa_validate aa_stats
export -f aa_print aa_print_table aa_diff
export -f aa_create_pricing_data aa_create_capability_matrix aa_create_deployment_state

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "Associative arrays library loaded (v${ASSOCIATIVE_ARRAYS_VERSION})"
elif declare -f echo >/dev/null 2>&1; then
    echo "INFO: Associative arrays library loaded (v${ASSOCIATIVE_ARRAYS_VERSION})" >&2
fi