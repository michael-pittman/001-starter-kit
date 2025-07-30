#!/usr/bin/env bash
# =============================================================================
# Parallel Execution Framework
# High-performance parallel execution for independent AWS operations
# Compatible with bash 3.x+
# =============================================================================

# Load dependencies
if [[ -n "$LIB_DIR" ]]; then
    source "$LIB_DIR/modules/core/logging.sh" 2>/dev/null || true
    source "$LIB_DIR/associative-arrays.sh" 2>/dev/null || true
fi

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================

# Maximum parallel jobs
declare -g PARALLEL_MAX_JOBS="${PARALLEL_MAX_JOBS:-10}"
declare -g PARALLEL_JOB_TIMEOUT="${PARALLEL_JOB_TIMEOUT:-300}"  # 5 minutes
declare -g PARALLEL_RETRY_COUNT="${PARALLEL_RETRY_COUNT:-3}"
declare -g PARALLEL_RETRY_DELAY="${PARALLEL_RETRY_DELAY:-5}"

# Job tracking arrays
declare -gA PARALLEL_JOBS
declare -gA PARALLEL_JOB_STATUS
declare -gA PARALLEL_JOB_OUTPUT
declare -gA PARALLEL_JOB_ERRORS
declare -gA PARALLEL_JOB_START_TIME
declare -gA PARALLEL_JOB_END_TIME

# =============================================================================
# JOB MANAGEMENT
# =============================================================================

# Execute command in background with tracking
parallel_execute() {
    local job_id="$1"
    local command="$2"
    shift 2
    local args=("$@")
    
    # Check if we're at max capacity
    wait_for_job_slot
    
    # Create output and error files
    local output_file="/tmp/parallel_${job_id}_out_$$"
    local error_file="/tmp/parallel_${job_id}_err_$$"
    
    # Store job info
    aa_set PARALLEL_JOBS "$job_id" "$command ${args[*]}"
    aa_set PARALLEL_JOB_STATUS "$job_id" "running"
    aa_set PARALLEL_JOB_START_TIME "$job_id" "$(date +%s)"
    
    # Execute command in background
    (
        # Execute with timeout
        if command -v timeout >/dev/null 2>&1; then
            timeout "$PARALLEL_JOB_TIMEOUT" "$command" "${args[@]}" >"$output_file" 2>"$error_file"
        else
            # Fallback for systems without timeout command
            "$command" "${args[@]}" >"$output_file" 2>"$error_file" &
            local cmd_pid=$!
            
            # Simple timeout implementation
            (
                sleep "$PARALLEL_JOB_TIMEOUT"
                kill -0 $cmd_pid 2>/dev/null && kill -TERM $cmd_pid
            ) &
            local timeout_pid=$!
            
            wait $cmd_pid
            local exit_code=$?
            kill -0 $timeout_pid 2>/dev/null && kill -TERM $timeout_pid
            exit $exit_code
        fi
    ) &
    
    local pid=$!
    aa_set PARALLEL_JOBS "${job_id}_pid" "$pid"
    aa_set PARALLEL_JOBS "${job_id}_output" "$output_file"
    aa_set PARALLEL_JOBS "${job_id}_error" "$error_file"
    
    log "Started parallel job: $job_id (PID: $pid)"
}

# Wait for available job slot
wait_for_job_slot() {
    while true; do
        local active_jobs=0
        
        # Count active jobs
        for job_id in $(aa_keys PARALLEL_JOB_STATUS); do
            local status=$(aa_get PARALLEL_JOB_STATUS "$job_id")
            [[ "$status" == "running" ]] && active_jobs=$((active_jobs + 1))
        done
        
        # Check if slot available
        if [[ $active_jobs -lt $PARALLEL_MAX_JOBS ]]; then
            break
        fi
        
        # Wait and check completed jobs
        sleep 0.5
        check_completed_jobs
    done
}

# Check for completed jobs
check_completed_jobs() {
    for job_id in $(aa_keys PARALLEL_JOB_STATUS); do
        local status=$(aa_get PARALLEL_JOB_STATUS "$job_id")
        
        if [[ "$status" == "running" ]]; then
            local pid=$(aa_get PARALLEL_JOBS "${job_id}_pid" "")
            
            if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                # Job completed
                wait "$pid"
                local exit_code=$?
                
                # Update status
                if [[ $exit_code -eq 0 ]]; then
                    aa_set PARALLEL_JOB_STATUS "$job_id" "completed"
                else
                    aa_set PARALLEL_JOB_STATUS "$job_id" "failed"
                fi
                
                # Store output and errors
                local output_file=$(aa_get PARALLEL_JOBS "${job_id}_output")
                local error_file=$(aa_get PARALLEL_JOBS "${job_id}_error")
                
                if [[ -f "$output_file" ]]; then
                    aa_set PARALLEL_JOB_OUTPUT "$job_id" "$(cat "$output_file")"
                    rm -f "$output_file"
                fi
                
                if [[ -f "$error_file" ]]; then
                    aa_set PARALLEL_JOB_ERRORS "$job_id" "$(cat "$error_file")"
                    rm -f "$error_file"
                fi
                
                aa_set PARALLEL_JOB_END_TIME "$job_id" "$(date +%s)"
            fi
        fi
    done
}

