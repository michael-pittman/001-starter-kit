#!/usr/bin/env bash
# ==============================================================================
# Module: [MODULE_NAME]
# Description: [Brief description of what this module provides]
# 
# Functions:
#   - [function_name]()     [Brief description]
#   - [function_name]()     [Brief description]
#
# Dependencies:
#   - [module_name]         [Why it's needed]
#
# Usage:
#   source "path/to/module.sh"
#   function_name "argument"
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__MODULE_NAME_LOADED:-}" ]] && return 0
readonly __MODULE_NAME_LOADED=1

# ==============================================================================
# DEPENDENCIES
# ==============================================================================
# Load required modules
if [[ -n "${LIB_DIR:-}" ]]; then
    source "$LIB_DIR/modules/core/logging.sh" || return 1
    source "$LIB_DIR/modules/core/validation.sh" || return 1
fi

# ==============================================================================
# CONSTANTS
# ==============================================================================
# Module-specific constants
readonly MODULE_CONSTANT="value"
readonly MODULE_VERSION="1.0.0"

# ==============================================================================
# PRIVATE FUNCTIONS (prefix with _)
# ==============================================================================

# Private helper function
# Arguments:
#   $1 - Parameter description
# Returns:
#   0 - Success
#   1 - Error
_module_private_helper() {
    local param="${1:-}"
    
    # Validation
    if [[ -z "$param" ]]; then
        log_error "[MODULE] Missing required parameter"
        return 1
    fi
    
    # Implementation
    log_debug "[MODULE] Processing: $param"
    
    return 0
}

# ==============================================================================
# PUBLIC FUNCTIONS
# ==============================================================================

# Main module function
# Arguments:
#   $1 - Required parameter
#   $2 - Optional parameter (default: "default_value")
# Returns:
#   0 - Success
#   1 - Validation error
#   2 - Processing error
# Output:
#   Processed result to stdout
module_main_function() {
    local required_param="${1:-}"
    local optional_param="${2:-default_value}"
    
    # Input validation
    if [[ -z "$required_param" ]]; then
        log_error "[MODULE] Missing required parameter"
        return 1
    fi
    
    # Validate using validation module
    if ! validate_not_empty "required_param" "$required_param"; then
        return 1
    fi
    
    # Process using private helper
    if ! _module_private_helper "$required_param"; then
        log_error "[MODULE] Failed to process parameter"
        return 2
    fi
    
    # Return result
    echo "Processed: $required_param with $optional_param"
    return 0
}

# Another public function
# Arguments:
#   $1 - Input file path
# Returns:
#   0 - Success
#   1 - File not found
#   2 - Processing error
# Global Variables Modified:
#   MODULE_LAST_RESULT - Stores the last processing result
module_process_file() {
    local file_path="${1:-}"
    
    # Validate file exists
    if [[ ! -f "$file_path" ]]; then
        log_error "[MODULE] File not found: $file_path"
        return 1
    fi
    
    # Process file
    log_info "[MODULE] Processing file: $file_path"
    
    # Store result in global variable (if needed)
    MODULE_LAST_RESULT="processed"
    
    return 0
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================
# Perform any module initialization here
log_debug "[MODULE] Module loaded successfully"