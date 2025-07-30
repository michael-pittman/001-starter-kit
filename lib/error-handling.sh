#!/usr/bin/env bash
# Compatibility wrapper for error-handling.sh
# Redirects to unified error handling system

# Source unified system
source "$(dirname "${BASH_SOURCE[0]}")/unified-error-handling.sh"

# Compatibility aliases
alias handle_error_old=handle_error

# Compatibility function for log_error
log_error() {
    log_error_internal "ERROR" "$@"
}
export -f log_error

# Compatibility function for log_warning
log_warning() {
    log_error_internal "WARNING" "$@"
}
export -f log_warning

# Compatibility functions
error() {
    throw_error 100 "$@"
}

# Export for backward compatibility
export -f error

