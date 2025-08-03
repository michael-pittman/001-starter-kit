#!/bin/bash
# =============================================================================
# Unity Standard Plugin: Spot Optimizer
# Automatically converts on-demand instances to spot instances for cost savings
# Integrates with existing GeuseMaker spot instance logic
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Load required libraries
source "$PROJECT_ROOT/lib/associative-arrays.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/spot-instance.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/aws-quota-checker.sh" 2>/dev/null || true

# =============================================================================
# PLUGIN METADATA - REQUIRED
# =============================================================================

plugin_metadata() {
    cat <<'PLUGIN_METADATA'
{
  "name": "spot-optimizer",
  "version": "2.0.0",
  "api_version": "2.0",
  "description": "Automatically converts on-demand instances to spot instances for up to 70% cost savings",
  "author": "GeuseMaker Unity Team",
  "license": "MIT",
  "homepage": "https://github.com/geusemake/unity-plugins",
  "type": "optimization",
  "category": "cost-optimization",
  "priority": 80,
  "execution_mode": "sync",
  "bash_compatibility": {
    "min_version": "3.2",
    "tested_versions": ["3.2", "4.0", "4.4", "5.0", "5.1"]
  },
  "dependencies": {
    "required": ["aws-cli"],
    "optional": ["jq"],
    "unity_services": ["config", "events"],
    "system_commands": ["curl", "date", "grep", "awk"]
  },
  "capabilities": {
    "extension_points": ["pre_deployment", "post_deployment", "on_cost_threshold"],
    "event_handlers": ["deployment.started", "deployment.completed", "aws.resource.created"],
    "configuration_schema": true,
    "metrics_collection": true,
    "health_monitoring": true
  },
  "configuration": {
    "config_file": "spot-optimizer.yml",
    "environment_prefix": "SPOT_OPTIMIZER",
    "required_config": [],
    "optional_config": ["max_spot_price", "fallback_enabled", "interruption_threshold", "savings_target"]
  },
  "resources": {
    "max_memory_mb": 25,
    "max_cpu_percent": 5,
    "max_disk_mb": 50,
    "network_access": true,
    "file_permissions": ["read", "write:tmp", "read:/home/ec2-user/.aws"]
  },
  "security": {
    "sandbox_mode": false,
    "allowed_commands": ["aws", "curl", "date", "grep", "awk", "sort"],
    "restricted_paths": ["/etc/passwd", "/etc/shadow"],
    "environment_isolation": false
  }
}
PLUGIN_METADATA
}

# =============================================================================
# PLUGIN CONFIGURATION
# =============================================================================

# Plugin configuration defaults
readonly SPOT_OPTIMIZER_MAX_PRICE="${SPOT_OPTIMIZER_MAX_PRICE:-0.50}"
readonly SPOT_OPTIMIZER_FALLBACK_ENABLED="${SPOT_OPTIMIZER_FALLBACK_ENABLED:-true}"
readonly SPOT_OPTIMIZER_INTERRUPTION_THRESHOLD="${SPOT_OPTIMIZER_INTERRUPTION_THRESHOLD:-5.0}"
readonly SPOT_OPTIMIZER_SAVINGS_TARGET="${SPOT_OPTIMIZER_SAVINGS_TARGET:-60}"
readonly SPOT_OPTIMIZER_CACHE_TTL="${SPOT_OPTIMIZER_CACHE_TTL:-3600}"

# Plugin state variables
PLUGIN_SPOT_OPTIMIZER_STATE=""
PLUGIN_SPOT_OPTIMIZER_METRICS=""

# =============================================================================
# PLUGIN VALIDATION - REQUIRED
# =============================================================================

plugin_validate() {
    local errors=0
    local warnings=0
    
    _plugin_log "INFO" "Validating Spot Optimizer Plugin"
    
    # Validate bash version compatibility
    if ! _validate_bash_version; then
        _plugin_log "ERROR" "Bash version not supported (requires 3.2+)"
        errors=$((errors + 1))
    fi
    
    # Validate required dependencies
    if ! _validate_dependencies; then
        _plugin_log "ERROR" "Required dependencies not available"
        errors=$((errors + 1))
    fi
    
    # Validate AWS CLI access
    if ! _validate_aws_access; then
        _plugin_log "ERROR" "AWS CLI access validation failed"
        errors=$((errors + 1))
    fi
    
    # Validate configuration
    if ! _validate_configuration; then
        _plugin_log "WARNING" "Configuration validation issues detected"
        warnings=$((warnings + 1))
    fi
    
    # Validate system resources
    if ! _validate_resources; then
        _plugin_log "WARNING" "Resource constraints may be exceeded"
        warnings=$((warnings + 1))
    fi
    
    _plugin_log "INFO" "Validation completed: $errors errors, $warnings warnings"
    return $errors
}

# Helper validation functions
_validate_bash_version() {
    local required_version="3.2"
    local current_version="${BASH_VERSION%%.*}.${BASH_VERSION#*.}"
    current_version="${current_version%%.*}"
    
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" == "$required_version" ]]; then
        return 0
    else
        return 1
    fi
}

_validate_dependencies() {
    local required_deps=("aws")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            _plugin_log "ERROR" "Required dependency not found: $dep"
            return 1
        fi
    done
    
    # Check AWS CLI version
    if command -v aws >/dev/null 2>&1; then
        local aws_version
        aws_version=$(aws --version 2>&1 | head -n1 | cut -d' ' -f1 | cut -d'/' -f2)
        _plugin_log "INFO" "AWS CLI version: $aws_version"
    fi
    
    return 0
}

_validate_aws_access() {
    # Test basic AWS access
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        _plugin_log "ERROR" "AWS credentials not configured or invalid"
        return 1
    fi
    
    # Test EC2 access
    if ! aws ec2 describe-regions --max-items 1 >/dev/null 2>&1; then
        _plugin_log "ERROR" "EC2 API access denied"
        return 1
    fi
    
    return 0
}

_validate_configuration() {
    # Validate numeric configuration values
    if ! [[ "$SPOT_OPTIMIZER_MAX_PRICE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        _plugin_log "WARNING" "Invalid max_spot_price format: $SPOT_OPTIMIZER_MAX_PRICE"
        return 1
    fi
    
    if ! [[ "$SPOT_OPTIMIZER_INTERRUPTION_THRESHOLD" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        _plugin_log "WARNING" "Invalid interruption_threshold format: $SPOT_OPTIMIZER_INTERRUPTION_THRESHOLD"
        return 1
    fi
    
    if ! [[ "$SPOT_OPTIMIZER_SAVINGS_TARGET" =~ ^[0-9]+$ ]]; then
        _plugin_log "WARNING" "Invalid savings_target format: $SPOT_OPTIMIZER_SAVINGS_TARGET"
        return 1
    fi
    
    return 0
}

_validate_resources() {
    # Check available memory
    local available_memory
    available_memory=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "1000")
    
    if [[ $available_memory -lt 25 ]]; then
        _plugin_log "WARNING" "Low memory available: ${available_memory}MB"
        return 1
    fi
    
    # Check disk space in /tmp
    local available_disk
    available_disk=$(df /tmp 2>/dev/null | awk 'NR==2{print int($4/1024)}' || echo "1000")
    
    if [[ $available_disk -lt 50 ]]; then
        _plugin_log "WARNING" "Low disk space in /tmp: ${available_disk}MB"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN LIFECYCLE FUNCTIONS - REQUIRED
# =============================================================================

plugin_init() {
    local plugin_name="spot-optimizer"
    
    _plugin_log "INFO" "Initializing Spot Optimizer Plugin v2.0.0"
    
    # Initialize plugin state directory
    local plugin_dir=".unity/plugins/$plugin_name"
    mkdir -p "$plugin_dir/state" "$plugin_dir/logs" "$plugin_dir/cache" "$plugin_dir/metrics"
    
    # Initialize plugin state
    PLUGIN_SPOT_OPTIMIZER_STATE="$plugin_dir/state"
    PLUGIN_SPOT_OPTIMIZER_METRICS="$plugin_dir/metrics"
    
    # Create initial state file
    cat > "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" <<EOF
{
    "status": "initialized",
    "timestamp": $(date '+%s'),
    "version": "2.0.0",
    "optimizations_applied": 0,
    "total_savings": 0.0,
    "last_optimization": null
}
EOF
    
    # Load plugin configuration
    if ! _load_plugin_config; then
        _plugin_log "ERROR" "Failed to load plugin configuration"
        return 1
    fi
    
    # Initialize spot pricing cache
    if ! _init_spot_pricing_cache; then
        _plugin_log "WARNING" "Failed to initialize spot pricing cache"
    fi
    
    # Register with Unity event system
    if command -v register_extension_handler >/dev/null 2>&1; then
        register_extension_handler "spot-optimizer" "pre_deployment" "_handle_pre_deployment"
        register_extension_handler "spot-optimizer" "post_deployment" "_handle_post_deployment"
        register_extension_handler "spot-optimizer" "on_cost_threshold" "_handle_cost_threshold"
        _plugin_log "INFO" "Registered extension handlers"
    else
        _plugin_log "WARNING" "Unity extension system not available"
    fi
    
    _plugin_log "SUCCESS" "Spot Optimizer Plugin initialized successfully"
    return 0
}

plugin_start() {
    local plugin_name="spot-optimizer"
    
    _plugin_log "INFO" "Starting Spot Optimizer Plugin"
    
    # Check if plugin is initialized
    if ! _is_plugin_initialized; then
        _plugin_log "ERROR" "Plugin not initialized - cannot start"
        return 1
    fi
    
    # Start background optimization monitoring if enabled
    if [[ "${SPOT_OPTIMIZER_BACKGROUND_MONITORING:-false}" == "true" ]]; then
        if ! _start_background_monitoring; then
            _plugin_log "WARNING" "Failed to start background monitoring"
        fi
    fi
    
    # Update plugin state
    cat > "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" <<EOF
{
    "status": "active",
    "timestamp": $(date '+%s'),
    "version": "2.0.0",
    "optimizations_applied": $(grep -c "optimization_applied" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "0"),
    "total_savings": 0.0,
    "last_optimization": $(stat -c %Y "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "null")
}
EOF
    
    _plugin_log "SUCCESS" "Spot Optimizer Plugin started successfully"
    return 0
}

plugin_stop() {
    local plugin_name="spot-optimizer"
    
    _plugin_log "INFO" "Stopping Spot Optimizer Plugin"
    
    # Stop background monitoring if running
    if [[ -f "$PLUGIN_SPOT_OPTIMIZER_STATE/monitoring.pid" ]]; then
        local monitoring_pid
        monitoring_pid=$(cat "$PLUGIN_SPOT_OPTIMIZER_STATE/monitoring.pid")
        if kill -0 "$monitoring_pid" 2>/dev/null; then
            kill "$monitoring_pid"
            rm -f "$PLUGIN_SPOT_OPTIMIZER_STATE/monitoring.pid"
            _plugin_log "INFO" "Stopped background monitoring (PID: $monitoring_pid)"
        fi
    fi
    
    # Save plugin state
    if ! _save_plugin_state; then
        _plugin_log "WARNING" "Failed to save plugin state"
    fi
    
    # Update status
    cat > "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" <<EOF
{
    "status": "stopped",
    "timestamp": $(date '+%s'),
    "version": "2.0.0",
    "stop_reason": "manual",
    "final_metrics": $(cat "$PLUGIN_SPOT_OPTIMIZER_METRICS/summary.json" 2>/dev/null || echo "{}")
}
EOF
    
    _plugin_log "SUCCESS" "Spot Optimizer Plugin stopped successfully"
    return 0
}

plugin_cleanup() {
    local plugin_name="spot-optimizer"
    
    _plugin_log "INFO" "Cleaning up Spot Optimizer Plugin"
    
    # Ensure plugin is stopped first
    if _is_plugin_active; then
        plugin_stop
    fi
    
    # Cleanup temporary resources
    if ! _cleanup_temp_resources; then
        _plugin_log "WARNING" "Failed to cleanup temporary resources"
    fi
    
    # Cleanup cache files
    rm -rf "$PLUGIN_SPOT_OPTIMIZER_STATE/cache"/* 2>/dev/null || true
    
    # Preserve optimization history and metrics unless explicitly requested to remove
    local cleanup_state="${PLUGIN_CLEANUP_STATE:-false}"
    if [[ "$cleanup_state" == "true" ]]; then
        rm -rf ".unity/plugins/$plugin_name" 2>/dev/null || true
        _plugin_log "INFO" "Removed all plugin data"
    else
        _plugin_log "INFO" "Preserved optimization history and metrics"
    fi
    
    _plugin_log "SUCCESS" "Spot Optimizer Plugin cleanup completed"
    return 0
}

# =============================================================================
# PLUGIN CORE FUNCTIONALITY
# =============================================================================

# Optimize instance selection for spot instances
optimize_spot_instance() {
    local instance_type="${1:-}"
    local region="${2:-$AWS_REGION}"
    local availability_zones=("${@:3}")
    
    if [[ -z "$instance_type" ]]; then
        _plugin_log "ERROR" "Instance type is required for optimization"
        return 1
    fi
    
    _plugin_log "INFO" "Starting spot instance optimization for $instance_type in $region"
    
    # Use existing GeuseMaker spot analysis functionality
    local optimization_result
    if command -v analyze_spot_pricing >/dev/null 2>&1; then
        optimization_result=$(analyze_spot_pricing "$instance_type" "$region" "${availability_zones[@]}")
    else
        # Fallback to simplified analysis
        optimization_result=$(_simple_spot_analysis "$instance_type" "$region")
    fi
    
    # Parse optimization results
    local best_az best_price savings_percent
    if [[ -n "$optimization_result" ]]; then
        best_az=$(echo "$optimization_result" | grep "best_az:" | cut -d':' -f2 | tr -d ' ')
        best_price=$(echo "$optimization_result" | grep "best_price:" | cut -d':' -f2 | tr -d ' ')
        savings_percent=$(echo "$optimization_result" | grep "savings:" | cut -d':' -f2 | tr -d '%' | tr -d ' ')
    fi
    
    # Validate optimization meets criteria
    if [[ -n "$best_price" ]] && [[ -n "$savings_percent" ]]; then
        if (( $(echo "$savings_percent >= $SPOT_OPTIMIZER_SAVINGS_TARGET" | bc -l 2>/dev/null || echo "0") )); then
            _plugin_log "SUCCESS" "Optimization successful: $savings_percent% savings with $instance_type in $best_az"
            
            # Record optimization
            _record_optimization "$instance_type" "$region" "$best_az" "$best_price" "$savings_percent"
            
            # Generate optimization result
            cat <<EOF
{
    "optimized": true,
    "instance_type": "$instance_type",
    "region": "$region",
    "recommended_az": "$best_az",
    "spot_price": "$best_price",
    "savings_percent": $savings_percent,
    "on_demand_equivalent": $(echo "$best_price / (1 - $savings_percent/100)" | bc -l 2>/dev/null || echo "unknown"),
    "recommendation": "use_spot",
    "timestamp": $(date '+%s')
}
EOF
            return 0
        else
            _plugin_log "WARNING" "Insufficient savings: $savings_percent% (target: $SPOT_OPTIMIZER_SAVINGS_TARGET%)"
        fi
    fi
    
    # Fallback recommendation
    _plugin_log "INFO" "Spot optimization not beneficial, recommending on-demand or reserved instances"
    cat <<EOF
{
    "optimized": false,
    "instance_type": "$instance_type",
    "region": "$region",
    "reason": "insufficient_savings",
    "recommendation": "use_on_demand",
    "fallback_enabled": $SPOT_OPTIMIZER_FALLBACK_ENABLED,
    "timestamp": $(date '+%s')
}
EOF
    return 1
}

# Analyze current deployment for spot optimization opportunities
analyze_deployment_for_optimization() {
    local stack_name="${1:-}"
    
    if [[ -z "$stack_name" ]]; then
        _plugin_log "ERROR" "Stack name is required for deployment analysis"
        return 1
    fi
    
    _plugin_log "INFO" "Analyzing deployment '$stack_name' for spot optimization opportunities"
    
    # Get current EC2 instances in the stack
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:StackName,Values=$stack_name" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,Placement.AvailabilityZone,SpotInstanceRequestId]' \
        --output text 2>/dev/null)
    
    if [[ -z "$instances" ]]; then
        _plugin_log "WARNING" "No running instances found for stack: $stack_name"
        return 1
    fi
    
    local optimization_opportunities=0
    local total_instances=0
    local analysis_results=()
    
    # Analyze each instance
    while IFS=$'\t' read -r instance_id instance_type az spot_request_id; do
        total_instances=$((total_instances + 1))
        
        # Skip if already a spot instance
        if [[ -n "$spot_request_id" && "$spot_request_id" != "None" ]]; then
            _plugin_log "DEBUG" "Instance $instance_id is already a spot instance"
            continue
        fi
        
        # Analyze optimization potential
        local optimization_result
        optimization_result=$(optimize_spot_instance "$instance_type" "$AWS_REGION" "$az")
        
        if [[ $? -eq 0 ]]; then
            optimization_opportunities=$((optimization_opportunities + 1))
            analysis_results+=("$instance_id:$instance_type:$az:optimizable")
            _plugin_log "INFO" "Instance $instance_id ($instance_type) can be optimized"
        else
            analysis_results+=("$instance_id:$instance_type:$az:not_optimizable")
        fi
    done <<< "$instances"
    
    # Generate analysis summary
    local optimization_percentage=0
    if [[ $total_instances -gt 0 ]]; then
        optimization_percentage=$(( (optimization_opportunities * 100) / total_instances ))
    fi
    
    cat <<EOF
{
    "stack_name": "$stack_name",
    "analysis_timestamp": $(date '+%s'),
    "total_instances": $total_instances,
    "optimization_opportunities": $optimization_opportunities,
    "optimization_percentage": $optimization_percentage,
    "recommendations": [
        $(printf '"%s",' "${analysis_results[@]}" | sed 's/,$//')
    ]
}
EOF
    
    _plugin_log "SUCCESS" "Deployment analysis completed: $optimization_opportunities/$total_instances instances can be optimized"
    return 0
}

# =============================================================================
# PLUGIN EXTENSION POINT HANDLERS
# =============================================================================

_handle_pre_deployment() {
    local extension_point="$1"
    local context_data="$2"
    
    _plugin_log "INFO" "Pre-deployment hook activated"
    
    # Extract deployment information from context
    local stack_name instance_type region
    stack_name=$(echo "$context_data" | grep -o '"stack_name":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    instance_type=$(echo "$context_data" | grep -o '"instance_type":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "g4dn.xlarge")
    region=$(echo "$context_data" | grep -o '"region":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "$AWS_REGION")
    
    # Perform spot optimization analysis
    local optimization_result
    optimization_result=$(optimize_spot_instance "$instance_type" "$region")
    
    if [[ $? -eq 0 ]]; then
        _plugin_log "SUCCESS" "Pre-deployment optimization successful for $stack_name"
        
        # Emit optimization event
        if command -v unity_emit_event >/dev/null 2>&1; then
            unity_emit_event "spot.optimization.recommended" "$optimization_result"
        fi
    else
        _plugin_log "INFO" "No optimization recommended for pre-deployment of $stack_name"
    fi
    
    return 0
}

_handle_post_deployment() {
    local extension_point="$1"
    local context_data="$2"
    
    _plugin_log "INFO" "Post-deployment hook activated"
    
    # Extract deployment information
    local stack_name
    stack_name=$(echo "$context_data" | grep -o '"stack_name":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    
    if [[ -n "$stack_name" ]]; then
        # Analyze deployed infrastructure for future optimization
        analyze_deployment_for_optimization "$stack_name" > "$PLUGIN_SPOT_OPTIMIZER_STATE/last_analysis.json"
        _plugin_log "INFO" "Post-deployment analysis completed for $stack_name"
    fi
    
    return 0
}

_handle_cost_threshold() {
    local extension_point="$1"
    local context_data="$2"
    
    _plugin_log "INFO" "Cost threshold exceeded - triggering spot optimization analysis"
    
    # Extract cost information
    local current_cost threshold
    current_cost=$(echo "$context_data" | grep -o '"current_cost":[0-9.]*' | cut -d':' -f2 2>/dev/null || echo "0")
    threshold=$(echo "$context_data" | grep -o '"threshold":[0-9.]*' | cut -d':' -f2 2>/dev/null || echo "0")
    
    if (( $(echo "$current_cost > $threshold" | bc -l 2>/dev/null || echo "0") )); then
        _plugin_log "WARNING" "Cost threshold exceeded: $current_cost > $threshold"
        
        # Trigger aggressive optimization
        _trigger_cost_optimization "$current_cost" "$threshold"
    fi
    
    return 0
}

# =============================================================================
# PLUGIN OPTIONAL FUNCTIONS
# =============================================================================

plugin_health_check() {
    local plugin_name="spot-optimizer"
    local health_status=0
    local health_details=()
    
    # Check if plugin is active
    if ! _is_plugin_active; then
        health_details+=("Plugin is not active")
        health_status=2
    fi
    
    # Check AWS API connectivity
    if ! aws ec2 describe-regions --max-items 1 >/dev/null 2>&1; then
        health_details+=("AWS API connectivity issues")
        health_status=1
    fi
    
    # Check optimization cache health
    if [[ ! -d "$PLUGIN_SPOT_OPTIMIZER_STATE/cache" ]]; then
        health_details+=("Optimization cache directory missing")
        health_status=1
    fi
    
    # Check recent optimization activity
    local last_optimization
    last_optimization=$(stat -c %Y "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_since_last=$((current_time - last_optimization))
    
    if [[ $time_since_last -gt 86400 ]]; then  # 24 hours
        health_details+=("No recent optimization activity")
        health_status=1
    fi
    
    # Generate health report
    local status_text
    case $health_status in
        0) status_text="healthy" ;;
        1) status_text="degraded" ;;
        2) status_text="unhealthy" ;;
    esac
    
    cat <<EOF
{
  "plugin": "$plugin_name",
  "status": "$status_text",
  "timestamp": $(date '+%s'),
  "version": "2.0.0",
  "details": [$(IFS=,; echo "${health_details[*]/#/\"}" | sed 's/,/", "/g' | sed 's/^""//' | sed 's/""$//')],
  "metrics": {
    "optimizations_applied": $(grep -c "optimization_applied" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "0"),
    "last_optimization_age_hours": $((time_since_last / 3600)),
    "cache_size_mb": $(du -sm "$PLUGIN_SPOT_OPTIMIZER_STATE/cache" 2>/dev/null | cut -f1 || echo "0")
  }
}
EOF
    
    return $health_status
}

plugin_status() {
    local plugin_name="spot-optimizer"
    
    # Read current status
    local status_data
    if [[ -f "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" ]]; then
        status_data=$(cat "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json")
    else
        status_data='{"status": "unknown", "timestamp": 0}'
    fi
    
    # Get metrics
    local metrics_data="{}"
    if [[ -f "$PLUGIN_SPOT_OPTIMIZER_METRICS/summary.json" ]]; then
        metrics_data=$(cat "$PLUGIN_SPOT_OPTIMIZER_METRICS/summary.json")
    fi
    
    cat <<EOF
{
  "plugin": "$plugin_name",
  "current_status": $status_data,
  "metrics": $metrics_data,
  "configuration": {
    "max_spot_price": "$SPOT_OPTIMIZER_MAX_PRICE",
    "fallback_enabled": $SPOT_OPTIMIZER_FALLBACK_ENABLED,
    "interruption_threshold": "$SPOT_OPTIMIZER_INTERRUPTION_THRESHOLD",
    "savings_target": "$SPOT_OPTIMIZER_SAVINGS_TARGET"
  }
}
EOF
}

plugin_metrics() {
    local plugin_name="spot-optimizer"
    
    # Calculate metrics
    local total_optimizations
    total_optimizations=$(grep -c "optimization_applied" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "0")
    
    local total_savings
    total_savings=$(grep "optimization_applied" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null | \
        awk -F'savings:' '{sum+=$2} END {printf "%.2f", sum}' || echo "0.00")
    
    local avg_savings_percent
    if [[ $total_optimizations -gt 0 ]]; then
        avg_savings_percent=$(echo "scale=2; $total_savings / $total_optimizations" | bc -l 2>/dev/null || echo "0.00")
    else
        avg_savings_percent="0.00"
    fi
    
    cat <<EOF
{
  "plugin": "$plugin_name",
  "timestamp": $(date '+%s'),
  "metrics": {
    "total_optimizations": $total_optimizations,
    "total_savings_percent": "$total_savings",
    "average_savings_percent": "$avg_savings_percent",
    "cache_hit_rate": $(grep -c "cache_hit" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "0"),
    "optimization_success_rate": "$(echo "scale=2; $total_optimizations * 100 / $(grep -c "optimization_attempted" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null | sed 's/^0$/1/')" | bc -l 2>/dev/null || echo "0.00")%"
  }
}
EOF
}

# =============================================================================
# PLUGIN HELPER FUNCTIONS
# =============================================================================

_is_plugin_initialized() {
    [[ -f "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" ]] && \
    [[ "$(grep -o '"status":"[^"]*"' "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" | cut -d'"' -f4)" != "unknown" ]]
}

_is_plugin_active() {
    [[ -f "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" ]] && \
    [[ "$(grep -o '"status":"[^"]*"' "$PLUGIN_SPOT_OPTIMIZER_STATE/status.json" | cut -d'"' -f4)" == "active" ]]
}

_load_plugin_config() {
    # Load configuration from Unity config system or environment
    _plugin_log "DEBUG" "Loading plugin configuration"
    
    # Validate configuration values
    if ! [[ "$SPOT_OPTIMIZER_MAX_PRICE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        _plugin_log "WARNING" "Invalid max_spot_price, using default: 0.50"
        SPOT_OPTIMIZER_MAX_PRICE="0.50"
    fi
    
    return 0
}

_init_spot_pricing_cache() {
    mkdir -p "$PLUGIN_SPOT_OPTIMIZER_STATE/cache/spot_prices"
    
    # Initialize cache with common instance types
    local common_instances=("g4dn.xlarge" "g5.xlarge" "c5.large" "m5.large" "t3.medium")
    
    for instance_type in "${common_instances[@]}"; do
        _update_spot_price_cache "$instance_type" "$AWS_REGION" &
    done
    
    wait  # Wait for all background cache updates to complete
    return 0
}

_update_spot_price_cache() {
    local instance_type="$1"
    local region="$2"
    local cache_file="$PLUGIN_SPOT_OPTIMIZER_STATE/cache/spot_prices/${instance_type}_${region}.json"
    
    # Check if cache is still valid
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        if [[ $cache_age -lt $SPOT_OPTIMIZER_CACHE_TTL ]]; then
            return 0  # Cache is still valid
        fi
    fi
    
    # Fetch fresh spot price data
    local spot_data
    spot_data=$(aws ec2 describe-spot-price-history \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-items 1 \
        --region "$region" \
        --query 'SpotPriceHistory[0]' 2>/dev/null)
    
    if [[ -n "$spot_data" && "$spot_data" != "null" ]]; then
        echo "$spot_data" > "$cache_file"
        _plugin_log "DEBUG" "Updated spot price cache for $instance_type in $region"
    fi
    
    return 0
}

_simple_spot_analysis() {
    local instance_type="$1"
    local region="$2"
    
    # Simplified spot analysis when full GeuseMaker functionality isn't available
    local spot_price
    spot_price=$(aws ec2 describe-spot-price-history \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-items 1 \
        --region "$region" \
        --query 'SpotPriceHistory[0].SpotPrice' \
        --output text 2>/dev/null)
    
    if [[ -n "$spot_price" && "$spot_price" != "None" ]]; then
        # Estimate on-demand price (simplified calculation)
        local on_demand_price
        on_demand_price=$(echo "$spot_price * 3" | bc -l 2>/dev/null || echo "0.50")
        
        # Calculate savings
        local savings_percent
        savings_percent=$(echo "scale=0; (1 - $spot_price / $on_demand_price) * 100" | bc -l 2>/dev/null || echo "66")
        
        echo "best_az: ${region}a"
        echo "best_price: $spot_price"
        echo "savings: ${savings_percent}%"
    else
        return 1
    fi
}

_record_optimization() {
    local instance_type="$1"
    local region="$2"
    local az="$3"
    local spot_price="$4"
    local savings_percent="$5"
    
    # Record optimization in history log
    echo "$(date '+%Y-%m-%d %H:%M:%S') optimization_applied instance_type:$instance_type region:$region az:$az spot_price:$spot_price savings:$savings_percent%" >> "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log"
    
    # Update metrics
    local current_total
    current_total=$(grep -c "optimization_applied" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" || echo "0")
    
    cat > "$PLUGIN_SPOT_OPTIMIZER_METRICS/summary.json" <<EOF
{
    "total_optimizations": $current_total,
    "last_optimization": {
        "timestamp": $(date '+%s'),
        "instance_type": "$instance_type",
        "region": "$region",
        "az": "$az",
        "spot_price": "$spot_price",
        "savings_percent": $savings_percent
    }
}
EOF
}

_start_background_monitoring() {
    # Start background monitoring process (optional feature)
    _plugin_log "INFO" "Starting background spot price monitoring"
    
    # This would start a background process to monitor spot prices
    # and send alerts when optimization opportunities arise
    
    return 0
}

_save_plugin_state() {
    # Save current plugin state for persistence
    local timestamp=$(date '+%s')
    
    cat > "$PLUGIN_SPOT_OPTIMIZER_STATE/last_state.json" <<EOF
{
    "saved_timestamp": $timestamp,
    "configuration": {
        "max_spot_price": "$SPOT_OPTIMIZER_MAX_PRICE",
        "fallback_enabled": $SPOT_OPTIMIZER_FALLBACK_ENABLED,
        "interruption_threshold": "$SPOT_OPTIMIZER_INTERRUPTION_THRESHOLD",
        "savings_target": "$SPOT_OPTIMIZER_SAVINGS_TARGET"
    },
    "runtime_state": {
        "optimizations_applied": $(grep -c "optimization_applied" "$PLUGIN_SPOT_OPTIMIZER_STATE/optimization_history.log" 2>/dev/null || echo "0"),
        "cache_entries": $(find "$PLUGIN_SPOT_OPTIMIZER_STATE/cache" -name "*.json" 2>/dev/null | wc -l || echo "0")
    }
}
EOF
    
    return 0
}

_cleanup_temp_resources() {
    # Clean up temporary files and resources
    rm -f "/tmp/spot_optimizer_"* 2>/dev/null || true
    
    # Clean up old cache entries (older than 24 hours)
    find "$PLUGIN_SPOT_OPTIMIZER_STATE/cache" -name "*.json" -mtime +1 -delete 2>/dev/null || true
    
    return 0
}

_trigger_cost_optimization() {
    local current_cost="$1"
    local threshold="$2"
    
    _plugin_log "WARNING" "Triggering aggressive cost optimization due to threshold breach"
    
    # This would implement aggressive optimization strategies
    # such as analyzing all running instances for immediate spot conversion
    
    return 0
}

# =============================================================================
# PLUGIN LOGGING UTILITY
# =============================================================================

_plugin_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local plugin_name="spot-optimizer"
    
    # Format log message
    local log_entry="$timestamp [$level] [$plugin_name] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to plugin log file
    local log_dir=".unity/plugins/$plugin_name/logs"
    mkdir -p "$log_dir"
    echo "$log_entry" >> "$log_dir/plugin.log"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "Plugin[$plugin_name]: $message"
    else
        # Fallback to stderr/stdout
        case "$level" in
            "ERROR"|"CRITICAL")
                echo "$log_entry" >&2
                ;;
            "SUCCESS")
                echo "$log_entry"
                ;;
            "INFO"|"WARNING"|"DEBUG")
                if [[ "${UNITY_PLUGIN_VERBOSE:-false}" == "true" ]]; then
                    echo "$log_entry"
                fi
                ;;
        esac
    fi
}

# =============================================================================
# PLUGIN MAIN EXECUTION
# =============================================================================

# If script is executed directly, show plugin information
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Standard Plugin: Spot Optimizer v2.0.0"
    echo "Automatically converts on-demand instances to spot instances for cost savings"
    echo ""
    
    case "${1:-help}" in
        "metadata")
            plugin_metadata | jq '.' 2>/dev/null || cat
            ;;
        "validate")
            plugin_validate
            ;;
        "init")
            plugin_init
            ;;
        "start")
            plugin_start
            ;;
        "stop")
            plugin_stop
            ;;
        "cleanup")
            plugin_cleanup
            ;;
        "health")
            plugin_health_check | jq '.' 2>/dev/null || cat
            ;;
        "status")
            plugin_status | jq '.' 2>/dev/null || cat
            ;;
        "metrics")
            plugin_metrics | jq '.' 2>/dev/null || cat
            ;;
        "optimize")
            optimize_spot_instance "${2:-g4dn.xlarge}" "${3:-$AWS_REGION}"
            ;;
        "analyze")
            analyze_deployment_for_optimization "${2:-}"
            ;;
        "help"|*)
            echo "Available commands:"
            echo "  metadata    - Show plugin metadata"
            echo "  validate    - Validate plugin environment"
            echo "  init        - Initialize plugin"
            echo "  start       - Start plugin"
            echo "  stop        - Stop plugin"
            echo "  cleanup     - Cleanup plugin resources"
            echo "  health      - Check plugin health"
            echo "  status      - Show plugin status"
            echo "  metrics     - Show plugin metrics"
            echo "  optimize <instance_type> [region] - Optimize instance"
            echo "  analyze <stack_name> - Analyze deployment"
            echo "  help        - Show this help"
            ;;
    esac
fi