# Wait for all jobs to complete
parallel_wait_all() {
    local timeout="${1:-0}"  # 0 = no timeout
    local start_time=$(date +%s)
    
    while true; do
        local active_jobs=0
        
        # Check all jobs
        check_completed_jobs
        
        # Count active jobs
        for job_id in $(aa_keys PARALLEL_JOB_STATUS); do
            local status=$(aa_get PARALLEL_JOB_STATUS "$job_id")
            [[ "$status" == "running" ]] && active_jobs=$((active_jobs + 1))
        done
        
        # All done?
        if [[ $active_jobs -eq 0 ]]; then
            break
        fi
        
        # Check timeout
        if [[ $timeout -gt 0 ]]; then
            local elapsed=$(($(date +%s) - start_time))
            if [[ $elapsed -gt $timeout ]]; then
                log "Parallel wait timeout after ${elapsed}s"
                return 1
            fi
        fi
        
        sleep 0.5
    done
    
    return 0
}

# Get job result
parallel_get_result() {
    local job_id="$1"
    
    local status=$(aa_get PARALLEL_JOB_STATUS "$job_id" "")
    if [[ -z "$status" ]]; then
        error "Job not found: $job_id"
        return 1
    fi
    
    # Wait for job if still running
    if [[ "$status" == "running" ]]; then
        local pid=$(aa_get PARALLEL_JOBS "${job_id}_pid" "")
        if [[ -n "$pid" ]]; then
            wait "$pid"
        fi
        check_completed_jobs
    fi
    
    # Return output
    aa_get PARALLEL_JOB_OUTPUT "$job_id" ""
}

# Get job status
parallel_get_status() {
    local job_id="$1"
    aa_get PARALLEL_JOB_STATUS "$job_id" "unknown"
}

# Get job error
parallel_get_error() {
    local job_id="$1"
    aa_get PARALLEL_JOB_ERRORS "$job_id" ""
}

# =============================================================================
# BATCH OPERATIONS
# =============================================================================

# Execute multiple commands in parallel
parallel_batch() {
    local job_prefix="${1:-job}"
    shift
    local commands=("$@")
    
    local job_ids=()
    local job_count=0
    
    # Start all jobs
    for cmd in "${commands[@]}"; do
        local job_id="${job_prefix}_${job_count}"
        job_ids+=("$job_id")
        
        # Parse command (first word is command, rest are args)
        local cmd_array=($cmd)
        local command="${cmd_array[0]}"
        local args=("${cmd_array[@]:1}")
        
        parallel_execute "$job_id" "$command" "${args[@]}"
        job_count=$((job_count + 1))
    done
    
    # Return job IDs
    printf '%s\n' "${job_ids[@]}"
}

# Map function over array in parallel
parallel_map() {
    local func="$1"
    local job_prefix="${2:-map}"
    shift 2
    local items=("$@")
    
    local job_ids=()
    local index=0
    
    for item in "${items[@]}"; do
        local job_id="${job_prefix}_${index}"
        job_ids+=("$job_id")
        
        parallel_execute "$job_id" "$func" "$item"
        index=$((index + 1))
    done
    
    # Wait for completion
    parallel_wait_all
    
    # Collect results
    local results=()
    for job_id in "${job_ids[@]}"; do
        local result=$(parallel_get_result "$job_id")
        results+=("$result")
    done
    
    printf '%s\n' "${results[@]}"
}

# =============================================================================
# AWS SPECIFIC PARALLEL OPERATIONS
# =============================================================================

