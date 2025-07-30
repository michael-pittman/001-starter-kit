#!/bin/bash
# performance/optimization.sh - Core performance optimization functions

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/monitoring.sh"

# Optimization flags
declare -g PERF_OPTIMIZE_STARTUP=true
declare -g PERF_OPTIMIZE_MEMORY=true
declare -g PERF_OPTIMIZE_API_CALLS=true
declare -g PERF_OPTIMIZE_PARALLEL=true

# Lazy loading registry
declare -g -A PERF_LAZY_LOADED_MODULES

# Module load optimization - lazy loading
perf_optimize_module_loading() {
    local module_path="$1"
    local module_name=$(basename "$module_path" .sh)
    
    # Check if already loaded
    if [[ "${PERF_LAZY_LOADED_MODULES[$module_name]}" == "loaded" ]]; then
        return 0
    fi
    
    # Define a lazy loader function
    eval "lazy_load_${module_name}() {
        if [[ \"\${PERF_LAZY_LOADED_MODULES[$module_name]}\" != \"loaded\" ]]; then
            source \"$module_path\"
            PERF_LAZY_LOADED_MODULES[$module_name]=\"loaded\"
        fi
    }"
    
    # Mark as available but not loaded
    PERF_LAZY_LOADED_MODULES[$module_name]="available"
}

# Optimize script startup time
perf_optimize_startup() {
    # Skip unnecessary checks in non-interactive mode
    if [[ ! -t 0 ]]; then
        export BASH_SILENCE_DEPRECATION_WARNING=1
    fi
    
    # Disable command hashing for faster lookups
    set +h
    
    # Pre-compile regex patterns
    declare -g -A PERF_COMPILED_PATTERNS
    PERF_COMPILED_PATTERNS["valid_stack_name"]='^[a-zA-Z][a-zA-Z0-9-]*$'
    PERF_COMPILED_PATTERNS["valid_region"]='^[a-z]{2}-[a-z]+-[0-9]+$'
    PERF_COMPILED_PATTERNS["valid_ami"]='^ami-[a-f0-9]{17}$'
    
    # Cache environment checks
    declare -g -A PERF_ENV_CACHE
    PERF_ENV_CACHE["has_aws_cli"]=$(command -v aws >/dev/null 2>&1 && echo "true" || echo "false")
    PERF_ENV_CACHE["has_jq"]=$(command -v jq >/dev/null 2>&1 && echo "true" || echo "false")
    PERF_ENV_CACHE["has_bc"]=$(command -v bc >/dev/null 2>&1 && echo "true" || echo "false")
}

# Memory optimization functions
perf_optimize_memory() {
    # Clear bash history in non-interactive mode
    if [[ ! -t 0 ]]; then
        history -c 2>/dev/null || true
    fi
    
    # Unset large variables after use
    perf_cleanup_large_vars() {
        local var_name="$1"
        unset "$var_name"
    }
    
    # Limit array sizes
    perf_limit_array_size() {
        local -n array=$1
        local max_size=${2:-1000}
        
        if [[ ${#array[@]} -gt $max_size ]]; then
            # Keep only the most recent entries
            local temp=("${array[@]: -$max_size}")
            array=("${temp[@]}")
        fi
    }
}

# API call optimization
perf_optimize_api_calls() {
    # Batch API calls where possible
    declare -g -A PERF_API_BATCH_QUEUE
    declare -g PERF_API_BATCH_SIZE=20
    declare -g PERF_API_BATCH_TIMEOUT=2
    
    # Queue an API call for batching
    perf_queue_api_call() {
        local call_type="$1"
        local call_params="$2"
        local queue_key="${call_type}"
        
        PERF_API_BATCH_QUEUE[$queue_key]+="${call_params}|"
        
        # Check if we should flush
        local queue_size=$(echo "${PERF_API_BATCH_QUEUE[$queue_key]}" | tr '|' '\n' | wc -l)
        if [[ $queue_size -ge $PERF_API_BATCH_SIZE ]]; then
            perf_flush_api_batch "$call_type"
        fi
    }
    
    # Flush batched API calls
    perf_flush_api_batch() {
        local call_type="$1"
        local batch_data="${PERF_API_BATCH_QUEUE[$call_type]}"
        
        if [[ -z "$batch_data" ]]; then
            return 0
        fi
        
        case "$call_type" in
            "describe-instances")
                perf_batch_describe_instances "$batch_data"
                ;;
            "describe-spot-price-history")
                perf_batch_describe_spot_prices "$batch_data"
                ;;
            *)
                # Fallback to individual calls
                IFS='|' read -ra calls <<< "$batch_data"
                for call in "${calls[@]}"; do
                    [[ -n "$call" ]] && eval "$call"
                done
                ;;
        esac
        
        # Clear the queue
        PERF_API_BATCH_QUEUE[$call_type]=""
    }
}

# Batch describe instances
perf_batch_describe_instances() {
    local instance_ids="$1"
    local filters=""
    
    # Build filters from instance IDs
    IFS='|' read -ra ids <<< "$instance_ids"
    for id in "${ids[@]}"; do
        [[ -n "$id" ]] && filters+="Name=instance-id,Values=$id "
    done
    
    # Single batched call
    aws ec2 describe-instances --filters $filters --query 'Reservations[*].Instances[*]' --output json
}

# Deduplicate API calls
declare -g -A PERF_API_CACHE
declare -g PERF_API_CACHE_TTL=300  # 5 minutes

perf_cached_api_call() {
    local cache_key="$1"
    shift
    local command="$@"
    
    # Check cache
    local cached_result="${PERF_API_CACHE[$cache_key]}"
    if [[ -n "$cached_result" ]]; then
        local cache_time=$(echo "$cached_result" | cut -d'|' -f1)
        local current_time=$(date +%s)
        
        if [[ $((current_time - cache_time)) -lt $PERF_API_CACHE_TTL ]]; then
            # Return cached result
            echo "$cached_result" | cut -d'|' -f2-
            return 0
        fi
    fi
    
    # Execute command and cache result
    local result=$($command)
    PERF_API_CACHE[$cache_key]="$(date +%s)|$result"
    echo "$result"
}

# Optimize AWS CLI usage
perf_optimize_aws_cli() {
    # Use --query to reduce data transfer
    export AWS_CLI_AUTO_PROMPT=off
    export AWS_PAGER=""
    
    # Pre-validate regions to avoid API calls
    declare -g -A PERF_VALID_REGIONS=(
        ["us-east-1"]=1 ["us-east-2"]=1 ["us-west-1"]=1 ["us-west-2"]=1
        ["eu-west-1"]=1 ["eu-central-1"]=1 ["ap-southeast-1"]=1 ["ap-northeast-1"]=1
    )
    
    perf_is_valid_region() {
        local region="$1"
        [[ -n "${PERF_VALID_REGIONS[$region]}" ]]
    }
}

# Script loading optimization
perf_optimize_script_loading() {
    # Preload commonly used functions
    declare -g -A PERF_PRELOADED_FUNCS
    
    # Cache function existence checks
    perf_function_exists() {
        local func_name="$1"
        
        # Check cache first
        if [[ -n "${PERF_PRELOADED_FUNCS[$func_name]}" ]]; then
            return 0
        fi
        
        # Check if function exists
        if declare -F "$func_name" >/dev/null 2>&1; then
            PERF_PRELOADED_FUNCS[$func_name]=1
            return 0
        fi
        
        return 1
    }
}

# File operation optimization
perf_optimize_file_ops() {
    # Buffer file writes
    declare -g -A PERF_FILE_WRITE_BUFFER
    declare -g PERF_FILE_WRITE_BUFFER_SIZE=4096
    
    perf_buffered_write() {
        local file="$1"
        local content="$2"
        
        PERF_FILE_WRITE_BUFFER[$file]+="$content"
        
        # Flush if buffer is large enough
        if [[ ${#PERF_FILE_WRITE_BUFFER[$file]} -ge $PERF_FILE_WRITE_BUFFER_SIZE ]]; then
            perf_flush_file_buffer "$file"
        fi
    }
    
    perf_flush_file_buffer() {
        local file="$1"
        
        if [[ -n "${PERF_FILE_WRITE_BUFFER[$file]}" ]]; then
            echo -n "${PERF_FILE_WRITE_BUFFER[$file]}" >> "$file"
            PERF_FILE_WRITE_BUFFER[$file]=""
        fi
    }
    
    # Flush all buffers on exit
    trap 'for f in "${!PERF_FILE_WRITE_BUFFER[@]}"; do perf_flush_file_buffer "$f"; done' EXIT
}

# Process optimization
perf_optimize_processes() {
    # Limit background processes
    declare -g PERF_MAX_BACKGROUND_PROCS=4
    declare -g -a PERF_BACKGROUND_PIDS
    
    perf_manage_background_process() {
        local command="$1"
        
        # Wait if too many background processes
        while [[ ${#PERF_BACKGROUND_PIDS[@]} -ge $PERF_MAX_BACKGROUND_PROCS ]]; do
            # Check for completed processes
            local new_pids=()
            for pid in "${PERF_BACKGROUND_PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            PERF_BACKGROUND_PIDS=("${new_pids[@]}")
            
            # Short sleep if still at limit
            [[ ${#PERF_BACKGROUND_PIDS[@]} -ge $PERF_MAX_BACKGROUND_PROCS ]] && sleep 0.1
        done
        
        # Start new background process
        eval "$command &"
        local new_pid=$!
        PERF_BACKGROUND_PIDS+=("$new_pid")
        echo "$new_pid"
    }
}

# Resource pooling
perf_optimize_resource_pooling() {
    # Connection pooling for AWS CLI
    export AWS_MAX_ATTEMPTS=3
    export AWS_RETRY_MODE=adaptive
    
    # Reuse SSH connections
    export SSH_CONTROL_PATH="/tmp/ssh-%r@%h:%p"
    export SSH_CONTROL_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=60"
}

# Apply all optimizations
perf_apply_all_optimizations() {
    local optimization_level="${1:-standard}"
    
    perf_start_phase "optimization"
    
    # Always apply these optimizations
    perf_optimize_startup
    perf_optimize_aws_cli
    perf_optimize_script_loading
    perf_optimize_resource_pooling
    
    # Apply based on optimization level
    case "$optimization_level" in
        "aggressive")
            perf_optimize_memory
            perf_optimize_api_calls
            perf_optimize_file_ops
            perf_optimize_processes
            ;;
        "standard")
            perf_optimize_api_calls
            ;;
        "minimal")
            # Only basic optimizations
            ;;
    esac
    
    perf_end_phase "optimization"
}

# Performance debugging helpers
perf_debug_slow_operation() {
    local operation="$1"
    local threshold="${2:-1.0}"  # seconds
    
    local start_time=$(date +%s.%N)
    eval "$operation"
    local result=$?
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc -l)
    if (( $(echo "$duration > $threshold" | bc -l) )); then
        echo "PERF WARNING: Operation '$operation' took ${duration}s (threshold: ${threshold}s)" >&2
    fi
    
    return $result
}

# Export optimization functions
export -f perf_optimize_module_loading
export -f perf_optimize_startup
export -f perf_cached_api_call
export -f perf_apply_all_optimizations