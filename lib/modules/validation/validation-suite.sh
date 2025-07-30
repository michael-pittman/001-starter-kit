#!/usr/bin/env bash
# =============================================================================
# Validation Suite - Consolidated validation framework
# Supports: dependencies, environment, modules, network
# Features: parallel processing, caching, retry mechanisms, structured logging
# =============================================================================

set -euo pipefail

# Initialize script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$(cd "$MODULE_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$LIB_DIR/.." && pwd)"

# Handle benchmark mode
if [[ "${BENCHMARK_MODE:-0}" == "1" ]]; then
    # Disable caching and verbose output for benchmarking
    export VALIDATION_CACHE_TTL=0
    export VALIDATION_MAX_PARALLEL=1
    exec >/dev/null 2>&1
fi

# Source required libraries
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Load required modules
load_module "core/errors"
load_module "core/variables"
load_module "core/logging"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly VALIDATION_VERSION="2.0.0"
readonly CACHE_DIR="${VALIDATION_CACHE_DIR:-$PROJECT_ROOT/.cache/validation}"
readonly CACHE_TTL="${VALIDATION_CACHE_TTL:-3600}"  # 1 hour default
readonly MAX_RETRIES="${VALIDATION_MAX_RETRIES:-3}"
readonly RETRY_DELAY="${VALIDATION_RETRY_DELAY:-2}"
readonly LOG_FILE="${VALIDATION_LOG_FILE:-/tmp/validation-suite.log}"

# Validation types
readonly VALID_TYPES="dependencies environment modules network"

# Parallel processing settings
readonly MAX_PARALLEL_JOBS="${VALIDATION_MAX_PARALLEL:-4}"

# State tracking
declare -gA VALIDATION_RESULTS
declare -gA VALIDATION_CACHE
declare -gA VALIDATION_METRICS
declare -g VALIDATION_TYPE=""
declare -g PARALLEL_MODE="false"
declare -g CACHE_ENABLED="false"
declare -g RETRY_ENABLED="false"
declare -g VERBOSE_MODE="false"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Validation Suite v$VALIDATION_VERSION initialized" >> "$LOG_FILE"
}

log_structured() {
    local level="$1"
    local component="$2"
    local message="$3"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_entry
    
    # Structured JSON log format
    log_entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg lvl "$level" \
        --arg comp "$component" \
        --arg msg "$message" \
        --arg type "$VALIDATION_TYPE" \
        '{timestamp: $ts, level: $lvl, component: $comp, message: $msg, validation_type: $type}')
    
    echo "$log_entry" >> "$LOG_FILE"
    
    # Also output to console based on level
    case "$level" in
        ERROR)
            echo -e "\033[0;31m[$timestamp] [$component] ERROR: $message\033[0m" >&2
            ;;
        WARN)
            echo -e "\033[0;33m[$timestamp] [$component] WARN: $message\033[0m"
            ;;
        INFO)
            [[ "$VERBOSE_MODE" == "true" ]] && echo "[$timestamp] [$component] INFO: $message"
            ;;
        DEBUG)
            [[ "$VERBOSE_MODE" == "true" ]] && echo "[$timestamp] [$component] DEBUG: $message"
            ;;
        SUCCESS)
            echo -e "\033[0;32m[$timestamp] [$component] ✓ $message\033[0m"
            ;;
    esac
}

# =============================================================================
# CACHE FUNCTIONS
# =============================================================================

init_cache() {
    if [[ "$CACHE_ENABLED" == "true" ]]; then
        mkdir -p "$CACHE_DIR"
        log_structured "INFO" "cache" "Cache initialized at $CACHE_DIR"
    fi
}

get_cache_key() {
    local validation_type="$1"
    local context="${2:-default}"
    echo "${validation_type}_${context}_$(date +%Y%m%d)"
}

is_cache_valid() {
    local cache_file="$1"
    
    [[ ! -f "$cache_file" ]] && return 1
    
    local file_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)))
    [[ $file_age -lt $CACHE_TTL ]]
}

get_from_cache() {
    local cache_key="$1"
    local cache_file="$CACHE_DIR/$cache_key.json"
    
    if [[ "$CACHE_ENABLED" == "true" ]] && is_cache_valid "$cache_file"; then
        log_structured "DEBUG" "cache" "Cache hit for $cache_key"
        cat "$cache_file"
        return 0
    fi
    
    return 1
}

save_to_cache() {
    local cache_key="$1"
    local data="$2"
    local cache_file="$CACHE_DIR/$cache_key.json"
    
    if [[ "$CACHE_ENABLED" == "true" ]]; then
        echo "$data" > "$cache_file"
        log_structured "DEBUG" "cache" "Saved to cache: $cache_key"
    fi
}

# =============================================================================
# RETRY MECHANISM
# =============================================================================

