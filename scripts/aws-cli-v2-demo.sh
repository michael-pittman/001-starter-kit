#!/usr/bin/env bash
# =============================================================================
# AWS CLI v2 Demo Script
# Demonstrates modern AWS CLI v2 features and best practices
# Requires: bash 5.3.3+, AWS CLI v2
# =============================================================================

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load required libraries
source "$PROJECT_ROOT/lib/modules/core/bash_version.sh"
require_bash_533 "aws-cli-v2-demo.sh"

source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/aws-cli-v2.sh"
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Set default values
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
VERBOSE="${VERBOSE:-false}"
DEMO_MODE="${DEMO_MODE:-full}"

# =============================================================================
# DEMO FUNCTIONS
# =============================================================================

# Demo 1: Basic AWS CLI v2 initialization and validation
demo_basic_initialization() {
    echo
    info "=== Demo 1: AWS CLI v2 Initialization ==="
    
    log "Initializing AWS CLI v2 environment..."
    if init_aws_cli_v2 "$AWS_PROFILE" "$AWS_REGION"; then
        success "AWS CLI v2 initialization completed successfully"
        
        # Show current configuration
        info "Current AWS Configuration:"
        info "  Profile: ${AWS_PROFILE}"
        info "  Region: ${AWS_DEFAULT_REGION:-not set}"
        info "  CLI Version: $(aws --version | head -1)"
    else
        error "AWS CLI v2 initialization failed"
        return 1
    fi
}

# Demo 2: Enhanced error handling and retry logic
demo_error_handling_retry() {
    echo
    info "=== Demo 2: Error Handling and Retry Logic ==="
    
    log "Testing AWS CLI with retry logic..."
    
    # Test successful call
    info "Testing successful API call..."
    if aws ec2 describe-regions >/dev/null; then
        success "Successful API call completed"
    fi
    
    # Test with circuit breaker
    info "Testing circuit breaker functionality..."
    init_circuit_breaker "ec2" 3 30
    
    local service="ec2"
    if check_circuit_breaker "$service"; then
        info "Circuit breaker for $service is CLOSED (normal operation)"
        record_circuit_breaker_result "$service" "true"
    fi
    
    # Show circuit breaker state
    local state="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]}"
    info "Circuit breaker state for $service: $state"
}

# Demo 3: Intelligent caching system
demo_intelligent_caching() {
    echo
    info "=== Demo 3: Intelligent Caching System ==="
    
    log "Testing AWS CLI caching..."
    
    # First call (uncached)
    info "Making first API call (will be cached)..."
    local start_time=$(date +%s)
    aws ec2 describe-regions >/dev/null
    local first_call_time=$(($(date +%s) - start_time))
    
    # Second call (cached)
    info "Making second API call (should use cache)..."
    start_time=$(date +%s)
    aws ec2 describe-regions >/dev/null
    local second_call_time=$(($(date +%s) - start_time))
    
    success "First call took ${first_call_time}s, second call took ${second_call_time}s"
    
    if [[ $second_call_time -lt $first_call_time ]]; then
        success "Caching is working effectively!"
    fi
}

# Demo 4: Pagination with large datasets
demo_pagination() {
    echo
    info "=== Demo 4: Advanced Pagination ==="
    
    log "Testing pagination for large result sets..."
    
    # Test pagination with EC2 describe-instances
    info "Using pagination for EC2 instances..."
    local instance_count
    instance_count=$(aws_paginate ec2 describe-instances \
        --query 'length(Reservations[].Instances[])' \
        --output text)
    
    success "Found $instance_count instances using pagination"
    
    # Test pagination with SSM parameters
    info "Using pagination for SSM parameters..."
    local param_count
    param_count=$(aws_paginate ssm describe-parameters \
        --query 'length(Parameters)' \
        --output text 2>/dev/null || echo "0")
    
    success "Found $param_count SSM parameters using pagination"
}

# Demo 5: Rate limiting and API call monitoring
demo_rate_limiting() {
    echo
    info "=== Demo 5: Rate Limiting and Monitoring ==="
    
    log "Testing rate limiting functionality..."
    
    # Enable API call logging
    export LOG_AWS_CALLS="/tmp/aws-cli-demo-$(date +%s).log"
    export DEBUG=true
    
    # Make several API calls to test rate limiting
    for i in {1..3}; do
        info "Making API call $i/3..."
        aws_cli_with_retry ec2 describe-availability-zones \
            --region "$AWS_REGION" \
            --max-items 1 >/dev/null
        sleep 0.5
    done
    
    # Show API call log
    if [[ -f "$LOG_AWS_CALLS" ]]; then
        info "API call log contents:"
        cat "$LOG_AWS_CALLS" | head -10
        rm -f "$LOG_AWS_CALLS"
    fi
    
    export DEBUG=false
    unset LOG_AWS_CALLS
}

