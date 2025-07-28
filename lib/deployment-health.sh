#!/usr/bin/env bash
#
# Deployment Health Monitoring Library
# Provides comprehensive health checks and status monitoring for deployments
#
# Dependencies: aws-cli, jq, curl
# Required Bash Version: 5.3+
#

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/core/bash_version.sh"
source "${SCRIPT_DIR}/modules/core/errors.sh"
source "${SCRIPT_DIR}/aws-cli-v2.sh"

# Health check configuration
declare -gA HEALTH_CONFIG=(
    [check_interval]=30
    [timeout]=10
    [max_retries]=3
    [enable_notifications]="true"
    [notification_webhook]=""
)

# Health status tracking
declare -gA HEALTH_STATUS=(
    [overall]="unknown"
    [stack]="unknown"
    [instances]="unknown"
    [services]="unknown"
    [network]="unknown"
    [storage]="unknown"
    [last_check]=""
)

# Service health tracking
declare -gA SERVICE_HEALTH=(
    [n8n]="unknown"
    [ollama]="unknown"
    [qdrant]="unknown"
    [crawl4ai]="unknown"
    [postgres]="unknown"
)

# Performance metrics
declare -gA PERFORMANCE_METRICS=(
    [cpu_usage]="0"
    [memory_usage]="0"
    [disk_usage]="0"
    [network_latency]="0"
)

# Initialize health monitoring
init_health_monitoring() {
    HEALTH_STATUS[last_check]=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Load webhook from parameter store if available
    if [[ -z "${HEALTH_CONFIG[notification_webhook]}" ]]; then
        local webhook
        webhook=$(aws ssm get-parameter \
            --name "/aibuildkit/WEBHOOK_URL" \
            --with-decryption \
            --output json 2>/dev/null | jq -r '.Parameter.Value // empty' || echo "")
        
        if [[ -n "$webhook" ]]; then
            HEALTH_CONFIG[notification_webhook]="$webhook"
        fi
    fi
}

# Check CloudFormation stack health
check_stack_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking CloudFormation stack health..."
    
    local stack_info
    stack_info=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null || echo '{"Stacks":[]}')
    
    local stack_status
    stack_status=$(echo "$stack_info" | jq -r '.Stacks[0].StackStatus // "NOT_FOUND"')
    
    case "$stack_status" in
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            HEALTH_STATUS[stack]="healthy"
            echo "✓ Stack status: $stack_status"
            
            # Check for drift
            check_stack_drift "$stack_name" "$region"
            ;;
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
            HEALTH_STATUS[stack]="updating"
            echo "⏳ Stack status: $stack_status"
            ;;
        "ROLLBACK_IN_PROGRESS"|"ROLLBACK_COMPLETE")
            HEALTH_STATUS[stack]="unhealthy"
            echo "✗ Stack status: $stack_status"
            
            # Get failure reason
            get_stack_failure_reason "$stack_name" "$region"
            ;;
        "NOT_FOUND")
            HEALTH_STATUS[stack]="not_found"
            echo "✗ Stack not found"
            ;;
        *)
            HEALTH_STATUS[stack]="unhealthy"
            echo "✗ Stack status: $stack_status"
            ;;
    esac
}

# Check for stack drift
check_stack_drift() {
    local stack_name="$1"
    local region="$2"
    
    echo -n "Checking for stack drift... "
    
    # Initiate drift detection
    local drift_id
    drift_id=$(aws cloudformation detect-stack-drift \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.StackDriftDetectionId // empty' || echo "")
    
    if [[ -z "$drift_id" ]]; then
        echo "unable to check"
        return
    fi
    
    # Wait for drift detection to complete (with timeout)
    local max_wait=30
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        local drift_status
        drift_status=$(aws cloudformation describe-stack-drift-detection-status \
            --stack-drift-detection-id "$drift_id" \
            --region "$region" \
            --output json 2>/dev/null | jq -r '.DetectionStatus // "UNKNOWN"')
        
        if [[ "$drift_status" == "DETECTION_COMPLETE" ]]; then
            local stack_drift_status
            stack_drift_status=$(aws cloudformation describe-stack-drift-detection-status \
                --stack-drift-detection-id "$drift_id" \
                --region "$region" \
                --output json 2>/dev/null | jq -r '.StackDriftStatus // "UNKNOWN"')
            
            case "$stack_drift_status" in
                "DRIFTED")
                    echo "⚠ Stack has drifted"
                    ;;
                "IN_SYNC")
                    echo "✓ No drift detected"
                    ;;
                *)
                    echo "status: $stack_drift_status"
                    ;;
            esac
            return
        fi
        
        sleep 2
        ((waited += 2))
    done
    
    echo "timeout"
}

