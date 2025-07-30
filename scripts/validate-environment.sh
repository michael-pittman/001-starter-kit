#!/usr/bin/env bash
# =============================================================================
# Environment Validation Script for GeuseMaker
# BACKWARD COMPATIBILITY WRAPPER - Delegates to validation-suite.sh
# =============================================================================

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if new validation suite exists
VALIDATION_SUITE="$PROJECT_ROOT/lib/modules/validation/validation-suite.sh"

if [[ -f "$VALIDATION_SUITE" ]]; then
    # Use new validation suite
    echo "Note: Using new consolidated validation suite" >&2
    exec "$VALIDATION_SUITE" --type environment "$@"
else
    # Fallback to original implementation
    echo "Warning: Validation suite not found, using legacy implementation" >&2
    
    # Initialize library loader
    SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

    # Source the errors module
    if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
        source "$LIB_DIR_TEMP/modules/core/errors.sh"
    else
        # Fallback warning if errors module not found
        echo "WARNING: Could not load errors module" >&2
    fi

    # Get project root first
    readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Source the library loader
    if [[ -f "$PROJECT_ROOT/lib/utils/library-loader.sh" ]]; then
        source "$PROJECT_ROOT/lib/utils/library-loader.sh"
    else
        echo "ERROR: Cannot find lib-loader.sh in $PROJECT_ROOT/lib/" >&2
        exit 1
    fi

    # Enable error handling
    set -euo pipefail
fi

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="validate-environment"
readonly SCRIPT_VERSION="1.0.0"
readonly VALIDATION_LOG="/var/log/geuse-validation.log"

# Detect development environment
detect_dev_environment() {
    # Check if running on a development machine
    if [ "${ENVIRONMENT:-}" = "development" ] || 
       [ "${ENVIRONMENT:-}" = "dev" ] || 
       [ -f "$PROJECT_ROOT/.dev" ] || 
       [ "${USER:-}" != "root" ] || 
       [ -n "${CODESPACES:-}" ] || 
       [ -n "${GITPOD_WORKSPACE_ID:-}" ]; then
        echo "true"
    else
        echo "false"
    fi
}

readonly IS_DEVELOPMENT="$(detect_dev_environment)"

# Memory requirements - relaxed for development
if [ "$IS_DEVELOPMENT" = "true" ]; then
    readonly MIN_MEMORY_MB=512
    readonly MIN_DISK_GB=5
    readonly NETWORK_CHECK_REQUIRED="false"
    readonly MIN_PASSWORD_LENGTH=6
    readonly MIN_ENCRYPTION_KEY_LENGTH=16
else
    readonly MIN_MEMORY_MB=2048
    readonly MIN_DISK_GB=20
    readonly NETWORK_CHECK_REQUIRED="true"
    readonly MIN_PASSWORD_LENGTH=8
    readonly MIN_ENCRYPTION_KEY_LENGTH=32
fi

# Required critical variables
readonly CRITICAL_VARIABLES="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET"

# Required optional variables with defaults
readonly OPTIONAL_VARIABLES="POSTGRES_DB POSTGRES_USER AWS_REGION ENVIRONMENT STACK_NAME"

# Required service variables
readonly SERVICE_VARIABLES="WEBHOOK_URL ENABLE_METRICS LOG_LEVEL COMPOSE_FILE"

# =============================================================================
# LOGGING SYSTEM
# =============================================================================

log() {
    local level="INFO"
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$VALIDATION_LOG"
}

error() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [ERROR] $message" | tee -a "$VALIDATION_LOG" >&2
}

success() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [SUCCESS] $message" | tee -a "$VALIDATION_LOG"
}

warning() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [WARNING] $message" | tee -a "$VALIDATION_LOG"
}

# =============================================================================
# VARIABLE VALIDATION FUNCTIONS
# =============================================================================

# Validate that a variable is set and not empty
validate_variable_set() {
    local var_name="$1"
    local var_value
    eval "var_value=\${$var_name:-}"
    
    if [ -z "$var_value" ]; then
        error "Variable $var_name is not set or empty"
        return 1
    else
        log "✓ $var_name is set (${#var_value} characters)"
        return 0
    fi
}