with_retry() {
    local func="$1"
    local component="$2"
    shift 2
    
    local attempt=1
    local delay=$RETRY_DELAY
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_structured "DEBUG" "retry" "Attempt $attempt/$MAX_RETRIES for $component"
        
        if $func "$@"; then
            return 0
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_structured "WARN" "retry" "$component failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_structured "ERROR" "retry" "$component failed after $MAX_RETRIES attempts"
    return 1
}

# =============================================================================
# DEPENDENCY VALIDATION
# =============================================================================

validate_dependencies() {
    log_structured "INFO" "dependencies" "Starting dependency validation"
    
    # Check cache first
    local cache_key=$(get_cache_key "dependencies")
    if result=$(get_from_cache "$cache_key"); then
        echo "$result"
        return 0
    fi
    
    # Load deployment validation module for check_dependencies
    load_module "deployment-validation"
    
    local result
    local exit_code=0
    
    # Run dependency check
    if output=$(check_dependencies 2>&1); then
        result=$(jq -n \
            --arg status "passed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "SUCCESS" "dependencies" "All dependencies validated"
    else
        exit_code=$?
        result=$(jq -n \
            --arg status "failed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "ERROR" "dependencies" "Dependency validation failed"
    fi
    
    # Save to cache
    save_to_cache "$cache_key" "$result"
    
    echo "$result"
    return $exit_code
}

# =============================================================================
# ENVIRONMENT VALIDATION
# =============================================================================

validate_environment() {
    log_structured "INFO" "environment" "Starting environment validation"
    
    # Check cache first
    local cache_key=$(get_cache_key "environment")
    if result=$(get_from_cache "$cache_key"); then
        echo "$result"
        return 0
    fi
    
    local result
    local exit_code=0
    local output=""
    
    # Source validate-environment functions directly
    source "$PROJECT_ROOT/scripts/validate-environment.sh"
    
    # Run environment validation
    if output=$(run_validation "full" "false" 2>&1); then
        result=$(jq -n \
            --arg status "passed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "SUCCESS" "environment" "Environment validation passed"
    else
        exit_code=$?
        result=$(jq -n \
            --arg status "failed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "ERROR" "environment" "Environment validation failed"
    fi
    
    # Save to cache
    save_to_cache "$cache_key" "$result"
    
    echo "$result"
    return $exit_code
}

# =============================================================================
# MODULE VALIDATION
# =============================================================================

validate_modules() {
    log_structured "INFO" "modules" "Starting module validation"
    
    # Check cache first
    local cache_key=$(get_cache_key "modules")
    if result=$(get_from_cache "$cache_key"); then
        echo "$result"
        return 0
    fi
    
    local result
    local exit_code=0
    
    # Run module consolidation validation
    if output=$("$PROJECT_ROOT/scripts/validate-module-consolidation.sh" 2>&1); then
        result=$(jq -n \
            --arg status "passed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "SUCCESS" "modules" "Module validation passed"
    else
        exit_code=$?
        result=$(jq -n \
            --arg status "failed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "ERROR" "modules" "Module validation failed"
    fi
    
    # Save to cache
    save_to_cache "$cache_key" "$result"
    
    echo "$result"
    return $exit_code
}

# =============================================================================
# NETWORK VALIDATION
# =============================================================================

validate_network() {
    log_structured "INFO" "network" "Starting network validation"
    
    # Don't cache network validation as it's time-sensitive
    local result
    local exit_code=0
    
    # Load deployment validation module for network check
    load_module "deployment-validation"
    
    # Run network connectivity check
    if output=$(check_network_connectivity 2>&1); then
        result=$(jq -n \
            --arg status "passed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "SUCCESS" "network" "Network validation passed"
    else
        exit_code=$?
        result=$(jq -n \
            --arg status "failed" \
            --arg output "$output" \
            '{status: $status, output: $output, timestamp: now}')
        log_structured "ERROR" "network" "Network validation failed"
    fi
    
    echo "$result"
    return $exit_code
}

# =============================================================================
# PARALLEL PROCESSING
# =============================================================================

run_validation_job() {
    local validation_type="$1"
    local output_file="$2"
    
    log_structured "DEBUG" "parallel" "Starting job: $validation_type"
    
    local result
    case "$validation_type" in
        dependencies)
            result=$(validate_dependencies)
            ;;
        environment)
            result=$(validate_environment)
            ;;
        modules)
            result=$(validate_modules)
            ;;
        network)
            result=$(validate_network)
            ;;
    esac
    
    echo "$result" > "$output_file"
    log_structured "DEBUG" "parallel" "Completed job: $validation_type"
}

run_parallel_validations() {
    local types=("$@")
    local temp_dir=$(mktemp -d)
    local pids=()
    
    log_structured "INFO" "parallel" "Running ${#types[@]} validations in parallel"
    
    # Start background jobs
    for type in "${types[@]}"; do
        local output_file="$temp_dir/$type.json"
        run_validation_job "$type" "$output_file" &
        pids+=($!)
    done
    
    # Wait for all jobs to complete
    local failed_jobs=0
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local type=${types[$i]}
        
        if wait $pid; then
            log_structured "DEBUG" "parallel" "Job $type completed successfully"
        else
            log_structured "ERROR" "parallel" "Job $type failed"
            ((failed_jobs++))
        fi
    done
    
    # Collect results
    local combined_results="{"
    for type in "${types[@]}"; do
        local output_file="$temp_dir/$type.json"
        if [[ -f "$output_file" ]]; then
            local result=$(cat "$output_file")
            combined_results="$combined_results\"$type\":$result,"
        fi
    done
    combined_results="${combined_results%,}}"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo "$combined_results"
    
    [[ $failed_jobs -eq 0 ]] && return 0 || return 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                VALIDATION_TYPE="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_MODE="true"
                shift
                ;;
            --cache)
                CACHE_ENABLED="true"
                shift
                ;;
            --retry)
                RETRY_ENABLED="true"
                shift
                ;;
            --verbose|-v)
                VERBOSE_MODE="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_structured "ERROR" "main" "Unknown option: $1"
                show_usage
                exit 2
                ;;
        esac
    done
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") --type TYPE [OPTIONS]

Consolidated validation suite for GeuseMaker project

OPTIONS:
    --type TYPE         Validation type: dependencies|environment|modules|network|all
    --parallel          Enable parallel processing for multiple validations
    --cache             Enable caching of validation results
    --retry             Enable retry mechanisms for failed validations
    --verbose, -v       Enable verbose output
    --help, -h          Show this help message

EXAMPLES:
    # Run dependency validation
    $(basename "$0") --type dependencies

    # Run all validations in parallel with caching
    $(basename "$0") --type all --parallel --cache

    # Run network validation with retries
    $(basename "$0") --type network --retry

EXIT CODES:
    0   Validation passed
    1   Validation failed
    2   System error

EOF
}