# Get spot prices across multiple regions in parallel
parallel_get_spot_prices() {
    local instance_type="$1"
    shift
    local regions=("$@")
    
    if [[ ${#regions[@]} -eq 0 ]]; then
        regions=(us-east-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1)
    fi
    
    log "Getting spot prices for $instance_type across ${#regions[@]} regions in parallel"
    
    # Define function to get prices for one region
    get_region_spot_price() {
        local region="$1"
        local instance_type="$2"
        
        local prices=$(aws ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "$region" \
            --query 'SpotPriceHistory[0].[AvailabilityZone,SpotPrice]' \
            --output text 2>/dev/null)
        
        if [[ -n "$prices" ]]; then
            echo "${region}:${prices}"
        fi
    }
    
    # Export function for subshells
    export -f get_region_spot_price
    
    # Execute in parallel
    local job_ids=()
    for region in "${regions[@]}"; do
        local job_id="spot_price_${region}"
        parallel_execute "$job_id" get_region_spot_price "$region" "$instance_type"
        job_ids+=("$job_id")
    done
    
    # Wait and collect results
    parallel_wait_all
    
    local best_price=""
    local best_region=""
    local best_az=""
    
    for job_id in "${job_ids[@]}"; do
        local result=$(parallel_get_result "$job_id")
        if [[ -n "$result" ]]; then
            local region=$(echo "$result" | cut -d: -f1)
            local az=$(echo "$result" | cut -d: -f2 | cut -f1)
            local price=$(echo "$result" | cut -d: -f2 | cut -f2)
            
            if [[ -z "$best_price" ]] || (( $(echo "$price < $best_price" | bc -l 2>/dev/null || echo 0) )); then
                best_price="$price"
                best_region="$region"
                best_az="$az"
            fi
        fi
    done
    
    if [[ -n "$best_price" ]]; then
        echo "${best_region}:${best_az}:${best_price}"
    fi
}

# Check instance availability across AZs in parallel
parallel_check_instance_availability() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    # Get all AZs
    local azs=($(aws ec2 describe-availability-zones \
        --region "$region" \
        --query 'AvailabilityZones[].ZoneName' \
        --output text))
    
    log "Checking $instance_type availability across ${#azs[@]} AZs in parallel"
    
    # Define check function
    check_az_capacity() {
        local az="$1"
        local instance_type="$2"
        local region="$3"
        
        # Try to get spot price as proxy for availability
        local price=$(aws ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --availability-zone "$az" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "$region" \
            --query 'SpotPriceHistory[0].SpotPrice' \
            --output text 2>/dev/null)
        
        if [[ -n "$price" ]] && [[ "$price" != "None" ]]; then
            echo "${az}:available:${price}"
        else
            echo "${az}:unavailable:0"
        fi
    }
    
    export -f check_az_capacity
    
    # Execute checks in parallel
    local job_ids=()
    for az in "${azs[@]}"; do
        local job_id="availability_${az}"
        parallel_execute "$job_id" check_az_capacity "$az" "$instance_type" "$region"
        job_ids+=("$job_id")
    done
    
    # Collect results
    parallel_wait_all
    
    local available_azs=()
    for job_id in "${job_ids[@]}"; do
        local result=$(parallel_get_result "$job_id")
        if [[ "$result" =~ :available: ]]; then
            available_azs+=("$result")
        fi
    done
    
    printf '%s\n' "${available_azs[@]}"
}

# =============================================================================
# PERFORMANCE MONITORING
# =============================================================================

# Get parallel execution statistics
parallel_get_stats() {
    local total_jobs=$(aa_size PARALLEL_JOBS)
    local completed=0
    local failed=0
    local running=0
    local total_time=0
    
    for job_id in $(aa_keys PARALLEL_JOB_STATUS); do
        local status=$(aa_get PARALLEL_JOB_STATUS "$job_id")
        
        case "$status" in
            completed) completed=$((completed + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            running) running=$((running + 1)) ;;
        esac
        
        # Calculate execution time
        local start_time=$(aa_get PARALLEL_JOB_START_TIME "$job_id" "0")
        local end_time=$(aa_get PARALLEL_JOB_END_TIME "$job_id" "0")
        
        if [[ $end_time -gt 0 ]]; then
            local job_time=$((end_time - start_time))
            total_time=$((total_time + job_time))
        fi
    done
    
    local avg_time=0
    if [[ $((completed + failed)) -gt 0 ]]; then
        avg_time=$((total_time / (completed + failed)))
    fi
    
    cat <<EOF
Parallel Execution Statistics:
==============================
Total Jobs: $total_jobs
Completed: $completed
Failed: $failed
Running: $running
Average Execution Time: ${avg_time}s
Max Parallel Jobs: $PARALLEL_MAX_JOBS
EOF
}

# Clear all job data
parallel_clear() {
    aa_clear PARALLEL_JOBS
    aa_clear PARALLEL_JOB_STATUS
    aa_clear PARALLEL_JOB_OUTPUT
    aa_clear PARALLEL_JOB_ERRORS
    aa_clear PARALLEL_JOB_START_TIME
    aa_clear PARALLEL_JOB_END_TIME
    
    # Clean up any remaining temp files
    rm -f /tmp/parallel_*_out_$$ /tmp/parallel_*_err_$$ 2>/dev/null
    
    log "Parallel execution data cleared"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize parallel execution system
init_parallel_executor() {
    # Set configuration from environment
    PARALLEL_MAX_JOBS="${PARALLEL_MAX_JOBS:-10}"
    PARALLEL_JOB_TIMEOUT="${PARALLEL_JOB_TIMEOUT:-300}"
    PARALLEL_RETRY_COUNT="${PARALLEL_RETRY_COUNT:-3}"
    
    # Clean up on exit
    trap parallel_clear EXIT
}

# Auto-initialize if sourced
init_parallel_executor