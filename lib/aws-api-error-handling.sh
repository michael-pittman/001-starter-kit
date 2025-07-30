#!/usr/bin/env bash
# Compatibility wrapper for error-handling.sh
# Redirects to unified error handling system

# Source unified system
source "$(dirname "${BASH_SOURCE[0]}")/unified-error-handling.sh"

# Compatibility aliases
alias handle_error_old=handle_error
alias log_error=log_error_internal

# Compatibility functions
error() {
    throw_error 100 "$@"
}

# Export for backward compatibility
export -f error

