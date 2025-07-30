#!/usr/bin/env bash
#
# Module: performance/pool
# Description: Connection pooling for AWS CLI and network connections
# Version: 1.0.0
# Dependencies: core/variables.sh, core/errors.sh, core/logging.sh
#
# This module provides connection pooling to reduce the overhead of
# establishing new connections for AWS API calls and other network operations.
#

set -euo pipefail

# Bash version compatibility
# Compatible with bash 3.x+

# Module directory detection
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

# Source dependencies with error handling
source_dependency() {
    local dep="$1"
    local dep_path="${MODULE_DIR}/../${dep}"
    
    if [[ ! -f "$dep_path" ]]; then
        echo "ERROR: Required dependency not found: $dep_path" >&2
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$dep_path" || {
        echo "ERROR: Failed to source dependency: $dep_path" >&2
        return 1
    }
}

# Load core dependencies
source_dependency "core/variables.sh"
source_dependency "core/errors.sh"
source_dependency "core/logging.sh"

# Module state management using associative arrays
declare -gA POOL_STATE=(
    [initialized]="false"
    [total_connections]="0"
    [active_connections]="0"
    [idle_connections]="0"
    [reused_connections]="0"
    [new_connections]="0"
    [failed_connections]="0"
)

# Connection pools
declare -gA POOL_AWS_CONNECTIONS     # AWS service endpoint connections
declare -gA POOL_HTTP_CONNECTIONS    # HTTP/HTTPS connections
declare -gA POOL_CONNECTION_METADATA # Connection metadata
declare -gA POOL_CONNECTION_STATS    # Connection statistics

# Module configuration
declare -gA POOL_CONFIG=(
    [max_connections_per_endpoint]="10"
    [max_idle_time_seconds]="300"
    [connection_timeout_seconds]="30"
    [retry_failed_connections]="true"
    [retry_count]="3"
    [retry_delay_seconds]="2"
    [keep_alive_enabled]="true"
    [keep_alive_interval_seconds]="60"
    [connection_validation]="true"
)

# AWS service endpoint mapping
declare -gA POOL_AWS_ENDPOINTS=(
    [ec2]="ec2.{region}.amazonaws.com"
    [s3]="s3.{region}.amazonaws.com"
    [rds]="rds.{region}.amazonaws.com"
    [iam]="iam.amazonaws.com"
    [cloudformation]="cloudformation.{region}.amazonaws.com"
    [sts]="sts.{region}.amazonaws.com"
    [ssm]="ssm.{region}.amazonaws.com"
)

# Module-specific error types
declare -gA POOL_ERROR_TYPES=(
    [POOL_INIT_FAILED]="Connection pool initialization failed"
    [POOL_CONNECTION_FAILED]="Failed to establish connection"
    [POOL_MAX_CONNECTIONS_EXCEEDED]="Maximum connections exceeded"
    [POOL_INVALID_ENDPOINT]="Invalid endpoint specified"
    [POOL_VALIDATION_FAILED]="Connection validation failed"
)

# ============================================================================
# Initialization Functions
# ============================================================================

#
# Initialize the connection pooling module
#
# Returns:
#   0 - Success
#   1 - Initialization failed
#
pool_init() {
    log_info "[${MODULE_NAME}] Initializing connection pooling module..."
    
    # Check if already initialized
    if [[ "${POOL_STATE[initialized]}" == "true" ]]; then
        log_debug "[${MODULE_NAME}] Module already initialized"
        return 0
    fi
    
    # Set up AWS CLI connection pooling
    export AWS_CLI_S3_DISABLE_THREADS=false
    export AWS_CLI_S3_MAX_CONCURRENT_REQUESTS=10
    export AWS_CLI_S3_MAX_QUEUE_SIZE=1000
    
    # Configure connection reuse
    export AWS_NODEJS_CONNECTION_REUSE_ENABLED=1
    export AWS_SDK_LOAD_CONFIG=1
    
    # Set up HTTP keep-alive
    export AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4
    export AWS_METADATA_SERVICE_TIMEOUT=5
    export AWS_METADATA_SERVICE_NUM_ATTEMPTS=3
    
    # Initialize connection tracking
    POOL_STATE[total_connections]=0
    POOL_STATE[active_connections]=0
    POOL_STATE[idle_connections]=0
    
    # Start connection monitor if keep-alive enabled
    if [[ "${POOL_CONFIG[keep_alive_enabled]}" == "true" ]]; then
        pool_start_monitor &
    fi
    
    # Mark as initialized
    POOL_STATE[initialized]="true"
    
    log_info "[${MODULE_NAME}] Module initialized successfully"
    return 0
}