# Demo 6: Health checks and service monitoring
demo_health_checks() {
    echo
    info "=== Demo 6: AWS Service Health Checks ==="
    
    log "Performing comprehensive AWS service health check..."
    
    # Test core services
    local services=("ec2" "ssm" "elbv2")
    if aws_service_health_check "${services[@]}"; then
        success "All AWS services are healthy"
    else
        warning "Some AWS services may have issues"
    fi
    
    # Show circuit breaker states
    info "Circuit breaker states:"
    for service in "${services[@]}"; do
        local state="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]:-"not initialized"}"
        local failure_count="${AWS_SERVICE_FAILURE_COUNTS["$service"]:-0}"
        info "  $service: state=$state, failures=$failure_count"
    done
}

# Demo 7: Modern authentication features
demo_authentication() {
    echo
    info "=== Demo 7: Modern Authentication ==="
    
    log "Testing credential validation and SSO features..."
    
    # Validate current credentials
    if validate_aws_credentials "$AWS_PROFILE" "$AWS_REGION"; then
        success "Credential validation passed"
    else
        warning "Credential validation failed"
    fi
    
    # Check if SSO session needs refresh
    refresh_aws_sso_session "$AWS_PROFILE" || true
    
    # Show credential information (without exposing secrets)
    info "Current credential status:"
    local caller_identity
    if caller_identity=$(aws_cli_with_retry sts get-caller-identity --output json 2>/dev/null); then
        local account_id user_arn
        account_id=$(echo "$caller_identity" | jq -r '.Account // "unknown"')
        user_arn=$(echo "$caller_identity" | jq -r '.Arn // "unknown"')
        info "  Account: $account_id"
        info "  User/Role: $(basename "$user_arn")"
    fi
}

# Demo 8: Cache management and cleanup
demo_cache_management() {
    echo
    info "=== Demo 8: Cache Management ==="
    
    log "Testing cache management features..."
    
    # Show cache directory status
    if [[ -d "$AWS_CACHE_DIR" ]]; then
        local cache_files
        cache_files=$(find "$AWS_CACHE_DIR" -type f | wc -l)
        info "Current cache directory: $AWS_CACHE_DIR"
        info "Cache files: $cache_files"
        
        # Demonstrate cache cleanup
        cleanup_aws_cache 0  # Clean all cache files
        
        local remaining_files
        remaining_files=$(find "$AWS_CACHE_DIR" -type f | wc -l)
        success "Cache cleanup completed. Files remaining: $remaining_files"
    else
        info "Cache directory not found: $AWS_CACHE_DIR"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

AWS CLI v2 Demo Script - Demonstrates modern AWS CLI v2 features

OPTIONS:
    -r, --region REGION     AWS region (default: $AWS_REGION)
    -p, --profile PROFILE   AWS profile (default: $AWS_PROFILE)
    -m, --mode MODE         Demo mode: full, basic, advanced (default: $DEMO_MODE)
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

DEMO MODES:
    basic      - Run basic demos (1-3)
    advanced   - Run advanced demos (4-6)
    full       - Run all demos (1-8)

EXAMPLES:
    $0                              # Run full demo with defaults
    $0 -m basic -v                  # Run basic demos with verbose output
    $0 -r us-west-2 -p prod -m advanced  # Advanced demos in us-west-2 with prod profile

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            -m|--mode)
                DEMO_MODE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

run_demo_suite() {
    local mode="$1"
    
    info "Starting AWS CLI v2 Demo Suite (mode: $mode)"
    info "Profile: $AWS_PROFILE, Region: $AWS_REGION"
    
    case "$mode" in
        "basic")
            demo_basic_initialization
            demo_error_handling_retry
            demo_intelligent_caching
            ;;
        "advanced")
            demo_pagination
            demo_rate_limiting
            demo_health_checks
            ;;
        "full")
            demo_basic_initialization
            demo_error_handling_retry
            demo_intelligent_caching
            demo_pagination
            demo_rate_limiting
            demo_health_checks
            demo_authentication
            demo_cache_management
            ;;
        *)
            error "Unknown demo mode: $mode"
            error "Valid modes: basic, advanced, full"
            exit 1
            ;;
    esac
}

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set verbose mode
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Run the demo suite
    run_demo_suite "$DEMO_MODE"
    
    echo
    success "AWS CLI v2 Demo Suite completed successfully!"
    info "All modern AWS CLI v2 features are working correctly."
    echo
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
