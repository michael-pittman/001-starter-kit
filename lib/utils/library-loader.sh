#!/usr/bin/env bash

# Library Loader Template for GeuseMaker
# Provides standardized module loading with proper error handling and path resolution
# Usage: source this file at the beginning of your script
# Compatible with bash 3.x+ (Universal compatibility)

set -euo pipefail

# Global variables for library loading
LIBRARY_LOADER_VERSION="1.0.0"
LIBRARY_LOADER_LOADED=true

# Use portable arrays for all bash versions
LOADED_MODULES=()
MODULE_LOAD_TIMES=()
LIBRARY_LOAD_ERRORS=()

# Determine script location and project root
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: library-loader.sh must be sourced, not executed directly" >&2
    exit 1
fi

# Robust path resolution that works from any location
resolve_script_dir() {
    local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local dir
    
    # Handle symlinks
    while [[ -L "$source" ]]; do
        dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    echo "$dir"
}

# Find project root by looking for marker files
find_project_root() {
    local current_dir="$1"
    local marker_files=("CLAUDE.md" "Makefile" ".git")
    
    while [[ "$current_dir" != "/" ]]; do
        for marker in "${marker_files[@]}"; do
            if [[ -e "$current_dir/$marker" ]]; then
                echo "$current_dir"
                return 0
            fi
        done
        current_dir="$(dirname "$current_dir")"
    done
    
    # Fallback: assume we're somewhere under the project
    echo "$(cd "$1/../.." && pwd)"
}

# Initialize paths
SCRIPT_DIR="$(resolve_script_dir)"
PROJECT_ROOT="$(find_project_root "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"
MODULES_DIR="$LIB_DIR/modules"

# Export for child scripts
export PROJECT_ROOT LIB_DIR MODULES_DIR

# Portable array functions for all bash versions
array_contains() {
    local array_name="$1"
    local value="$2"
    local array_ref
    
    # Use eval to access array dynamically with proper error handling
    if eval "[[ \${$array_name[@]+isset} ]]"; then
        eval "array_ref=(\"\${$array_name[@]}\")"
    else
        # Array doesn't exist, return false
        return 1
    fi
    
    local item
    for item in "${array_ref[@]}"; do
        if [[ "$item" == "$value" ]]; then
            return 0
        fi
    done
    return 1
}

array_set() {
    local array_name="$1"
    local key="$2"
    local value="$3"
    
    # For bash 3.x compatibility, we'll use a simple array with key=value format
    # This is a simplified approach - in practice, you might want to use separate arrays
    eval "$array_name+=(\"$key=$value\")"
}

array_get() {
    local array_name="$1"
    local key="$2"
    local array_ref
    
    # Check if array exists before accessing
    if eval "[[ \${$array_name[@]+isset} ]]"; then
        eval "array_ref=(\"\${$array_name[@]}\")"
    else
        return 1
    fi
    
    local item
    for item in "${array_ref[@]}"; do
        if [[ "$item" =~ ^"$key=" ]]; then
            echo "${item#*=}"
            return 0
        fi
    done
    return 1
}

# Enhanced source with error handling and tracking
safe_source() {
    local file="$1"
    local required="${2:-true}"
    local description="${3:-}"
    local start_time=$(date +%s.%N)
    
    # Check if already loaded using portable method
    if array_contains "LOADED_MODULES" "$file"; then
        return 0
    fi
    
    # Resolve relative paths
    if [[ ! "$file" =~ ^/ ]]; then
        # Try multiple base paths
        local bases=("$LIB_DIR" "$MODULES_DIR" "$PROJECT_ROOT" "$SCRIPT_DIR")
        local found=false
        
        for base in "${bases[@]}"; do
            if [[ -f "$base/$file" ]]; then
                file="$base/$file"
                found=true
                break
            fi
        done
        
        if [[ "$found" != "true" && -f "$file" ]]; then
            file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
        fi
    fi
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        local error_msg="Library not found: $file"
        [[ -n "$description" ]] && error_msg="$description library not found: $file"
        
        if [[ "$required" == "true" ]]; then
            echo "Error: $error_msg" >&2
            LIBRARY_LOAD_ERRORS+=("$error_msg")
            return 1
        else
            echo "Warning: $error_msg (optional, continuing)" >&2
            return 0
        fi
    fi
    
    # Source the file with error handling
    if source "$file"; then
        LOADED_MODULES+=("$file")
        local end_time=$(date +%s.%N)
        if command -v bc >/dev/null 2>&1; then
            local load_time=$(echo "$end_time - $start_time" | bc)
            array_set "MODULE_LOAD_TIMES" "$file" "$load_time"
        fi
        [[ -n "$description" ]] && echo "Loaded: $description"
        return 0
    else
        local error_msg="Failed to load: $file"
        [[ -n "$description" ]] && error_msg="Failed to load $description: $file"
        echo "Error: $error_msg" >&2
        LIBRARY_LOAD_ERRORS+=("$error_msg")
        return 1
    fi
}

# Load module with dependency resolution
load_module() {
    local module_name="$1"
    local module_path="modules/$module_name"
    
    # Check for .sh extension
    [[ ! "$module_path" =~ \.sh$ ]] && module_path="${module_path}.sh"
    
    safe_source "$module_path" true "Module $module_name"
}

# Batch load modules
load_modules() {
    local modules=("$@")
    local failed=0
    
    for module in "${modules[@]}"; do
        if ! load_module "$module"; then
            ((failed++))
        fi
    done
    
    return $failed
}

# Initialize script with required modules
initialize_script() {
    local script_name="$1"
    shift
    local modules=("$@")
    
    echo "Initializing $script_name with ${#modules[@]} modules..."
    
    # Load standard libraries first
    if ! load_standard_libraries; then
        echo "Error: Failed to load standard libraries" >&2
        return 1
    fi
    
    # Load required modules
    local failed=0
    for module in "${modules[@]}"; do
        if ! load_module "$module"; then
            echo "Error: Failed to load module $module" >&2
            ((failed++))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        echo "Error: Failed to load $failed modules" >&2
        return 1
    fi
    
    echo "Successfully initialized $script_name"
    return 0
}

# Load libraries (backward compatibility function)
load_libraries() {
    local libraries=("$@")
    local failed=0
    
    for library in "${libraries[@]}"; do
        if ! safe_source "$library" true "$library"; then
            ((failed++))
        fi
    done
    
    return $failed
}

# Standard library loading order
load_standard_libraries() {
    local libraries=(
        "aws-deployment-common.sh:Core logging and prerequisites"
        "error-handling.sh:Error handling and cleanup"
        "associative-arrays.sh:Enhanced data structures:optional"
        "aws-config.sh:AWS configuration management"
        "aws-cli-v2.sh:AWS CLI v2 compatibility"
    )
    
    local failed=0
    for library_spec in "${libraries[@]}"; do
        local file="${library_spec%%:*}"
        local description="${library_spec#*:}"
        local required="true"
        
        # Check if optional
        if [[ "$description" =~ :optional$ ]]; then
            description="${description%:optional}"
            required="false"
        fi
        
        if ! safe_source "$file" "$required" "$description"; then
            ((failed++))
        fi
    done
    
    return $failed
}

# Get loaded modules
get_loaded_modules() {
    printf '%s\n' "${LOADED_MODULES[@]}"
}

# Get module load times
get_module_load_times() {
    local module
    for module in "${LOADED_MODULES[@]}"; do
        local load_time
        if load_time=$(array_get "MODULE_LOAD_TIMES" "$module"); then
            echo "$module: ${load_time}s"
        else
            echo "$module: <unknown>"
        fi
    done
}

# Get load errors
get_load_errors() {
    if [[ ${#LIBRARY_LOAD_ERRORS[@]} -eq 0 ]]; then
        echo "No load errors"
        return 0
    fi
    
    printf 'Error: %s\n' "${LIBRARY_LOAD_ERRORS[@]}"
    return 1
}

# Library loader status
library_loader_status() {
    echo "Library Loader Status:"
    echo "  Version: $LIBRARY_LOADER_VERSION"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  Library Directory: $LIB_DIR"
    echo "  Modules Directory: $MODULES_DIR"
    echo "  Loaded Modules: ${#LOADED_MODULES[@]}"
    echo "  Load Errors: ${#LIBRARY_LOAD_ERRORS[@]}"
    
    if [[ ${#LIBRARY_LOAD_ERRORS[@]} -gt 0 ]]; then
        echo "  Errors:"
        get_load_errors
    fi
}

# Export functions for use in other scripts
export -f safe_source load_module load_modules load_libraries
export -f load_standard_libraries get_loaded_modules get_module_load_times
export -f get_load_errors library_loader_status
export -f array_contains array_set array_get
export -f initialize_script

# Auto-load standard libraries if not already loaded
if [[ ${#LOADED_MODULES[@]} -eq 0 ]]; then
    load_standard_libraries
fi