# ============================================================================
# Core Functions
# ============================================================================

#
# Get or create a pooled connection for AWS service
#
# Arguments:
#   $1 - AWS service name (ec2, s3, rds, etc.)
#   $2 - AWS region
#
# Returns:
#   0 - Connection available
#   1 - Failed to establish connection
#
# Output:
#   Connection ID
#
pool_get_aws_connection() {
    local service="$1"
    local region="${2:-${AWS_REGION:-us-east-1}}"
    
    # Validate initialization
    if [[ "${POOL_STATE[initialized]}" != "true" ]]; then
        error_pool_init_failed "Module not initialized. Call pool_init() first."
        return 1
    fi
    
    # Get endpoint
    local endpoint_template="${POOL_AWS_ENDPOINTS[$service]:-}"
    if [[ -z "$endpoint_template" ]]; then
        error_pool_invalid_endpoint "Unknown AWS service: $service"
        return 1
    fi
    
    local endpoint="${endpoint_template//\{region\}/$region}"
    local pool_key="${service}:${region}"
    
    log_debug "[${MODULE_NAME}] Requesting connection for: $pool_key"
    
    # Check for existing idle connection
    local connection_id=$(pool_find_idle_connection "$pool_key")
    
    if [[ -n "$connection_id" ]]; then
        # Validate existing connection
        if pool_validate_connection "$connection_id"; then
            pool_mark_active "$connection_id"
            ((POOL_STATE[reused_connections]++))
            log_debug "[${MODULE_NAME}] Reusing connection: $connection_id"
            echo "$connection_id"
            return 0
        else
            # Remove invalid connection
            pool_remove_connection "$connection_id"
        fi
    fi
    
    # Check connection limit
    local current_connections=$(pool_count_endpoint_connections "$pool_key")
    if [[ $current_connections -ge ${POOL_CONFIG[max_connections_per_endpoint]} ]]; then
        error_pool_max_connections_exceeded "Maximum connections reached for $pool_key"
        return 1
    fi
    
    # Create new connection
    connection_id=$(pool_create_connection "$service" "$region" "$endpoint")
    
    if [[ -n "$connection_id" ]]; then
        ((POOL_STATE[new_connections]++))
        echo "$connection_id"
        return 0
    fi
    
    ((POOL_STATE[failed_connections]++))
    return 1
}

#
# Release a connection back to the pool
#
# Arguments:
#   $1 - Connection ID
#
# Returns:
#   0 - Success
#
pool_release_connection() {
    local connection_id="$1"
    
    if [[ -z "${POOL_CONNECTION_METADATA[$connection_id]+x}" ]]; then
        log_warn "[${MODULE_NAME}] Unknown connection ID: $connection_id"
        return 1
    fi
    
    pool_mark_idle "$connection_id"
    log_debug "[${MODULE_NAME}] Released connection: $connection_id"
    
    return 0
}