# Get stack failure reason
get_stack_failure_reason() {
    local stack_name="$1"
    local region="$2"
    
    echo "Recent failure events:"
    
    aws cloudformation describe-stack-events \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | \
        jq -r '.StackEvents[] | 
            select(.ResourceStatus | contains("FAILED")) | 
            "  - \(.LogicalResourceId): \(.ResourceStatusReason)"' | \
        head -5
}

# Check EC2 instance health
check_instance_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo -e "\nChecking EC2 instance health..."
    
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Reservations[].Instances[]')
    
    if [[ -z "$instances" ]]; then
        HEALTH_STATUS[instances]="not_found"
        echo "✗ No instances found"
        return
    fi
    
    local healthy_count=0
    local total_count=0
    
    echo "$instances" | jq -c '.' | while read -r instance; do
        ((total_count++))
        
        local instance_id state status_check
        instance_id=$(echo "$instance" | jq -r '.InstanceId')
        state=$(echo "$instance" | jq -r '.State.Name')
        
        echo -n "  Instance $instance_id: "
        
        case "$state" in
            "running")
                # Check instance status
                status_check=$(aws ec2 describe-instance-status \
                    --instance-ids "$instance_id" \
                    --region "$region" \
                    --output json 2>/dev/null | \
                    jq -r '.InstanceStatuses[0].InstanceStatus.Status // "unknown"')
                
                if [[ "$status_check" == "ok" ]]; then
                    echo "✓ Running (status: OK)"
                    ((healthy_count++))
                else
                    echo "⚠ Running (status: $status_check)"
                fi
                
                # Check system metrics
                check_instance_metrics "$instance_id" "$region"
                ;;
            "pending")
                echo "⏳ Starting up"
                ;;
            "stopped"|"stopping")
                echo "✗ $state"
                ;;
            *)
                echo "✗ Unknown state: $state"
                ;;
        esac
    done
    
    if [[ $healthy_count -eq $total_count ]] && [[ $total_count -gt 0 ]]; then
        HEALTH_STATUS[instances]="healthy"
    elif [[ $healthy_count -gt 0 ]]; then
        HEALTH_STATUS[instances]="degraded"
    else
        HEALTH_STATUS[instances]="unhealthy"
    fi
    
    echo "  Summary: $healthy_count/$total_count instances healthy"
}

# Check instance metrics
check_instance_metrics() {
    local instance_id="$1"
    local region="$2"
    
    # Get CPU utilization
    local cpu_usage
    cpu_usage=$(aws cloudwatch get-metric-statistics \
        --namespace "AWS/EC2" \
        --metric-name "CPUUtilization" \
        --dimensions "Name=InstanceId,Value=$instance_id" \
        --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 300 \
        --statistics Average \
        --region "$region" \
        --output json 2>/dev/null | \
        jq -r '.Datapoints[0].Average // 0' | \
        awk '{printf "%.1f", $1}')
    
    PERFORMANCE_METRICS[cpu_usage]="$cpu_usage"
    
    echo "    CPU: ${cpu_usage}%"
}

