#!/bin/bash
# performance/parallel.sh - Parallel execution framework for performance optimization

# Parallel execution configuration
declare -g PARALLEL_MAX_JOBS=${PARALLEL_MAX_JOBS:-4}
declare -g PARALLEL_JOB_TIMEOUT=${PARALLEL_JOB_TIMEOUT:-300}  # 5 minutes default
declare -g PARALLEL_VERBOSE=${PARALLEL_VERBOSE:-false}

# Job tracking
declare -g -A PARALLEL_JOBS
declare -g -A PARALLEL_JOB_STATUS
declare -g -A PARALLEL_JOB_RESULTS
declare -g -A PARALLEL_JOB_START_TIME
declare -g PARALLEL_JOB_COUNTER=0

# Initialize parallel execution framework
parallel_init() {
    local max_jobs="${1:-$PARALLEL_MAX_JOBS}"
    
    # Set max jobs based on CPU cores if not specified
    if [[ "$max_jobs" == "auto" ]]; then
        PARALLEL_MAX_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    else
        PARALLEL_MAX_JOBS=$max_jobs
    fi
    
    # Create temp directory for job outputs
    declare -g PARALLEL_TEMP_DIR=$(mktemp -d "/tmp/parallel.XXXXXX")
    
    # Set up signal handlers
    trap 'parallel_cleanup' EXIT INT TERM
}

# Execute commands in parallel
parallel_execute() {
    local -a commands=("$@")
    local job_group_id="group_$$_$(date +%s)"
    local -a job_ids=()
    
    [[ "$PARALLEL_VERBOSE" == "true" ]] && echo "Starting parallel execution of ${#commands[@]} commands" >&2
    
    # Submit all jobs
    for cmd in "${commands[@]}"; do
        local job_id=$(parallel_submit_job "$cmd" "$job_group_id")
        job_ids+=("$job_id")
    done
    
    # Wait for all jobs to complete
    parallel_wait_for_group "$job_group_id"
    
    # Collect results
    local all_success=true
    for job_id in "${job_ids[@]}"; do
        if [[ "${PARALLEL_JOB_STATUS[$job_id]}" != "completed" ]]; then
            all_success=false
        fi
    done
    
    # Return success only if all jobs succeeded
    [[ "$all_success" == "true" ]]
}

# Submit a single job
parallel_submit_job() {
    local command="$1"
    local group_id="${2:-default}"
    
    # Generate unique job ID
    local job_id="job_${PARALLEL_JOB_COUNTER}_$$"
    PARALLEL_JOB_COUNTER=$((PARALLEL_JOB_COUNTER + 1))
    
    # Wait if at max capacity
    parallel_wait_for_slot
    
    # Create job output files
    local output_file="$PARALLEL_TEMP_DIR/${job_id}.out"
    local error_file="$PARALLEL_TEMP_DIR/${job_id}.err"
    local status_file="$PARALLEL_TEMP_DIR/${job_id}.status"
    
    # Record job info
    PARALLEL_JOBS[$job_id]="$command"
    PARALLEL_JOB_STATUS[$job_id]="running"
    PARALLEL_JOB_START_TIME[$job_id]=$(date +%s)
    
    # Execute job in background
    {
        # Set timeout for job
        if command -v timeout >/dev/null 2>&1; then
            timeout "$PARALLEL_JOB_TIMEOUT" bash -c "$command" > "$output_file" 2> "$error_file"
        else
            # Fallback timeout implementation
            bash -c "$command" > "$output_file" 2> "$error_file" &
            local cmd_pid=$!
            
            # Monitor timeout
            (
                sleep "$PARALLEL_JOB_TIMEOUT"
                kill -TERM $cmd_pid 2>/dev/null
            ) &
            local timeout_pid=$!
            
            # Wait for command to finish
            wait $cmd_pid
            local exit_code=$?
            
            # Kill timeout monitor
            kill $timeout_pid 2>/dev/null
            
            exit $exit_code
        fi
        
        echo $? > "$status_file"
    } &
    
    local bg_pid=$!
    
    # Track job PID and group
    echo "$bg_pid" > "$PARALLEL_TEMP_DIR/${job_id}.pid"
    echo "$group_id" > "$PARALLEL_TEMP_DIR/${job_id}.group"
    
    [[ "$PARALLEL_VERBOSE" == "true" ]] && echo "Submitted job $job_id (PID: $bg_pid): $command" >&2
    
    echo "$job_id"
}

# Wait for available job slot
parallel_wait_for_slot() {
    while true; do
        local running_jobs=0
        
        # Count running jobs
        for job_id in "${!PARALLEL_JOB_STATUS[@]}"; do
            if [[ "${PARALLEL_JOB_STATUS[$job_id]}" == "running" ]]; then
                # Check if job is still running
                if parallel_is_job_running "$job_id"; then
                    running_jobs=$((running_jobs + 1))
                else
                    # Job finished, update status
                    parallel_update_job_status "$job_id"
                fi
            fi
        done
        
        # Check if slot available
        if [[ $running_jobs -lt $PARALLEL_MAX_JOBS ]]; then
            break
        fi
        
        # Short sleep before checking again
        sleep 0.1
    done
}