# Validate critical variables with security checks
validate_critical_variables() {
    log "Validating critical variables..."
    if [ "$IS_DEVELOPMENT" = "true" ]; then
        log "Running in development mode - relaxed validation"
    fi
    
    local validation_passed=true
    
    for var in $CRITICAL_VARIABLES; do
        local value
        eval "value=\${$var:-}"
        
        if [ -z "$value" ]; then
            if [ "$IS_DEVELOPMENT" = "true" ]; then
                warning "Critical variable $var is not set (development mode)"
                # Set a development default
                case "$var" in
                    POSTGRES_PASSWORD)
                        export POSTGRES_PASSWORD="dev-password-123"
                        warning "Using development default for POSTGRES_PASSWORD"
                        ;;
                    N8N_ENCRYPTION_KEY)
                        export N8N_ENCRYPTION_KEY="dev-encryption-key-1234567890123456"
                        warning "Using development default for N8N_ENCRYPTION_KEY"
                        ;;
                    N8N_USER_MANAGEMENT_JWT_SECRET)
                        export N8N_USER_MANAGEMENT_JWT_SECRET="dev-jwt-secret-1234567890"
                        warning "Using development default for N8N_USER_MANAGEMENT_JWT_SECRET"
                        ;;
                esac
                eval "value=\${$var:-}"
            else
                error "Critical variable $var is not set"
                validation_passed=false
                continue
            fi
        fi
        
        # Check minimum length
        if [ ${#value} -lt $MIN_PASSWORD_LENGTH ]; then
            if [ "$IS_DEVELOPMENT" = "true" ]; then
                warning "Variable $var is short (${#value} chars, recommended $MIN_PASSWORD_LENGTH)"
            else
                error "Critical variable $var is too short (${#value} chars, minimum $MIN_PASSWORD_LENGTH)"
                validation_passed=false
                continue
            fi
        fi
        
        # Check for common insecure values (warning only in dev)
        case "$var" in
            POSTGRES_PASSWORD)
                case "$value" in
                    password|postgres|admin|root|test|dev-password*)
                        if [ "$IS_DEVELOPMENT" = "true" ]; then
                            warning "POSTGRES_PASSWORD uses a common/development value (OK for dev)"
                        else
                            error "POSTGRES_PASSWORD uses a common insecure value"
                            validation_passed=false
                            continue
                        fi
                        ;;
                esac
                ;;
            N8N_ENCRYPTION_KEY)
                if [ ${#value} -lt $MIN_ENCRYPTION_KEY_LENGTH ]; then
                    if [ "$IS_DEVELOPMENT" = "true" ]; then
                        warning "N8N_ENCRYPTION_KEY is short for security (${#value} chars, recommended $MIN_ENCRYPTION_KEY_LENGTH)"
                    else
                        error "N8N_ENCRYPTION_KEY is too short for security (${#value} chars, minimum $MIN_ENCRYPTION_KEY_LENGTH)"
                        validation_passed=false
                        continue
                    fi
                fi
                ;;
        esac
        
        success "✓ $var is valid (${#value} characters)"
    done
    
    if [ "$validation_passed" = "true" ]; then
        success "All critical variables are valid"
        return 0
    else
        if [ "$IS_DEVELOPMENT" = "true" ]; then
            warning "Some validation checks failed but continuing in development mode"
            return 0
        else
            error "Critical variable validation failed"
            return 1
        fi
    fi
}

# =============================================================================
# SYSTEM VALIDATION FUNCTIONS
# =============================================================================

# Check system resources
validate_system_resources() {
    log "Validating system resources..."
    
    # Check available memory
    local available_memory_mb
    if command -v free >/dev/null 2>&1; then
        available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    elif [ -f /proc/meminfo ]; then
        available_memory_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    else
        warning "Cannot determine available memory"
        return 0
    fi
    
    if [ -n "$available_memory_mb" ] && [ "$available_memory_mb" -lt "$MIN_MEMORY_MB" ]; then
        if [ "$IS_DEVELOPMENT" = "true" ]; then
            warning "Low memory: ${available_memory_mb}MB available (recommended ${MIN_MEMORY_MB}MB for dev)"
        else
            error "Insufficient memory: ${available_memory_mb}MB available (minimum ${MIN_MEMORY_MB}MB)"
            return 1
        fi
    else
        success "✓ Memory check passed: ${available_memory_mb}MB available"
    fi
    
    # Check disk space
    local available_disk_gb
    available_disk_gb=$(df -BG . | awk 'NR==2{print int($4)}')
    
    if [ -n "$available_disk_gb" ] && [ "$available_disk_gb" -lt "$MIN_DISK_GB" ]; then
        if [ "$IS_DEVELOPMENT" = "true" ]; then
            warning "Low disk space: ${available_disk_gb}GB available (recommended ${MIN_DISK_GB}GB for dev)"
        else
            error "Insufficient disk space: ${available_disk_gb}GB available (minimum ${MIN_DISK_GB}GB)"
            return 1
        fi
    else
        success "✓ Disk space check passed: ${available_disk_gb}GB available"
    fi
    
    return 0
}

# Check network connectivity (optional for development)
validate_network_connectivity() {
    if [ "$NETWORK_CHECK_REQUIRED" = "false" ]; then
        log "Skipping network checks in development mode"
        return 0
    fi
    
    log "Validating network connectivity..."
    
    # Check DNS resolution
    if ! nslookup google.com >/dev/null 2>&1 && ! host google.com >/dev/null 2>&1; then
        warning "DNS resolution may have issues"
    else
        success "✓ DNS resolution working"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        warning "Internet connectivity may have issues"
    else
        success "✓ Internet connectivity confirmed"
    fi
    
    return 0
}

# =============================================================================
# MAIN VALIDATION FUNCTION
# =============================================================================

run_validation() {
    local validation_mode="${1:-full}"
    local exit_on_error="${2:-true}"
    
    log "Starting environment validation (mode: $validation_mode)..."
    if [ "$IS_DEVELOPMENT" = "true" ]; then
        log "🔧 Running in DEVELOPMENT mode - validation requirements relaxed"
    else
        log "🚀 Running in PRODUCTION mode - strict validation enforced"
    fi
    
    local validation_errors=0
    
    # Load variable management library
    if [ -f "$PROJECT_ROOT/lib/utils/library-loader.sh" ]; then
        log "Loading variable management library..."
        source "$PROJECT_ROOT/lib/utils/library-loader.sh"
        load_module "variable-management"
        
        # Initialize variables if not already done
        if command -v init_all_variables >/dev/null 2>&1; then
            log "Initializing variables..."
            if ! init_all_variables; then
                warning "Variable initialization had issues"
                validation_errors=$((validation_errors + 1))
            fi
        fi
    else
        error "Variable management library not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Run validation checks
    case "$validation_mode" in
        variables)
            log "Running variables-only validation..."
            
            if ! validate_critical_variables; then
                validation_errors=$((validation_errors + 1))
            fi
            ;;
            
        system)
            log "Running system validation..."
            
            if ! validate_system_resources; then
                validation_errors=$((validation_errors + 1))
            fi
            
            if ! validate_network_connectivity; then
                if [ "$IS_DEVELOPMENT" = "true" ]; then
                    warning "Network validation had issues (non-blocking in dev mode)"
                else
                    validation_errors=$((validation_errors + 1))
                fi
            fi
            ;;
            
        full)
            log "Running full validation..."
            
            if ! validate_critical_variables; then
                validation_errors=$((validation_errors + 1))
            fi
            
            if ! validate_system_resources; then
                validation_errors=$((validation_errors + 1))
            fi
            
            if ! validate_network_connectivity; then
                if [ "$IS_DEVELOPMENT" = "true" ]; then
                    warning "Network validation had issues (non-blocking in dev mode)"
                else
                    validation_errors=$((validation_errors + 1))
                fi
            fi
            ;;
            
        *)
            error "Unknown validation mode: $validation_mode"
            validation_errors=$((validation_errors + 1))
            ;;
    esac
    
    # Report results
    if [ $validation_errors -eq 0 ]; then
        success "🎉 All validation checks passed!"
        return 0
    else
        if [ "$IS_DEVELOPMENT" = "true" ]; then
            warning "⚠️  Validation had $validation_errors issues in development mode"
            log "Development mode allows continuing with warnings"
            return 0
        else
            error "❌ Validation failed with $validation_errors errors"
            if [ "$exit_on_error" = "true" ]; then
                exit 1
            else
                return 1
            fi
        fi
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Ensure log directory exists
mkdir -p "$(dirname "$VALIDATION_LOG")"

log "Starting GeuseMaker environment validation..."
log "Script: $SCRIPT_NAME v$SCRIPT_VERSION"

# Parse command line arguments
validation_mode="${1:-full}"
exit_on_error="${2:-false}"

# Show usage if requested
if [ "$validation_mode" = "--help" ] || [ "$validation_mode" = "-h" ]; then
    cat <<EOF
Usage: $0 [mode] [exit_on_error]

Modes:
  variables - Validate environment variables only
  system    - Validate system resources only
  full      - Run all validations (default)

Options:
  exit_on_error - true|false (default: false)

Development Mode:
  Set ENVIRONMENT=development or create .dev file in project root
  This relaxes validation requirements for local development

Examples:
  $0                    # Run full validation
  $0 variables          # Check variables only
  $0 system true        # Check system and exit on error
  ENVIRONMENT=dev $0    # Run in development mode
EOF
    exit 0
fi

# Run validation
run_validation "$validation_mode" "$exit_on_error"