# Check service health
check_service_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo -e "\nChecking service health..."
    
    # Get instance IP
    local instance_ip
    instance_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$stack_name" \
                  "Name=instance-state-name,Values=running" \
        --region "$region" \
        --output json 2>/dev/null | \
        jq -r '.Reservations[0].Instances[0].PublicIpAddress // empty')
    
    if [[ -z "$instance_ip" ]]; then
        echo "✗ No running instance found"
        HEALTH_STATUS[services]="unreachable"
        return
    fi
    
    local healthy_services=0
    local total_services=0
    
    # Check n8n
    echo -n "  n8n (port 5678): "
    if check_service_endpoint "http://$instance_ip:5678/healthz" "n8n"; then
        ((healthy_services++))
    fi
    ((total_services++))
    
    # Check Ollama
    echo -n "  Ollama (port 11434): "
    if check_service_endpoint "http://$instance_ip:11434/api/tags" "ollama"; then
        ((healthy_services++))
    fi
    ((total_services++))
    
    # Check Qdrant
    echo -n "  Qdrant (port 6333): "
    if check_service_endpoint "http://$instance_ip:6333/health" "qdrant"; then
        ((healthy_services++))
    fi
    ((total_services++))
    
    # Check Crawl4AI
    echo -n "  Crawl4AI (port 11235): "
    if check_service_endpoint "http://$instance_ip:11235/health" "crawl4ai"; then
        ((healthy_services++))
    fi
    ((total_services++))
    
    # Check PostgreSQL
    echo -n "  PostgreSQL (port 5432): "
    if timeout 5 bash -c "echo >/dev/tcp/$instance_ip/5432" 2>/dev/null; then
        echo "✓ Responding"
        SERVICE_HEALTH[postgres]="healthy"
        ((healthy_services++))
    else
        echo "✗ Not responding"
        SERVICE_HEALTH[postgres]="unhealthy"
    fi
    ((total_services++))
    
    # Update overall service health
    if [[ $healthy_services -eq $total_services ]]; then
        HEALTH_STATUS[services]="healthy"
    elif [[ $healthy_services -gt 0 ]]; then
        HEALTH_STATUS[services]="degraded"
    else
        HEALTH_STATUS[services]="unhealthy"
    fi
    
    echo "  Summary: $healthy_services/$total_services services healthy"
}

# Check individual service endpoint
check_service_endpoint() {
    local endpoint="$1"
    local service_name="$2"
    
    if curl -sf --max-time "${HEALTH_CONFIG[timeout]}" "$endpoint" &>/dev/null; then
        echo "✓ Responding"
        SERVICE_HEALTH[$service_name]="healthy"
        return 0
    else
        echo "✗ Not responding"
        SERVICE_HEALTH[$service_name]="unhealthy"
        return 1
    fi
}

# Check network health
check_network_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo -e "\nChecking network health..."
    
    # Get VPC info
    local vpc_id
    vpc_id=$(aws cloudformation describe-stack-resources \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | \
        jq -r '.StackResources[] | select(.ResourceType == "AWS::EC2::VPC") | .PhysicalResourceId' | \
        head -1)
    
    if [[ -z "$vpc_id" ]]; then
        echo "✗ VPC not found"
        HEALTH_STATUS[network]="not_found"
        return
    fi
    
    echo "  VPC: $vpc_id"
    
    # Check subnets
    echo -n "  Subnets: "
    local subnet_count
    subnet_count=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --output json 2>/dev/null | jq '.Subnets | length')
    
    if [[ $subnet_count -gt 0 ]]; then
        echo "✓ $subnet_count found"
    else
        echo "✗ None found"
    fi
    
    # Check internet gateway
    echo -n "  Internet Gateway: "
    local igw_count
    igw_count=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --region "$region" \
        --output json 2>/dev/null | jq '.InternetGateways | length')
    
    if [[ $igw_count -gt 0 ]]; then
        echo "✓ Attached"
    else
        echo "✗ Not found"
    fi
    
    # Check security groups
    echo -n "  Security Groups: "
    local sg_count
    sg_count=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --output json 2>/dev/null | jq '.SecurityGroups | length')
    
    echo "✓ $sg_count configured"
    
    # Overall network health
    if [[ $subnet_count -gt 0 ]] && [[ $igw_count -gt 0 ]]; then
        HEALTH_STATUS[network]="healthy"
    else
        HEALTH_STATUS[network]="unhealthy"
    fi
}