# Check if job is still running
parallel_is_job_running() {
    local job_id="$1"
    local pid_file="$PARALLEL_TEMP_DIR/${job_id}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        kill -0 "$pid" 2>/dev/null
    else
        return 1
    fi
}

# Update job status
parallel_update_job_status() {
    local job_id="$1"
    local status_file="$PARALLEL_TEMP_DIR/${job_id}.status"
    local output_file="$PARALLEL_TEMP_DIR/${job_id}.out"
    local error_file="$PARALLEL_TEMP_DIR/${job_id}.err"
    
    if [[ -f "$status_file" ]]; then
        local exit_code=$(cat "$status_file")
        
        if [[ "$exit_code" -eq 0 ]]; then
            PARALLEL_JOB_STATUS[$job_id]="completed"
        else
            PARALLEL_JOB_STATUS[$job_id]="failed"
        fi
        
        # Store results
        PARALLEL_JOB_RESULTS[$job_id]="exit_code=$exit_code"
        
        # Calculate duration
        local start_time=${PARALLEL_JOB_START_TIME[$job_id]}
        local duration=$(($(date +%s) - start_time))
        
        [[ "$PARALLEL_VERBOSE" == "true" ]] && echo "Job $job_id finished in ${duration}s with exit code $exit_code" >&2
    else
        PARALLEL_JOB_STATUS[$job_id]="timeout"
        [[ "$PARALLEL_VERBOSE" == "true" ]] && echo "Job $job_id timed out" >&2
    fi
}

# Wait for job group to complete
parallel_wait_for_group() {
    local group_id="$1"
    local timeout="${2:-0}"  # 0 = no timeout
    local start_time=$(date +%s)
    
    while true; do
        local all_done=true
        local group_jobs=()
        
        # Find all jobs in group
        for job_id in "${!PARALLEL_JOBS[@]}"; do
            local job_group_file="$PARALLEL_TEMP_DIR/${job_id}.group"
            if [[ -f "$job_group_file" ]] && [[ "$(cat "$job_group_file")" == "$group_id" ]]; then
                group_jobs+=("$job_id")
                
                if [[ "${PARALLEL_JOB_STATUS[$job_id]}" == "running" ]]; then
                    if parallel_is_job_running "$job_id"; then
                        all_done=false
                    else
                        parallel_update_job_status "$job_id"
                    fi
                fi
            fi
        done
        
        # Check if all done
        if [[ "$all_done" == "true" ]]; then
            break
        fi
        
        # Check timeout
        if [[ "$timeout" -gt 0 ]]; then
            local elapsed=$(($(date +%s) - start_time))
            if [[ $elapsed -gt $timeout ]]; then
                # Kill remaining jobs
                for job_id in "${group_jobs[@]}"; do
                    if [[ "${PARALLEL_JOB_STATUS[$job_id]}" == "running" ]]; then
                        parallel_kill_job "$job_id"
                    fi
                done
                return 1
            fi
        fi
        
        sleep 0.1
    done
    
    return 0
}

# Kill a job
parallel_kill_job() {
    local job_id="$1"
    local pid_file="$PARALLEL_TEMP_DIR/${job_id}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        kill -TERM "$pid" 2>/dev/null || true
        sleep 0.5
        kill -KILL "$pid" 2>/dev/null || true
        
        PARALLEL_JOB_STATUS[$job_id]="killed"
    fi
}

# Get job output
parallel_get_output() {
    local job_id="$1"
    local output_file="$PARALLEL_TEMP_DIR/${job_id}.out"
    
    if [[ -f "$output_file" ]]; then
        cat "$output_file"
    fi
}

# Get job errors
parallel_get_errors() {
    local job_id="$1"
    local error_file="$PARALLEL_TEMP_DIR/${job_id}.err"
    
    if [[ -f "$error_file" ]]; then
        cat "$error_file"
    fi
}

# AWS parallel operations
parallel_describe_regions() {
    local regions=("$@")
    local -a commands=()
    
    for region in "${regions[@]}"; do
        commands+=("aws ec2 describe-regions --region $region --query 'Regions[0]' 2>/dev/null || echo '{}'")
    done
    
    parallel_execute "${commands[@]}"
}

