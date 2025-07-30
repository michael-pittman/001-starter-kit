#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Security Utilities Module
# Provides secure password generation and cryptographic functions
# =============================================================================

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh" || {
    echo "ERROR: Failed to source logging module" >&2
    exit 1
}

# Secure password generation with no predictable fallbacks
generate_secure_password() {
    local length="${1:-32}"
    local password
    
    # Try multiple methods, fail if none work
    if command -v openssl >/dev/null 2>&1; then
        password=$(openssl rand -base64 "$length" 2>/dev/null)
    elif command -v pwgen >/dev/null 2>&1; then
        password=$(pwgen -s "$length" 1 2>/dev/null)
    elif [ -r /dev/urandom ]; then
        password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+=' < /dev/urandom | head -c "$length")
    else
        log_error "No secure password generation method available"
        return 1
    fi
    
    if [[ -z "$password" ]]; then
        log_error "Failed to generate secure password"
        return 1
    fi
    
    echo "$password"
}

# Generate hexadecimal key (for encryption keys)
generate_secure_hex_key() {
    local length="${1:-32}"
    local key
    
    if command -v openssl >/dev/null 2>&1; then
        key=$(openssl rand -hex "$length" 2>/dev/null)
    elif [ -r /dev/urandom ]; then
        key=$(tr -dc 'a-f0-9' < /dev/urandom | head -c "$((length * 2))")
    else
        log_error "No secure hex key generation method available"
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "Failed to generate secure hex key"
        return 1
    fi
    
    echo "$key"
}

# Validate password strength
validate_password_strength() {
    local password="$1"
    local min_length="${2:-16}"
    
    # Check length
    if [[ ${#password} -lt $min_length ]]; then
        return 1
    fi
    
    # Check complexity (at least 3 of: uppercase, lowercase, numbers, special chars)
    local complexity=0
    [[ "$password" =~ [A-Z] ]] && ((complexity++))
    [[ "$password" =~ [a-z] ]] && ((complexity++))
    [[ "$password" =~ [0-9] ]] && ((complexity++))
    [[ "$password" =~ [^A-Za-z0-9] ]] && ((complexity++))
    
    [[ $complexity -ge 3 ]]
}

# Generate secure random string
generate_secure_random_string() {
    local length="${1:-32}"
    local charset="${2:-A-Za-z0-9}"
    local random_string
    
    if [ -r /dev/urandom ]; then
        random_string=$(tr -dc "$charset" < /dev/urandom | head -c "$length")
    elif command -v openssl >/dev/null 2>&1; then
        # Use openssl as fallback
        local raw_random
        raw_random=$(openssl rand -base64 "$((length * 2))" 2>/dev/null)
        random_string=$(echo "$raw_random" | tr -dc "$charset" | head -c "$length")
    else
        log_error "No secure random generation method available"
        return 1
    fi
    
    if [[ -z "$random_string" || ${#random_string} -lt $length ]]; then
        log_error "Failed to generate secure random string of required length"
        return 1
    fi
    
    echo "$random_string"
}

# Export functions
export -f generate_secure_password
export -f generate_secure_hex_key
export -f validate_password_strength
export -f generate_secure_random_string