# Check storage health
check_storage_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo -e "\nChecking storage health..."
    
    # Check EFS
    local efs_id
    efs_id=$(aws cloudformation describe-stack-resources \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | \
        jq -r '.StackResources[] | select(.ResourceType == "AWS::EFS::FileSystem") | .PhysicalResourceId' | \
        head -1)
    
    if [[ -n "$efs_id" ]]; then
        echo -n "  EFS ($efs_id): "
        
        local efs_status
        efs_status=$(aws efs describe-file-systems \
            --file-system-id "$efs_id" \
            --region "$region" \
            --output json 2>/dev/null | \
            jq -r '.FileSystems[0].LifeCycleState // "unknown"')
        
        if [[ "$efs_status" == "available" ]]; then
            echo "✓ Available"
            
            # Check mount targets
            echo -n "    Mount targets: "
            local mount_count
            mount_count=$(aws efs describe-mount-targets \
                --file-system-id "$efs_id" \
                --region "$region" \
                --output json 2>/dev/null | \
                jq '.MountTargets | length')
            
            echo "$mount_count active"
        else
            echo "✗ Status: $efs_status"
        fi
    else
        echo "  EFS: Not configured"
    fi
    
    # Check instance storage
    check_instance_storage "$stack_name" "$region"
    
    # Overall storage health
    if [[ "$efs_status" == "available" ]] || [[ -z "$efs_id" ]]; then
        HEALTH_STATUS[storage]="healthy"
    else
        HEALTH_STATUS[storage]="unhealthy"
    fi
}

# Check instance storage
check_instance_storage() {
    local stack_name="$1"
    local region="$2"
    
    # Get instance IDs
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$stack_name" \
                  "Name=instance-state-name,Values=running" \
        --region "$region" \
        --output json 2>/dev/null | \
        jq -r '.Reservations[].Instances[].InstanceId')
    
    if [[ -z "$instance_ids" ]]; then
        return
    fi
    
    echo "  Instance storage:"
    
    # Check disk usage via CloudWatch (if custom metrics are available)
    # This is a placeholder - actual implementation would need CloudWatch agent
    echo "    Disk usage: Monitoring not configured"
}

# Perform comprehensive health check
perform_health_check() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "===================================================="
    echo "Deployment Health Check"
    echo "Stack: $stack_name"
    echo "Region: $region"
    echo "Time: $(date)"
    echo "===================================================="
    
    # Initialize
    init_health_monitoring
    
    # Run all health checks
    check_stack_health "$stack_name" "$region"
    check_instance_health "$stack_name" "$region"
    check_service_health "$stack_name" "$region"
    check_network_health "$stack_name" "$region"
    check_storage_health "$stack_name" "$region"
    
    # Determine overall health
    local unhealthy_count=0
    local degraded_count=0
    
    for component in stack instances services network storage; do
        case "${HEALTH_STATUS[$component]}" in
            "unhealthy"|"not_found")
                ((unhealthy_count++))
                ;;
            "degraded"|"updating")
                ((degraded_count++))
                ;;
        esac
    done
    
    if [[ $unhealthy_count -eq 0 ]] && [[ $degraded_count -eq 0 ]]; then
        HEALTH_STATUS[overall]="healthy"
    elif [[ $unhealthy_count -eq 0 ]]; then
        HEALTH_STATUS[overall]="degraded"
    else
        HEALTH_STATUS[overall]="unhealthy"
    fi
    
    # Update last check time
    HEALTH_STATUS[last_check]=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Display summary
    display_health_summary
    
    # Send notifications if configured
    if [[ "${HEALTH_CONFIG[enable_notifications]}" == "true" ]] && \
       [[ "${HEALTH_STATUS[overall]}" != "healthy" ]]; then
        send_health_notification
    fi
    
    # Generate report
    generate_health_report "health-report-$(date +%Y%m%d-%H%M%S).json"
    
    # Return based on overall health
    [[ "${HEALTH_STATUS[overall]}" == "healthy" ]]
}