validate_input() {
    if [[ -z "$VALIDATION_TYPE" ]]; then
        log_structured "ERROR" "main" "No validation type specified"
        show_usage
        exit 2
    fi
    
    if [[ "$VALIDATION_TYPE" != "all" ]] && ! echo "$VALID_TYPES" | grep -qw "$VALIDATION_TYPE"; then
        log_structured "ERROR" "main" "Invalid validation type: $VALIDATION_TYPE"
        show_usage
        exit 2
    fi
}

main() {
    # Initialize
    init_logging
    init_cache
    
    # Parse arguments
    parse_arguments "$@"
    validate_input
    
    log_structured "INFO" "main" "Starting validation suite v$VALIDATION_VERSION"
    log_structured "INFO" "main" "Options: type=$VALIDATION_TYPE, parallel=$PARALLEL_MODE, cache=$CACHE_ENABLED, retry=$RETRY_ENABLED"
    
    local exit_code=0
    local result
    
    # Handle validation execution
    if [[ "$VALIDATION_TYPE" == "all" ]]; then
        local all_types=($VALID_TYPES)
        
        if [[ "$PARALLEL_MODE" == "true" ]]; then
            result=$(run_parallel_validations "${all_types[@]}")
            exit_code=$?
        else
            # Run sequentially
            result="{"
            for type in "${all_types[@]}"; do
                local type_result
                case "$type" in
                    dependencies)
                        type_result=$(validate_dependencies) || exit_code=1
                        ;;
                    environment)
                        type_result=$(validate_environment) || exit_code=1
                        ;;
                    modules)
                        type_result=$(validate_modules) || exit_code=1
                        ;;
                    network)
                        type_result=$(validate_network) || exit_code=1
                        ;;
                esac
                result="$result\"$type\":$type_result,"
            done
            result="${result%,}}"
        fi
    else
        # Single validation type
        if [[ "$RETRY_ENABLED" == "true" ]]; then
            case "$VALIDATION_TYPE" in
                dependencies)
                    result=$(with_retry validate_dependencies "dependencies")
                    ;;
                environment)
                    result=$(with_retry validate_environment "environment")
                    ;;
                modules)
                    result=$(with_retry validate_modules "modules")
                    ;;
                network)
                    result=$(with_retry validate_network "network")
                    ;;
            esac
            exit_code=$?
        else
            case "$VALIDATION_TYPE" in
                dependencies)
                    result=$(validate_dependencies)
                    ;;
                environment)
                    result=$(validate_environment)
                    ;;
                modules)
                    result=$(validate_modules)
                    ;;
                network)
                    result=$(validate_network)
                    ;;
            esac
            exit_code=$?
        fi
    fi
    
    # Output final result
    echo "$result"
    
    # Log completion
    if [[ $exit_code -eq 0 ]]; then
        log_structured "SUCCESS" "main" "Validation suite completed successfully"
    else
        log_structured "ERROR" "main" "Validation suite completed with failures"
    fi
    
    exit $exit_code
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi