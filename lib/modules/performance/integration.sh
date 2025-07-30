#!/usr/bin/env bash
#
# Module: performance/integration
# Description: Integration helpers for using performance modules in existing scripts
# Version: 1.0.0
# Dependencies: All performance modules
#
# This module provides simplified integration functions to easily add
# performance enhancements to existing deployment scripts.
#

set -euo pipefail

# Bash version compatibility
# Compatible with bash 3.x+

# Module directory detection
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

# Source all performance modules
source_performance_module() {
    local module="$1"
    local module_path="${MODULE_DIR}/${module}.sh"
    
    if [[ ! -f "$module_path" ]]; then
        echo "ERROR: Performance module not found: $module_path" >&2
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$module_path" || {
        echo "ERROR: Failed to source performance module: $module_path" >&2
        return 1
    }
}

# Load all performance modules
source_performance_module "parallel"
source_performance_module "cache"
source_performance_module "pool"
source_performance_module "progress"
source_performance_module "metrics"

# Global state
declare -gA PERF_INTEGRATION_STATE=(
    [initialized]="false"
    [modules_loaded]="true"
    [auto_metrics]="true"
    [auto_progress]="true"
    [auto_caching]="true"
)

# ============================================================================
# High-Level Integration Functions
# ============================================================================

#
# Initialize all performance modules with sensible defaults
#
# Arguments:
#   $1 - Optional: Stack name for identification
#
# Returns:
#   0 - Success
#   1 - Initialization failed
#
perf_init_all() {
    local stack_name="${1:-performance}"
    
    echo "Initializing performance modules..."
    
    # Initialize parallel processing
    parallel_init || {
        echo "ERROR: Failed to initialize parallel processing" >&2
        return 1
    }
    
    # Initialize caching
    cache_init || {
        echo "ERROR: Failed to initialize caching" >&2
        return 1
    }
    
    # Initialize connection pooling
    pool_init || {
        echo "ERROR: Failed to initialize connection pooling" >&2
        return 1
    }
    
    # Initialize progress indicators
    progress_init || {
        echo "ERROR: Failed to initialize progress indicators" >&2
        return 1
    }
    
    # Initialize metrics collection
    metrics_init || {
        echo "ERROR: Failed to initialize metrics" >&2
        return 1
    }
    
    PERF_INTEGRATION_STATE[initialized]="true"
    echo "Performance modules initialized successfully"
    return 0
}

# ============================================================================
# AWS CLI Enhancement Functions
# ============================================================================

#
# Enhanced AWS CLI with automatic caching, pooling, and metrics
#
# Usage: Same as regular aws command
# Example: perf_aws ec2 describe-instances --region us-east-1
#
perf_aws() {
    local service="$1"
    local operation="$2"
    shift 2
    local args=("$@")
    
    # Build cache key
    local cache_key="aws:${service}:${operation}:$(echo "${args[@]}" | sha256sum | cut -d' ' -f1)"
    
    # Start metrics
    metrics_operation_start "aws_${service}_${operation}" "aws_api"
    
    # Check cache first if reading data
    local result
    local cache_hit=false
    
    if [[ "$operation" =~ ^(describe|get|list) ]]; then
        if result=$(cache_get "$cache_key" 2>/dev/null); then
            cache_hit=true
            metrics_counter_increment "cache.hits.aws_api"
        else
            metrics_counter_increment "cache.misses.aws_api"
        fi
    fi
    
    # Execute if not cached
    if [[ "$cache_hit" == "false" ]]; then
        # Use connection pooling
        result=$(pool_aws_cli "$service" "$operation" "${args[@]}")
        local exit_code=$?
        
        # Cache successful results
        if [[ $exit_code -eq 0 ]] && [[ "$operation" =~ ^(describe|get|list) ]]; then
            local ttl=300  # 5 minutes default
            
            # Longer TTL for stable resources
            case "$operation" in
                describe-availability-zones|describe-regions)
                    ttl=86400  # 24 hours
                    ;;
                describe-instance-types|describe-images)
                    ttl=3600   # 1 hour
                    ;;
            esac
            
            cache_set "$cache_key" "$result" "$ttl" "aws_api"
        fi
        
        # End metrics
        if [[ $exit_code -eq 0 ]]; then
            metrics_operation_end "aws_${service}_${operation}" "aws_api" "success"
        else
            metrics_operation_end "aws_${service}_${operation}" "aws_api" "failure"
            return $exit_code
        fi
    else
        metrics_operation_end "aws_${service}_${operation}" "aws_api" "success"
    fi
    
    echo "$result"
    return 0
}

