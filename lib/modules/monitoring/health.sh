#!/usr/bin/env bash
# =============================================================================
# Health Check and Monitoring Module
# Provides health checks and monitoring capabilities
# =============================================================================

# Prevent multiple sourcing
[ -n "${_HEALTH_SH_LOADED:-}" ] && return 0
_HEALTH_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../compute/launch.sh"

# =============================================================================
# HEALTH CHECK TYPES
# =============================================================================

# Check instance health
check_instance_health() {
    local instance_id="$1"
    local checks="${2:-all}"  # all, ssh, http, services
    
    echo "Running health checks for instance: $instance_id" >&2
    
    local health_status=0
    local health_report=""
    
    # Get instance details
    local instance_info
    instance_info=$(get_instance_details "$instance_id") || {
        throw_error $ERROR_AWS_API "Failed to get instance details"
    }
    
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIpAddress')
    local state=$(echo "$instance_info" | jq -r '.State')
    
    # Check instance state
    if [ "$state" != "running" ]; then
        health_report+="Instance State: FAILED (state: $state)\n"
        health_status=1
    else
        health_report+="Instance State: OK (running)\n"
    fi
    
    # Run specific checks
    case "$checks" in
        all)
            check_ssh_health "$instance_id" "$public_ip" || health_status=1
            check_http_health "$public_ip" || health_status=1
            check_service_health "$instance_id" "$public_ip" || health_status=1
            ;;
        ssh)
            check_ssh_health "$instance_id" "$public_ip" || health_status=1
            ;;
        http)
            check_http_health "$public_ip" || health_status=1
            ;;
        services)
            check_service_health "$instance_id" "$public_ip" || health_status=1
            ;;
    esac
    
    # Print report
    echo -e "\n=== Health Check Report ===" >&2
    echo -e "$health_report" >&2
    echo "==========================" >&2
    
    return $health_status
}

# Check SSH connectivity
check_ssh_health() {
    local instance_id="$1"
    local public_ip="$2"
    
    echo "Checking SSH connectivity..." >&2
    
    # Get key file
    local key_name=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].KeyName' \
        --output text)
    
    local key_file="$HOME/.ssh/${key_name}.pem"
    
    if [ ! -f "$key_file" ]; then
        health_report+="SSH Health: FAILED (key file not found: $key_file)\n"
        return 1
    fi
    
    # Test SSH connection
    if ssh -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           -i "$key_file" \
           ubuntu@"$public_ip" \
           "echo 'SSH test successful'" &>/dev/null; then
        health_report+="SSH Health: OK\n"
        return 0
    else
        health_report+="SSH Health: FAILED\n"
        return 1
    fi
}

# Check HTTP endpoint health
check_http_health() {
    local public_ip="$1"
    local port="${2:-8080}"
    local endpoint="${3:-/health}"
    
    echo "Checking HTTP health endpoint..." >&2
    
    # Check health endpoint
    local response
    response=$(curl -s -f -m 10 "http://${public_ip}:${port}${endpoint}" 2>/dev/null) || {
        health_report+="HTTP Health: FAILED (no response from ${public_ip}:${port}${endpoint})\n"
        return 1
    }
    
    # Parse response
    local status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "unknown")
    
    if [ "$status" = "healthy" ]; then
        health_report+="HTTP Health: OK\n"
        return 0
    else
        health_report+="HTTP Health: FAILED (status: $status)\n"
        return 1
    fi
}

# Check service health
check_service_health() {
    local instance_id="$1"
    local public_ip="$2"
    
    echo "Checking service health..." >&2
    
    # Define services to check
    local services=(
        "n8n:5678:/healthz"
        "qdrant:6333:/health"
        "ollama:11434:/api/health"
        "crawl4ai:11235:/health"
    )
    
    local all_healthy=true
    
    for service_spec in "${services[@]}"; do
        IFS=':' read -r service port endpoint <<< "$service_spec"
        
        echo "Checking $service..." >&2
        
        # Skip if service is disabled
        local enable_var="${service^^}_ENABLE"
        if [ "${!enable_var}" = "false" ]; then
            health_report+="Service $service: SKIPPED (disabled)\n"
            continue
        fi
        
        # Check service endpoint
        if curl -s -f -m 5 "http://${public_ip}:${port}${endpoint}" &>/dev/null; then
            health_report+="Service $service: OK\n"
        else
            health_report+="Service $service: FAILED\n"
            all_healthy=false
        fi
    done
    
    [ "$all_healthy" = "true" ] && return 0 || return 1
}

# =============================================================================
# MONITORING SETUP
# =============================================================================

# Setup CloudWatch monitoring
setup_cloudwatch_monitoring() {
    local stack_name="${1:-$STACK_NAME}"
    local instance_id="$2"
    
    echo "Setting up CloudWatch monitoring for: $instance_id" >&2
    
    # Create CloudWatch dashboard
    create_cloudwatch_dashboard "$stack_name" "$instance_id"
    
    # Create alarms
    create_cloudwatch_alarms "$stack_name" "$instance_id"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    local stack_name="$1"
    local instance_id="$2"
    
    local dashboard_body=$(cat <<EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "CPUUtilization", { "stat": "Average" } ],
                    [ ".", "NetworkIn", { "stat": "Sum" } ],
                    [ ".", "NetworkOut", { "stat": "Sum" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "EC2 Instance Metrics",
                "dimensions": {
                    "InstanceId": "$instance_id"
                }
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AIStarterKit/$stack_name", "utilization_gpu", { "stat": "Average" } ],
                    [ ".", "utilization_memory", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "GPU Metrics"
            }
        }
    ]
}
EOF
)
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${stack_name}-dashboard" \
        --dashboard-body "$dashboard_body" || {
        echo "Failed to create CloudWatch dashboard" >&2
    }
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    local stack_name="$1"
    local instance_id="$2"
    
    # CPU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-cpu-high" \
        --alarm-description "CPU utilization is too high" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --evaluation-periods 2 || {
        echo "Failed to create CPU alarm" >&2
    }
    
    # Instance status check alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-instance-status" \
        --alarm-description "Instance status check failed" \
        --metric-name StatusCheckFailed \
        --namespace AWS/EC2 \
        --statistic Maximum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --evaluation-periods 2 || {
        echo "Failed to create status check alarm" >&2
    }
}

# =============================================================================
# LOG COLLECTION
# =============================================================================

# Collect logs from instance
collect_instance_logs() {
    local instance_id="$1"
    local output_dir="${2:-./logs}"
    
    echo "Collecting logs from instance: $instance_id" >&2
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Get instance details
    local public_ip
    public_ip=$(get_instance_public_ip "$instance_id") || {
        echo "Failed to get instance IP" >&2
        return 1
    }
    
    # Get key file
    local key_name=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].KeyName' \
        --output text)
    
    local key_file="$HOME/.ssh/${key_name}.pem"
    
    if [ ! -f "$key_file" ]; then
        echo "SSH key not found: $key_file" >&2
        return 1
    fi
    
    # Define logs to collect
    local logs=(
        "/var/log/user-data.log"
        "/var/log/cloud-init.log"
        "/var/log/cloud-init-output.log"
        "/var/log/syslog"
        "/home/ubuntu/ai-starter-kit/docker-compose.yml"
    )
    
    # Collect logs
    for log in "${logs[@]}"; do
        local log_name=$(basename "$log")
        echo "Collecting: $log" >&2
        
        scp -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -i "$key_file" \
            "ubuntu@${public_ip}:${log}" \
            "${output_dir}/${log_name}" 2>/dev/null || {
            echo "Failed to collect: $log" >&2
        }
    done
    
    # Collect Docker logs
    echo "Collecting Docker logs..." >&2
    
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -i "$key_file" \
        ubuntu@"$public_ip" \
        "cd /home/ubuntu/ai-starter-kit && docker-compose logs" \
        > "${output_dir}/docker-compose.log" 2>&1 || {
        echo "Failed to collect Docker logs" >&2
    }
    
    echo "Logs collected in: $output_dir" >&2
}

# =============================================================================
# PERFORMANCE METRICS
# =============================================================================

# Get performance metrics
get_performance_metrics() {
    local instance_id="$1"
    local duration="${2:-3600}"  # 1 hour default
    
    echo "Getting performance metrics for: $instance_id" >&2
    
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -d "$duration seconds ago" +%Y-%m-%dT%H:%M:%S)
    
    # Get CPU metrics
    local cpu_stats
    cpu_stats=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --statistics Average,Maximum \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300)
    
    # Get network metrics
    local network_in
    network_in=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name NetworkIn \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --statistics Sum \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300)
    
    # Build metrics report
    cat <<EOF
{
    "instance_id": "$instance_id",
    "period": {
        "start": "$start_time",
        "end": "$end_time"
    },
    "metrics": {
        "cpu": $cpu_stats,
        "network_in": $network_in
    }
}
EOF
}