# Display health summary
display_health_summary() {
    echo -e "\n===================================================="
    echo "Health Summary"
    echo "===================================================="
    
    local status_icon
    local status_color
    
    for component in overall stack instances services network storage; do
        case "${HEALTH_STATUS[$component]}" in
            "healthy")
                status_icon="✓"
                status_color="\033[0;32m"  # Green
                ;;
            "degraded"|"updating")
                status_icon="⚠"
                status_color="\033[0;33m"  # Yellow
                ;;
            "unhealthy"|"not_found")
                status_icon="✗"
                status_color="\033[0;31m"  # Red
                ;;
            *)
                status_icon="?"
                status_color="\033[0;37m"  # Gray
                ;;
        esac
        
        printf "%-15s ${status_color}%s %s\033[0m\n" \
            "${component^}:" "$status_icon" "${HEALTH_STATUS[$component]}"
    done
    
    echo -e "\nService Status:"
    for service in n8n ollama qdrant crawl4ai postgres; do
        case "${SERVICE_HEALTH[$service]}" in
            "healthy")
                status_icon="✓"
                status_color="\033[0;32m"
                ;;
            "unhealthy")
                status_icon="✗"
                status_color="\033[0;31m"
                ;;
            *)
                status_icon="?"
                status_color="\033[0;37m"
                ;;
        esac
        
        printf "  %-12s ${status_color}%s %s\033[0m\n" \
            "${service^}:" "$status_icon" "${SERVICE_HEALTH[$service]}"
    done
    
    echo "===================================================="
}

# Send health notification
send_health_notification() {
    local webhook="${HEALTH_CONFIG[notification_webhook]}"
    
    if [[ -z "$webhook" ]]; then
        return
    fi
    
    local message
    message=$(jq -n \
        --arg status "${HEALTH_STATUS[overall]}" \
        --arg stack "$1" \
        --arg time "${HEALTH_STATUS[last_check]}" \
        --argjson health "$(declare -p HEALTH_STATUS | sed 's/^declare -[aA] //' | jq -R . | jq -s 'add')" \
        '{
            text: "Deployment Health Alert",
            status: $status,
            stack: $stack,
            timestamp: $time,
            details: $health
        }')
    
    curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "$message" \
        "$webhook" &>/dev/null || true
}

# Generate health report
generate_health_report() {
    local output_file="${1:-health-report.json}"
    
    local report_data
    report_data=$(jq -n \
        --argjson health "$(printf '%s\n' "${!HEALTH_STATUS[@]}" | jq -R . | jq -s 'map(. as $k | {($k): $HEALTH_STATUS[$k]}) | add')" \
        --argjson services "$(printf '%s\n' "${!SERVICE_HEALTH[@]}" | jq -R . | jq -s 'map(. as $k | {($k): $SERVICE_HEALTH[$k]}) | add')" \
        --argjson metrics "$(printf '%s\n' "${!PERFORMANCE_METRICS[@]}" | jq -R . | jq -s 'map(. as $k | {($k): $PERFORMANCE_METRICS[$k]}) | add')" \
        --arg timestamp "${HEALTH_STATUS[last_check]}" \
        '{
            timestamp: $timestamp,
            health_status: $health,
            service_health: $services,
            performance_metrics: $metrics
        }')
    
    echo "$report_data" > "$output_file"
    echo -e "\nHealth report saved to: $output_file"
}

# Continuous health monitoring
monitor_deployment_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    local duration="${3:-3600}"  # Default 1 hour
    
    echo "Starting continuous health monitoring for $duration seconds"
    echo "Press Ctrl+C to stop"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        perform_health_check "$stack_name" "$region"
        
        # Wait for next check
        echo -e "\nNext check in ${HEALTH_CONFIG[check_interval]} seconds..."
        sleep "${HEALTH_CONFIG[check_interval]}"
    done
    
    echo "Monitoring completed"
}

# Export functions
export -f init_health_monitoring
export -f check_stack_health
export -f check_instance_health
export -f check_service_health
export -f check_network_health
export -f check_storage_health
export -f perform_health_check
export -f monitor_deployment_health
export -f generate_health_report
export -f display_health_summary