# Parallel spot price queries
parallel_get_spot_prices() {
    local instance_type="$1"
    shift
    local regions=("$@")
    
    local -a commands=()
    local -a job_ids=()
    
    # Build commands for each region
    for region in "${regions[@]}"; do
        local cmd="aws ec2 describe-spot-price-history \
            --region $region \
            --instance-types $instance_type \
            --max-results 1 \
            --query 'SpotPriceHistory[0]' \
            --output json 2>/dev/null || echo '{}'"
        commands+=("$cmd")
    done
    
    # Execute in parallel
    local job_group="spot_prices_$$"
    for i in "${!commands[@]}"; do
        local job_id=$(parallel_submit_job "${commands[$i]}" "$job_group")
        job_ids+=("$job_id:${regions[$i]}")
    done
    
    # Wait for completion
    parallel_wait_for_group "$job_group"
    
    # Collect results
    declare -g -A SPOT_PRICES_RESULT
    for job_info in "${job_ids[@]}"; do
        local job_id="${job_info%%:*}"
        local region="${job_info#*:}"
        
        if [[ "${PARALLEL_JOB_STATUS[$job_id]}" == "completed" ]]; then
            local output=$(parallel_get_output "$job_id")
            if [[ -n "$output" ]] && [[ "$output" != "{}" ]]; then
                SPOT_PRICES_RESULT[$region]="$output"
            fi
        fi
    done
}

# Parallel EC2 instance operations
parallel_describe_instances() {
    local filter="$1"
    shift
    local regions=("$@")
    
    local -a commands=()
    for region in "${regions[@]}"; do
        commands+=("aws ec2 describe-instances --region $region $filter --query 'Reservations[*].Instances[*]' --output json")
    done
    
    parallel_execute "${commands[@]}"
}

# Map-reduce pattern implementation
parallel_map_reduce() {
    local map_function="$1"
    local reduce_function="$2"
    shift 2
    local -a input_data=("$@")
    
    # Map phase
    local -a job_ids=()
    local job_group="mapreduce_$$"
    
    for data in "${input_data[@]}"; do
        local cmd="$map_function '$data'"
        local job_id=$(parallel_submit_job "$cmd" "$job_group")
        job_ids+=("$job_id")
    done
    
    # Wait for map phase
    parallel_wait_for_group "$job_group"
    
    # Reduce phase
    local -a map_results=()
    for job_id in "${job_ids[@]}"; do
        if [[ "${PARALLEL_JOB_STATUS[$job_id]}" == "completed" ]]; then
            local output=$(parallel_get_output "$job_id")
            [[ -n "$output" ]] && map_results+=("$output")
        fi
    done
    
    # Apply reduce function
    if [[ ${#map_results[@]} -gt 0 ]]; then
        $reduce_function "${map_results[@]}"
    fi
}

# Parallel pipeline execution
parallel_pipeline() {
    local -a stages=("$@")
    local previous_output=""
    
    for stage in "${stages[@]}"; do
        if [[ -n "$previous_output" ]]; then
            # Pass previous output as input
            previous_output=$(echo "$previous_output" | $stage)
        else
            # First stage
            previous_output=$($stage)
        fi
        
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    done
    
    echo "$previous_output"
}

# Performance statistics for parallel execution
parallel_stats() {
    local total_jobs=0
    local completed_jobs=0
    local failed_jobs=0
    local total_duration=0
    
    for job_id in "${!PARALLEL_JOBS[@]}"; do
        total_jobs=$((total_jobs + 1))
        
        case "${PARALLEL_JOB_STATUS[$job_id]}" in
            "completed")
                completed_jobs=$((completed_jobs + 1))
                ;;
            "failed"|"timeout"|"killed")
                failed_jobs=$((failed_jobs + 1))
                ;;
        esac
        
        # Calculate duration
        if [[ -n "${PARALLEL_JOB_START_TIME[$job_id]}" ]]; then
            local duration=$(($(date +%s) - ${PARALLEL_JOB_START_TIME[$job_id]}))
            total_duration=$((total_duration + duration))
        fi
    done
    
    echo "=== Parallel Execution Statistics ==="
    echo "Total Jobs:      $total_jobs"
    echo "Completed:       $completed_jobs"
    echo "Failed:          $failed_jobs"
    echo "Max Parallel:    $PARALLEL_MAX_JOBS"
    echo "Total Duration:  ${total_duration}s"
    
    if [[ $total_jobs -gt 0 ]]; then
        local avg_duration=$((total_duration / total_jobs))
        echo "Avg Duration:    ${avg_duration}s"
        
        # Calculate speedup
        local sequential_estimate=$((avg_duration * total_jobs))
        local speedup=$(echo "scale=2; $sequential_estimate / $total_duration" | bc -l 2>/dev/null || echo "N/A")
        echo "Speedup:         ${speedup}x"
    fi
}

# Cleanup function
parallel_cleanup() {
    # Kill any remaining jobs
    for job_id in "${!PARALLEL_JOB_STATUS[@]}"; do
        if [[ "${PARALLEL_JOB_STATUS[$job_id]}" == "running" ]]; then
            parallel_kill_job "$job_id"
        fi
    done
    
    # Clean up temp directory
    if [[ -n "$PARALLEL_TEMP_DIR" ]] && [[ -d "$PARALLEL_TEMP_DIR" ]]; then
        rm -rf "$PARALLEL_TEMP_DIR"
    fi
}

# Export parallel functions
export -f parallel_init
export -f parallel_execute
export -f parallel_submit_job
export -f parallel_wait_for_group
export -f parallel_get_output
export -f parallel_get_errors
export -f parallel_map_reduce
export -f parallel_stats