#
# Execute AWS CLI command with connection pooling
#
# Arguments:
#   $@ - AWS CLI command and arguments
#
# Returns:
#   AWS CLI exit code
#
# Output:
#   AWS CLI output
#
pool_aws_cli() {
    local aws_command="$1"
    shift
    local aws_args=("$@")
    
    # Extract service and region from command
    local service="$aws_command"
    local region="${AWS_REGION:-us-east-1}"
    
    for i in "${!aws_args[@]}"; do
        if [[ "${aws_args[$i]}" == "--region" ]] && [[ $((i + 1)) -lt ${#aws_args[@]} ]]; then
            region="${aws_args[$((i + 1))]}"
            break
        fi
    done
    
    # Get pooled connection
    local connection_id
    connection_id=$(pool_get_aws_connection "$service" "$region")
    
    if [[ $? -ne 0 ]]; then
        log_warn "[${MODULE_NAME}] Failed to get pooled connection, using direct call"
    fi
    
    # Execute AWS CLI command with optimized settings
    local output
    local exit_code
    
    AWS_RETRY_MODE=adaptive \
    AWS_MAX_ATTEMPTS="${POOL_CONFIG[retry_count]}" \
    AWS_NODEJS_CONNECTION_REUSE_ENABLED=1 \
    aws "$aws_command" "${aws_args[@]}"
    
    exit_code=$?
    
    # Release connection
    if [[ -n "$connection_id" ]]; then
        pool_release_connection "$connection_id"
    fi
    
    return $exit_code
}

# ============================================================================
# Connection Management Functions
# ============================================================================

#
# Create a new connection
#
# Arguments:
#   $1 - Service name
#   $2 - Region
#   $3 - Endpoint
#
# Returns:
#   Connection ID
#
pool_create_connection() {
    local service="$1"
    local region="$2"
    local endpoint="$3"
    
    local connection_id="${service}-${region}-$(date +%s%N)"
    local pool_key="${service}:${region}"
    local created_time=$(date +%s)
    
    # Test connection
    if ! pool_test_endpoint "$endpoint"; then
        error_pool_connection_failed "Failed to connect to $endpoint"
        return 1
    fi
    
    # Store connection metadata
    POOL_AWS_CONNECTIONS[$connection_id]="$pool_key"
    POOL_CONNECTION_METADATA[$connection_id]="$endpoint:$created_time:active"
    POOL_CONNECTION_STATS[$connection_id]="0:0:$created_time"  # requests:errors:last_used
    
    ((POOL_STATE[total_connections]++))
    ((POOL_STATE[active_connections]++))
    
    log_debug "[${MODULE_NAME}] Created connection: $connection_id for $pool_key"
    echo "$connection_id"
}

#
# Find an idle connection for the given pool key
#
# Arguments:
#   $1 - Pool key (service:region)
#
# Returns:
#   Connection ID or empty string
#
pool_find_idle_connection() {
    local pool_key="$1"
    local current_time=$(date +%s)
    local max_idle_time="${POOL_CONFIG[max_idle_time_seconds]}"
    
    for connection_id in "${!POOL_AWS_CONNECTIONS[@]}"; do
        if [[ "${POOL_AWS_CONNECTIONS[$connection_id]}" == "$pool_key" ]]; then
            local metadata="${POOL_CONNECTION_METADATA[$connection_id]}"
            local status="${metadata##*:}"
            
            if [[ "$status" == "idle" ]]; then
                # Check idle time
                local stats="${POOL_CONNECTION_STATS[$connection_id]}"
                local last_used="${stats##*:}"
                local idle_time=$((current_time - last_used))
                
                if [[ $idle_time -lt $max_idle_time ]]; then
                    echo "$connection_id"
                    return 0
                else
                    # Connection too old, remove it
                    pool_remove_connection "$connection_id"
                fi
            fi
        fi
    done
    
    return 1
}

#
# Validate a connection is still alive
#
# Arguments:
#   $1 - Connection ID
#
# Returns:
#   0 - Connection valid
#   1 - Connection invalid
#
pool_validate_connection() {
    local connection_id="$1"
    
    if [[ "${POOL_CONFIG[connection_validation]}" != "true" ]]; then
        return 0
    fi
    
    local metadata="${POOL_CONNECTION_METADATA[$connection_id]}"
    local endpoint="${metadata%%:*}"
    
    # Quick validation - just check if endpoint is reachable
    pool_test_endpoint "$endpoint"
}

#
# Test if an endpoint is reachable
#
# Arguments:
#   $1 - Endpoint URL
#
# Returns:
#   0 - Reachable
#   1 - Not reachable
#
pool_test_endpoint() {
    local endpoint="$1"
    
    # Use curl to test HTTPS endpoint
    if command -v curl &>/dev/null; then
        curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$endpoint" | grep -q "^[234]"
    else
        # Fallback to simple TCP test
        timeout 5 bash -c "echo >/dev/tcp/${endpoint%%:*}/443" 2>/dev/null
    fi
}

#
# Mark connection as active
#
# Arguments:
#   $1 - Connection ID
#
pool_mark_active() {
    local connection_id="$1"
    local metadata="${POOL_CONNECTION_METADATA[$connection_id]}"
    local endpoint="${metadata%%:*}"
    local created="${metadata#*:}"
    created="${created%%:*}"
    
    POOL_CONNECTION_METADATA[$connection_id]="$endpoint:$created:active"
    
    ((POOL_STATE[idle_connections]--))
    ((POOL_STATE[active_connections]++))
    
    # Update stats
    local stats="${POOL_CONNECTION_STATS[$connection_id]}"
    local requests="${stats%%:*}"
    local remaining="${stats#*:}"
    local errors="${remaining%%:*}"
    ((requests++))
    
    POOL_CONNECTION_STATS[$connection_id]="$requests:$errors:$(date +%s)"
}

#
# Mark connection as idle
#
# Arguments:
#   $1 - Connection ID
#
pool_mark_idle() {
    local connection_id="$1"
    local metadata="${POOL_CONNECTION_METADATA[$connection_id]}"
    local endpoint="${metadata%%:*}"
    local created="${metadata#*:}"
    created="${created%%:*}"
    
    POOL_CONNECTION_METADATA[$connection_id]="$endpoint:$created:idle"
    
    ((POOL_STATE[active_connections]--))
    ((POOL_STATE[idle_connections]++))
}

#
# Remove a connection from the pool
#
# Arguments:
#   $1 - Connection ID
#
pool_remove_connection() {
    local connection_id="$1"
    
    local metadata="${POOL_CONNECTION_METADATA[$connection_id]:-}"
    local status="${metadata##*:}"
    
    if [[ "$status" == "active" ]]; then
        ((POOL_STATE[active_connections]--))
    elif [[ "$status" == "idle" ]]; then
        ((POOL_STATE[idle_connections]--))
    fi
    
    unset "POOL_AWS_CONNECTIONS[$connection_id]"
    unset "POOL_CONNECTION_METADATA[$connection_id]"
    unset "POOL_CONNECTION_STATS[$connection_id]"
    
    ((POOL_STATE[total_connections]--))
    
    log_debug "[${MODULE_NAME}] Removed connection: $connection_id"
}

#
# Count connections for a specific endpoint
#
# Arguments:
#   $1 - Pool key (service:region)
#
# Returns:
#   Number of connections
#
pool_count_endpoint_connections() {
    local pool_key="$1"
    local count=0
    
    for connection_id in "${!POOL_AWS_CONNECTIONS[@]}"; do
        if [[ "${POOL_AWS_CONNECTIONS[$connection_id]}" == "$pool_key" ]]; then
            ((count++))
        fi
    done
    
    echo "$count"
}

# ============================================================================
# Monitoring Functions
# ============================================================================

#
# Start connection monitor for keep-alive
#
pool_start_monitor() {
    local monitor_pid_file="/tmp/pool-monitor-$$.pid"
    
    {
        echo $$ > "$monitor_pid_file"
        
        while true; do
            sleep "${POOL_CONFIG[keep_alive_interval_seconds]}"
            
            # Check each idle connection
            for connection_id in "${!POOL_CONNECTION_METADATA[@]}"; do
                local metadata="${POOL_CONNECTION_METADATA[$connection_id]:-}"
                local status="${metadata##*:}"
                
                if [[ "$status" == "idle" ]]; then
                    # Send keep-alive or validate connection
                    if ! pool_validate_connection "$connection_id"; then
                        pool_remove_connection "$connection_id"
                    fi
                fi
            done
            
            # Clean up old connections
            pool_cleanup_expired
        done
    } &
    
    log_debug "[${MODULE_NAME}] Started connection monitor (PID: $!)"
}

#
# Clean up expired connections
#
pool_cleanup_expired() {
    local current_time=$(date +%s)
    local max_idle_time="${POOL_CONFIG[max_idle_time_seconds]}"
    
    for connection_id in "${!POOL_CONNECTION_STATS[@]}"; do
        local stats="${POOL_CONNECTION_STATS[$connection_id]}"
        local last_used="${stats##*:}"
        local idle_time=$((current_time - last_used))
        
        if [[ $idle_time -gt $max_idle_time ]]; then
            log_debug "[${MODULE_NAME}] Removing expired connection: $connection_id"
            pool_remove_connection "$connection_id"
        fi
    done
}

# ============================================================================
# Query Functions
# ============================================================================

#
# Get connection pool statistics
#
# Output:
#   Pool statistics in key=value format
#
pool_get_stats() {
    local reuse_rate=0
    local total_used=$((POOL_STATE[reused_connections] + POOL_STATE[new_connections]))
    
    if [[ $total_used -gt 0 ]]; then
        reuse_rate=$((POOL_STATE[reused_connections] * 100 / total_used))
    fi
    
    echo "initialized=${POOL_STATE[initialized]}"
    echo "total_connections=${POOL_STATE[total_connections]}"
    echo "active_connections=${POOL_STATE[active_connections]}"
    echo "idle_connections=${POOL_STATE[idle_connections]}"
    echo "reused_connections=${POOL_STATE[reused_connections]}"
    echo "new_connections=${POOL_STATE[new_connections]}"
    echo "failed_connections=${POOL_STATE[failed_connections]}"
    echo "reuse_rate=${reuse_rate}%"
}

#
# List all connections
#
# Output:
#   List of connections with details
#
pool_list_connections() {
    for connection_id in "${!POOL_AWS_CONNECTIONS[@]}"; do
        local pool_key="${POOL_AWS_CONNECTIONS[$connection_id]}"
        local metadata="${POOL_CONNECTION_METADATA[$connection_id]}"
        local stats="${POOL_CONNECTION_STATS[$connection_id]}"
        
        local endpoint="${metadata%%:*}"
        local status="${metadata##*:}"
        local requests="${stats%%:*}"
        
        echo "$connection_id: $pool_key ($status) - $endpoint (requests: $requests)"
    done
}

# ============================================================================
# Utility Functions
# ============================================================================

#
# Configure pool settings
#
# Arguments:
#   $1 - Setting name
#   $2 - Setting value
#
pool_configure() {
    local setting="$1"
    local value="$2"
    
    if [[ -n "${POOL_CONFIG[$setting]+x}" ]]; then
        POOL_CONFIG[$setting]="$value"
        log_info "[${MODULE_NAME}] Set $setting=$value"
    else
        log_warn "[${MODULE_NAME}] Unknown setting: $setting"
    fi
}

#
# Shutdown pool and cleanup
#
pool_shutdown() {
    log_info "[${MODULE_NAME}] Shutting down connection pool"
    
    # Stop monitor
    pkill -f "pool-monitor-$$" 2>/dev/null || true
    
    # Close all connections
    for connection_id in "${!POOL_AWS_CONNECTIONS[@]}"; do
        pool_remove_connection "$connection_id"
    done
    
    POOL_STATE[initialized]="false"
}

# ============================================================================
# Error Handler Functions
# ============================================================================

#
# Register module-specific error handlers
#
pool_register_error_handlers() {
    for error_type in "${!POOL_ERROR_TYPES[@]}"; do
        local handler_name="error_$(echo "$error_type" | tr '[:upper:]' '[:lower:]')"
        
        # Create error handler function dynamically
        eval "
        $handler_name() {
            local message=\"\${1:-${POOL_ERROR_TYPES[$error_type]}}\"
            log_error \"[${MODULE_NAME}] \$message\"
            return 1
        }
        "
    done
}

# Register error handlers
pool_register_error_handlers

# ============================================================================
# Module Exports
# ============================================================================

# Export public functions
export -f pool_init
export -f pool_get_aws_connection
export -f pool_release_connection
export -f pool_aws_cli
export -f pool_get_stats
export -f pool_list_connections
export -f pool_configure
export -f pool_shutdown

# Export module state
export POOL_STATE
export POOL_CONFIG

# Module metadata
export POOL_MODULE_VERSION="1.0.0"
export POOL_MODULE_NAME="${MODULE_NAME}"

# Cleanup on exit
trap 'pool_shutdown 2>/dev/null || true' EXIT

# Indicate module is loaded
log_debug "[${MODULE_NAME}] Module loaded successfully"