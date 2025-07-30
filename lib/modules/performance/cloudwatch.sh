#!/bin/bash
# performance/cloudwatch.sh - CloudWatch dashboard and metrics configuration

# CloudWatch configuration
declare -g CW_NAMESPACE="${CW_NAMESPACE:-GeuseMaker/Performance}"
declare -g CW_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
declare -g CW_DASHBOARD_NAME="${CW_DASHBOARD_NAME:-GeuseMaker-Performance}"

# Create CloudWatch dashboard for performance monitoring
create_performance_dashboard() {
    local stack_name="${1:-default}"
    
    log_info "Creating CloudWatch performance dashboard..."
    
    # Dashboard JSON definition
    local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CW_NAMESPACE", "DeploymentDuration", { "stat": "Average", "label": "Avg Deployment Time" } ],
                    [ "...", { "stat": "Maximum", "label": "Max Deployment Time" } ],
                    [ "...", { "stat": "Minimum", "label": "Min Deployment Time" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$CW_REGION",
                "title": "Deployment Performance",
                "yAxis": {
                    "left": {
                        "label": "Seconds"
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CW_NAMESPACE", "PeakMemoryUsage", { "stat": "Average" } ],
                    [ "...", { "stat": "Maximum" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$CW_REGION",
                "title": "Memory Usage",
                "yAxis": {
                    "left": {
                        "label": "Megabytes"
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CW_NAMESPACE", "ScriptLoadTime", { "stat": "Average" } ],
                    [ "$CW_NAMESPACE", "StartupTime", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$CW_REGION",
                "title": "Startup Performance",
                "yAxis": {
                    "left": {
                        "label": "Seconds"
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CW_NAMESPACE", "APICallCount", { "stat": "Sum", "label": "Total API Calls" } ],
                    [ "$CW_NAMESPACE", "CacheHitRate", { "stat": "Average", "label": "Cache Hit Rate %" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$CW_REGION",
                "title": "API and Cache Performance"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 12,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CW_NAMESPACE", "ParallelJobsCompleted", { "stat": "Sum" } ],
                    [ "$CW_NAMESPACE", "ParallelJobsFailed", { "stat": "Sum" } ],
                    [ "$CW_NAMESPACE", "ParallelSpeedup", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$CW_REGION",
                "title": "Parallel Execution Performance"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 12,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CW_NAMESPACE", "SpotPriceQueryTime", { "stat": "Average" } ],
                    [ "$CW_NAMESPACE", "EC2LaunchTime", { "stat": "Average" } ],
                    [ "$CW_NAMESPACE", "EFSMountTime", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$CW_REGION",
                "title": "AWS Resource Performance",
                "yAxis": {
                    "left": {
                        "label": "Seconds"
                    }
                }
            }
        }
    ]
}
EOF
)
    
    # Create or update dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$CW_DASHBOARD_NAME" \
        --dashboard-body "$dashboard_body" \
        --region "$CW_REGION" \
        2>/dev/null || {
            log_error "Failed to create CloudWatch dashboard"
            return 1
        }
    
    log_success "CloudWatch dashboard created: $CW_DASHBOARD_NAME"
    
    # Output dashboard URL
    local dashboard_url="https://${CW_REGION}.console.aws.amazon.com/cloudwatch/home?region=${CW_REGION}#dashboards:name=${CW_DASHBOARD_NAME}"
    log_info "Dashboard URL: $dashboard_url"
}

# Send metric to CloudWatch
send_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-None}"
    local dimensions="${4:-}"
    
    local metric_data="MetricName=$metric_name,Value=$value,Unit=$unit"
    
    if [[ -n "$dimensions" ]]; then
        metric_data+=",Dimensions=$dimensions"
    fi
    
    aws cloudwatch put-metric-data \
        --namespace "$CW_NAMESPACE" \
        --metric-data "$metric_data" \
        --region "$CW_REGION" \
        2>/dev/null || {
            log_debug "Failed to send metric $metric_name"
            return 1
        }
}

# Send performance metrics to CloudWatch
send_performance_metrics() {
    local stack_name="${1:-default}"
    
    log_debug "Sending performance metrics to CloudWatch..."
    
    # Dimensions for all metrics
    local dimensions="Name=Stack,Value=$stack_name"
    
    # Parse metrics from performance monitoring
    if [[ -f "$PERF_METRICS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        # Deployment duration
        local deployment_duration=$(jq -r '.phases.deployment_duration // 0' "$PERF_METRICS_FILE")
        [[ "$deployment_duration" != "0" ]] && send_metric "DeploymentDuration" "$deployment_duration" "Seconds" "$dimensions"
        
        # Memory usage
        local peak_memory=$(jq -r '.memory.peak_mb // 0' "$PERF_METRICS_FILE")
        [[ "$peak_memory" != "0" ]] && send_metric "PeakMemoryUsage" "$peak_memory" "Megabytes" "$dimensions"
        
        # Startup time
        local startup_time=$(jq -r '.phases.startup_duration // 0' "$PERF_METRICS_FILE")
        [[ "$startup_time" != "0" ]] && send_metric "StartupTime" "$startup_time" "Seconds" "$dimensions"
        
        # API call count
        local api_calls=$(jq -r '[.api_calls[].count // 0] | add // 0' "$PERF_METRICS_FILE")
        [[ "$api_calls" != "0" ]] && send_metric "APICallCount" "$api_calls" "Count" "$dimensions"
    fi
    
    # Cache metrics
    local cache_hit_rate=$(cache_calculate_hit_rate)
    [[ -n "$cache_hit_rate" ]] && send_metric "CacheHitRate" "$cache_hit_rate" "Percent" "$dimensions"
    
    # Parallel execution metrics
    send_parallel_metrics "$dimensions"
}

# Send parallel execution metrics
send_parallel_metrics() {
    local dimensions="$1"
    
    # Extract metrics from parallel stats
    local stats_output=$(parallel_stats 2>&1)
    
    # Parse completed jobs
    local completed=$(echo "$stats_output" | grep "Completed:" | awk '{print $2}')
    [[ -n "$completed" ]] && send_metric "ParallelJobsCompleted" "$completed" "Count" "$dimensions"
    
    # Parse failed jobs
    local failed=$(echo "$stats_output" | grep "Failed:" | awk '{print $2}')
    [[ -n "$failed" ]] && send_metric "ParallelJobsFailed" "$failed" "Count" "$dimensions"
    
    # Parse speedup
    local speedup=$(echo "$stats_output" | grep "Speedup:" | awk '{print $2}' | tr -d 'x')
    [[ -n "$speedup" ]] && [[ "$speedup" != "N/A" ]] && send_metric "ParallelSpeedup" "$speedup" "None" "$dimensions"
}

# Create CloudWatch alarms for performance
create_performance_alarms() {
    local stack_name="${1:-default}"
    local sns_topic="${2:-}"
    
    log_info "Creating CloudWatch alarms for performance monitoring..."
    
    # Alarm for slow deployments
    create_alarm "SlowDeployment-$stack_name" \
        "DeploymentDuration" \
        "GreaterThanThreshold" \
        "180" \
        "Deployment taking longer than 3 minutes" \
        "$sns_topic"
    
    # Alarm for high memory usage
    create_alarm "HighMemoryUsage-$stack_name" \
        "PeakMemoryUsage" \
        "GreaterThanThreshold" \
        "100" \
        "Memory usage exceeding 100MB" \
        "$sns_topic"
    
    # Alarm for low cache hit rate
    create_alarm "LowCacheHitRate-$stack_name" \
        "CacheHitRate" \
        "LessThanThreshold" \
        "50" \
        "Cache hit rate below 50%" \
        "$sns_topic"
    
    # Alarm for high failure rate
    create_alarm "HighFailureRate-$stack_name" \
        "ParallelJobsFailed" \
        "GreaterThanThreshold" \
        "10" \
        "More than 10 parallel jobs failed" \
        "$sns_topic"
    
    log_success "Performance alarms created"
}

# Create individual alarm
create_alarm() {
    local alarm_name="$1"
    local metric_name="$2"
    local comparison_operator="$3"
    local threshold="$4"
    local description="$5"
    local sns_topic="$6"
    
    local alarm_actions=""
    if [[ -n "$sns_topic" ]]; then
        alarm_actions="--alarm-actions $sns_topic"
    fi
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "$description" \
        --metric-name "$metric_name" \
        --namespace "$CW_NAMESPACE" \
        --statistic Average \
        --period 300 \
        --evaluation-periods 2 \
        --threshold "$threshold" \
        --comparison-operator "$comparison_operator" \
        --region "$CW_REGION" \
        $alarm_actions \
        2>/dev/null || {
            log_debug "Failed to create alarm $alarm_name"
            return 1
        }
}

# Query CloudWatch metrics
query_performance_metrics() {
    local stack_name="${1:-default}"
    local start_time="${2:-1h}"  # Default to last hour
    local metric_name="${3:-}"
    
    log_info "Querying performance metrics from CloudWatch..."
    
    # Calculate time range
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time_calc
    case "$start_time" in
        *h)
            hours="${start_time%h}"
            start_time_calc=$(date -u -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
                             date -u -v-${hours}H +%Y-%m-%dT%H:%M:%S)
            ;;
        *d)
            days="${start_time%d}"
            start_time_calc=$(date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
                             date -u -v-${days}d +%Y-%m-%dT%H:%M:%S)
            ;;
        *)
            start_time_calc="$start_time"
            ;;
    esac
    
    # Query specific metric or all metrics
    if [[ -n "$metric_name" ]]; then
        query_single_metric "$metric_name" "$start_time_calc" "$end_time" "$stack_name"
    else
        # Query all key metrics
        local metrics=("DeploymentDuration" "PeakMemoryUsage" "CacheHitRate" "APICallCount")
        for metric in "${metrics[@]}"; do
            query_single_metric "$metric" "$start_time_calc" "$end_time" "$stack_name"
        done
    fi
}

# Query single metric
query_single_metric() {
    local metric_name="$1"
    local start_time="$2"
    local end_time="$3"
    local stack_name="$4"
    
    local result=$(aws cloudwatch get-metric-statistics \
        --namespace "$CW_NAMESPACE" \
        --metric-name "$metric_name" \
        --dimensions Name=Stack,Value="$stack_name" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average,Maximum,Minimum \
        --region "$CW_REGION" \
        --output json 2>/dev/null)
    
    if [[ -n "$result" ]] && [[ "$result" != "null" ]]; then
        echo "Metric: $metric_name"
        echo "$result" | jq -r '.Datapoints | sort_by(.Timestamp) | .[] | "\(.Timestamp): Avg=\(.Average), Max=\(.Maximum), Min=\(.Minimum)"'
        echo ""
    fi
}

# Generate performance insights
generate_performance_insights() {
    local stack_name="${1:-default}"
    
    log_info "Generating performance insights..."
    
    # Query recent metrics
    local metrics_data=$(query_performance_metrics "$stack_name" "24h")
    
    # Analyze patterns
    echo "=== Performance Insights ==="
    echo "Stack: $stack_name"
    echo "Analysis Period: Last 24 hours"
    echo ""
    
    # Deployment performance
    echo "Deployment Performance:"
    local avg_deployment=$(aws cloudwatch get-metric-statistics \
        --namespace "$CW_NAMESPACE" \
        --metric-name "DeploymentDuration" \
        --dimensions Name=Stack,Value="$stack_name" \
        --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 86400 \
        --statistics Average \
        --region "$CW_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ -n "$avg_deployment" ]] && [[ "$avg_deployment" != "None" ]]; then
        echo "  Average deployment time: ${avg_deployment}s"
        if (( $(echo "$avg_deployment > 180" | bc -l) )); then
            echo "  ⚠️  Deployments are taking longer than target (3 minutes)"
            echo "  Recommendations:"
            echo "    - Enable aggressive optimization mode"
            echo "    - Increase parallel job limits"
            echo "    - Pre-warm caches before deployment"
        fi
    fi
    
    # Memory performance
    echo ""
    echo "Memory Performance:"
    local avg_memory=$(aws cloudwatch get-metric-statistics \
        --namespace "$CW_NAMESPACE" \
        --metric-name "PeakMemoryUsage" \
        --dimensions Name=Stack,Value="$stack_name" \
        --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 86400 \
        --statistics Average \
        --region "$CW_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ -n "$avg_memory" ]] && [[ "$avg_memory" != "None" ]]; then
        echo "  Average peak memory: ${avg_memory}MB"
        if (( $(echo "$avg_memory > 100" | bc -l) )); then
            echo "  ⚠️  Memory usage exceeding target (100MB)"
            echo "  Recommendations:"
            echo "    - Enable memory optimization"
            echo "    - Implement array size limits"
            echo "    - Clear large variables after use"
        fi
    fi
    
    # Cache performance
    echo ""
    echo "Cache Performance:"
    local cache_hit_rate=$(aws cloudwatch get-metric-statistics \
        --namespace "$CW_NAMESPACE" \
        --metric-name "CacheHitRate" \
        --dimensions Name=Stack,Value="$stack_name" \
        --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 86400 \
        --statistics Average \
        --region "$CW_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ -n "$cache_hit_rate" ]] && [[ "$cache_hit_rate" != "None" ]]; then
        echo "  Average cache hit rate: ${cache_hit_rate}%"
        if (( $(echo "$cache_hit_rate < 70" | bc -l) )); then
            echo "  ⚠️  Cache hit rate below optimal (70%)"
            echo "  Recommendations:"
            echo "    - Increase cache size"
            echo "    - Extend cache TTL for stable data"
            echo "    - Pre-warm caches with common queries"
        fi
    fi
}

# Export CloudWatch functions
export -f create_performance_dashboard
export -f send_metric
export -f send_performance_metrics
export -f create_performance_alarms
export -f query_performance_metrics
export -f generate_performance_insights