# ============================================================================
# Parallel Deployment Functions
# ============================================================================

#
# Deploy multiple resources in parallel
#
# Arguments:
#   Array of deployment tasks passed via stdin or as arguments
#
# Example:
#   perf_parallel_deploy << EOF
#   vpc:create_vpc_resources
#   sg:create_security_groups
#   iam:create_iam_roles
#   EOF
#
perf_parallel_deploy() {
    local -a tasks=()
    
    if [[ $# -gt 0 ]]; then
        tasks=("$@")
    else
        local line
        while IFS= read -r line; do
            [[ -n "$line" ]] && tasks+=("$line")
        done
    fi
    
    progress_steps_start "deployment" "Parallel Deployment" "${tasks[@]}"
    
    # Convert tasks to parallel batch format
    local -a parallel_tasks=()
    local i=0
    for task in "${tasks[@]}"; do
        local task_id="${task%%:*}"
        local task_cmd="${task#*:}"
        parallel_tasks+=("${task_id}:${task_cmd}")
        ((i++))
    done
    
    # Execute in parallel
    if parallel_batch "${parallel_tasks[@]}"; then
        progress_success "All deployment tasks completed successfully"
        return 0
    else
        progress_error "Some deployment tasks failed"
        return 1
    fi
}

# ============================================================================
# Progress Wrapper Functions
# ============================================================================

#
# Execute command with automatic progress indication
#
# Arguments:
#   $1 - Description
#   $@ - Command to execute
#
perf_with_progress() {
    local description="$1"
    shift
    
    progress_run "$description" "$@"
}

#
# Execute command with progress bar
#
# Arguments:
#   $1 - Description
#   $2 - Total steps
#   $@ - Command that outputs step numbers
#
perf_with_progress_bar() {
    local description="$1"
    local total_steps="$2"
    shift 2
    
    local task_id="task-$$"
    progress_bar_create "$task_id" "$total_steps" "$description"
    
    # Execute command and update progress
    "$@" | while read -r line; do
        if [[ "$line" =~ ^PROGRESS:([0-9]+) ]]; then
            progress_bar_update "$task_id" "${BASH_REMATCH[1]}"
        else
            echo "$line"
        fi
    done
    
    progress_bar_complete "$task_id"
}

# ============================================================================
# Spot Price Functions with Caching
# ============================================================================

#
# Get spot prices with automatic caching
#
# Arguments:
#   $1 - Instance type
#   $2 - Optional: Region
#
# Returns:
#   Best spot price and AZ
#
perf_get_spot_price() {
    local instance_type="$1"
    local region="${2:-${AWS_REGION:-us-east-1}}"
    
    local cache_key="spot_price:${region}:${instance_type}"
    
    # Check cache (1 hour TTL for spot prices)
    local cached_price
    if cached_price=$(cache_get "$cache_key" 2>/dev/null); then
        echo "$cached_price"
        return 0
    fi
    
    # Fetch with progress indication
    local result
    result=$(progress_run "Fetching spot prices for $instance_type" \
        analyze_spot_pricing "$instance_type" "$region")
    
    if [[ $? -eq 0 ]]; then
        # Cache for 1 hour
        cache_set "$cache_key" "$result" 3600 "spot_prices"
        echo "$result"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Batch Operations
# ============================================================================

#
# Execute multiple AWS operations in parallel with caching
#
# Arguments:
#   Array of operations in format "id:aws_command"
#
# Example:
#   perf_batch_aws << EOF
#   instances:ec2 describe-instances
#   vpcs:ec2 describe-vpcs
#   subnets:ec2 describe-subnets
#   EOF
#
perf_batch_aws() {
    local -a operations=()
    local line
    
    while IFS= read -r line; do
        [[ -n "$line" ]] && operations+=("$line")
    done
    
    progress_spinner_start "Executing ${#operations[@]} AWS operations in parallel"
    
    # Convert to parallel tasks
    local -a tasks=()
    for op in "${operations[@]}"; do
        local op_id="${op%%:*}"
        local aws_cmd="${op#*:}"
        tasks+=("${op_id}:perf_aws $aws_cmd")
    done
    
    # Execute in parallel
    parallel_batch "${tasks[@]}"
    local exit_code=$?
    
    progress_spinner_stop "AWS operations completed" \
        $([ $exit_code -eq 0 ] && echo "success" || echo "failure")
    
    # Collect results
    for op in "${operations[@]}"; do
        local op_id="${op%%:*}"
        echo "=== $op_id ==="
        parallel_get_job_output "$op_id"
        echo
    done
    
    return $exit_code
}

# ============================================================================
# Performance Report Generation
# ============================================================================

#
# Generate and display performance report
#
# Arguments:
#   $1 - Optional: Format (json|text|markdown)
#
perf_show_report() {
    local format="${1:-text}"
    
    echo
    echo "=== Performance Report ==="
    echo
    
    # Show cache statistics
    echo "Cache Statistics:"
    cache_get_stats | sed 's/^/  /'
    echo
    
    # Show connection pool statistics
    echo "Connection Pool Statistics:"
    pool_get_stats | sed 's/^/  /'
    echo
    
    # Show parallel execution statistics
    echo "Parallel Execution Statistics:"
    parallel_get_stats | sed 's/^/  /'
    echo
    
    # Generate metrics report
    metrics_generate_report "$format"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

#
# Clean up all performance module resources
#
perf_cleanup() {
    echo "Cleaning up performance modules..."
    
    # Stop metrics collection
    metrics_stop 2>/dev/null || true
    
    # Shutdown connection pool
    pool_shutdown 2>/dev/null || true
    
    # Cleanup parallel jobs
    parallel_cleanup all 2>/dev/null || true
    
    # Clear cache if requested
    if [[ "${1:-}" == "--clear-cache" ]]; then
        cache_clear all
    fi
    
    echo "Performance modules cleaned up"
}

# ============================================================================
# Example Integration Functions
# ============================================================================

#
# Example: Deploy EC2 instance with full performance enhancements
#
perf_deploy_ec2_instance() {
    local stack_name="$1"
    local instance_type="$2"
    
    # Initialize performance modules
    perf_init_all "$stack_name"
    
    # Multi-step progress
    progress_steps_start "ec2_deploy" "EC2 Instance Deployment" \
        "Fetch AMI" \
        "Get spot price" \
        "Create security group" \
        "Launch instance" \
        "Wait for running" \
        "Configure instance"
    
    # Step 1: Get AMI with caching
    progress_step_complete "ec2_deploy" 0
    local ami_id
    ami_id=$(perf_aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=Deep Learning AMI*" \
        --query 'Images[0].ImageId' \
        --output text)
    
    # Step 2: Get spot price
    progress_step_complete "ec2_deploy" 1
    local spot_info
    spot_info=$(perf_get_spot_price "$instance_type")
    
    # Continue with deployment...
    # (Implementation details omitted for brevity)
    
    # Show performance report
    perf_show_report
}

# ============================================================================
# Module Configuration
# ============================================================================

#
# Configure performance settings
#
perf_configure() {
    local setting="$1"
    local value="$2"
    
    case "$setting" in
        auto_metrics)
            PERF_INTEGRATION_STATE[auto_metrics]="$value"
            ;;
        auto_progress)
            PERF_INTEGRATION_STATE[auto_progress]="$value"
            ;;
        auto_caching)
            PERF_INTEGRATION_STATE[auto_caching]="$value"
            ;;
        cache_ttl)
            cache_configure "default_ttl_seconds" "$value"
            ;;
        max_parallel)
            parallel_configure "max_concurrent_jobs" "$value"
            ;;
        metrics_export)
            metrics_configure "enable_cloudwatch_export" "$value"
            ;;
        *)
            echo "Unknown setting: $setting" >&2
            return 1
            ;;
    esac
}

# ============================================================================
# Module Exports
# ============================================================================

# Export integration functions
export -f perf_init_all
export -f perf_aws
export -f perf_parallel_deploy
export -f perf_with_progress
export -f perf_with_progress_bar
export -f perf_get_spot_price
export -f perf_batch_aws
export -f perf_show_report
export -f perf_cleanup
export -f perf_deploy_ec2_instance
export -f perf_configure

# Export state
export PERF_INTEGRATION_STATE

# Module metadata
export PERF_INTEGRATION_VERSION="1.0.0"

# Setup cleanup on exit
trap 'perf_cleanup 2>/dev/null || true' EXIT

echo "Performance integration module loaded successfully"