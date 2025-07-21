#!/bin/bash

# =============================================================================
# AI Starter Kit - Comprehensive Deployment Validator
# =============================================================================
# Validates all aspects of deployed AI infrastructure on AWS
# Features: Service health, SSH connectivity, GPU functionality, EFS mounting,
# Docker health, security groups, CloudWatch monitoring, diagnostics
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VALIDATION_TIMEOUT=300  # 5 minutes for comprehensive validation
SSH_TIMEOUT=30
SERVICE_TIMEOUT=60

# Validation results tracking
VALIDATION_RESULTS=()
FAILED_CHECKS=()
WARNING_CHECKS=()
PASSED_CHECKS=()

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}"
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
    PASSED_CHECKS+=("$*")
}

warning() {
    echo -e "${YELLOW}⚠ $*${NC}"
    WARNING_CHECKS+=("$*")
}

error() {
    echo -e "${RED}✗ $*${NC}"
    FAILED_CHECKS+=("$*")
}

info() {
    echo -e "${CYAN}ℹ $*${NC}"
}

separator() {
    echo -e "${PURPLE}$1${NC}"
}

# Timeout wrapper for commands
run_with_timeout() {
    local timeout="$1"
    shift
    timeout "$timeout" "$@" 2>/dev/null || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            error "Command timed out after ${timeout}s: $*"
        else
            error "Command failed with exit code $exit_code: $*"
        fi
        return $exit_code
    }
}

# SSH command wrapper
ssh_exec() {
    local instance_ip="$1"
    local command="$2"
    local timeout="${3:-$SSH_TIMEOUT}"
    
    run_with_timeout "$timeout" ssh -i "${KEY_NAME}.pem" \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        ubuntu@"$instance_ip" "$command"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_prerequisites() {
    separator "=== VALIDATING PREREQUISITES ==="
    
    # Check required files
    if [[ -f "${KEY_NAME}.pem" ]]; then
        success "SSH key file found: ${KEY_NAME}.pem"
        chmod 600 "${KEY_NAME}.pem"
    else
        error "SSH key file not found: ${KEY_NAME}.pem"
        return 1
    fi
    
    # Check AWS CLI
    if command -v aws >/dev/null 2>&1; then
        success "AWS CLI is available"
        local aws_identity=$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null || echo "ERROR")
        if [[ "$aws_identity" != "ERROR" ]]; then
            success "AWS credentials are valid (Account: $aws_identity)"
        else
            error "AWS credentials are invalid or not configured"
            return 1
        fi
    else
        error "AWS CLI not found"
        return 1
    fi
    
    # Check jq availability
    if command -v jq >/dev/null 2>&1; then
        success "jq is available for JSON processing"
    else
        warning "jq not found - some advanced validations may be limited"
    fi
    
    return 0
}

validate_infrastructure() {
    local instance_ip="$1"
    separator "=== VALIDATING INFRASTRUCTURE ==="
    
    # Validate CloudFormation stack
    log "Checking CloudFormation stack status..."
    local stack_status=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME:-ai-starter-kit}" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]]; then
        success "CloudFormation stack is in healthy state: $stack_status"
    else
        error "CloudFormation stack is not healthy: $stack_status"
        return 1
    fi
    
    # Validate EC2 instance
    log "Checking EC2 instance status..."
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$instance_ip" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$instance_id" != "None" && "$instance_id" != "" ]]; then
        success "EC2 instance is running: $instance_id"
        
        # Get instance details
        local instance_type=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].InstanceType' \
            --output text 2>/dev/null)
        local availability_zone=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
            --output text 2>/dev/null)
        
        info "Instance Type: $instance_type"
        info "Availability Zone: $availability_zone"
        
        # Check if it's a spot instance
        local spot_instance=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].SpotInstanceRequestId' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$spot_instance" != "None" && "$spot_instance" != "" ]]; then
            info "Instance is running on spot: $spot_instance"
        else
            info "Instance is running on-demand"
        fi
    else
        error "EC2 instance not found or not running for IP: $instance_ip"
        return 1
    fi
    
    # Validate EFS file system
    log "Checking EFS file system..."
    local efs_id=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME:-ai-starter-kit}" \
        --query 'Stacks[0].Outputs[?OutputKey==`EFSFileSystemId`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$efs_id" ]]; then
        local efs_state=$(aws efs describe-file-systems \
            --file-system-id "$efs_id" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null || echo "ERROR")
        
        if [[ "$efs_state" == "available" ]]; then
            success "EFS file system is available: $efs_id"
        else
            error "EFS file system is not available: $efs_state"
        fi
    else
        warning "EFS file system ID not found in CloudFormation outputs"
    fi
    
    return 0
}

validate_ssh_connectivity() {
    local instance_ip="$1"
    separator "=== VALIDATING SSH CONNECTIVITY ==="
    
    log "Testing SSH connectivity to $instance_ip..."
    
    # Test basic SSH connection
    if ssh_exec "$instance_ip" "echo 'SSH connection successful'" 10; then
        success "SSH connection established successfully"
    else
        error "SSH connection failed"
        return 1
    fi
    
    # Check user permissions
    log "Checking user permissions..."
    local user_groups=$(ssh_exec "$instance_ip" "groups" 5)
    if [[ "$user_groups" == *"docker"* ]]; then
        success "User has Docker group access"
    else
        warning "User may not have Docker group access: $user_groups"
    fi
    
    # Check sudo access
    if ssh_exec "$instance_ip" "sudo -n echo 'sudo works'" 5; then
        success "User has passwordless sudo access"
    else
        warning "User may not have passwordless sudo access"
    fi
    
    return 0
}

validate_gpu_functionality() {
    local instance_ip="$1"
    separator "=== VALIDATING GPU FUNCTIONALITY ==="
    
    log "Checking NVIDIA GPU availability..."
    
    # Check nvidia-smi
    local gpu_info=$(ssh_exec "$instance_ip" "nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits" 30)
    if [[ -n "$gpu_info" ]]; then
        success "NVIDIA GPU detected and accessible"
        while IFS=',' read -r gpu_name gpu_memory driver_version; do
            info "GPU: $gpu_name"
            info "Memory: ${gpu_memory}MB"
            info "Driver: $driver_version"
        done <<< "$gpu_info"
    else
        error "NVIDIA GPU not detected or nvidia-smi not working"
        return 1
    fi
    
    # Check CUDA availability
    log "Checking CUDA availability..."
    local cuda_version=$(ssh_exec "$instance_ip" "nvcc --version 2>/dev/null | grep 'release' | awk '{print \$6}' | cut -c2-" 10 || echo "")
    if [[ -n "$cuda_version" ]]; then
        success "CUDA is available: $cuda_version"
    else
        warning "CUDA toolkit not found or not in PATH"
    fi
    
    # Check Docker GPU runtime
    log "Checking Docker GPU runtime..."
    if ssh_exec "$instance_ip" "docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi" 60; then
        success "Docker GPU runtime is working correctly"
    else
        error "Docker GPU runtime is not working"
        return 1
    fi
    
    return 0
}

validate_efs_mounting() {
    local instance_ip="$1"
    separator "=== VALIDATING EFS MOUNTING ==="
    
    log "Checking EFS mount status..."
    
    # Check if EFS is mounted
    local efs_mounts=$(ssh_exec "$instance_ip" "mount | grep nfs4 | grep efs" 10)
    if [[ -n "$efs_mounts" ]]; then
        success "EFS file system is mounted"
        info "Mount details: $efs_mounts"
    else
        error "EFS file system is not mounted"
        return 1
    fi
    
    # Test EFS write access
    log "Testing EFS write access..."
    local test_file="/mnt/efs/validation_test_$(date +%s)"
    if ssh_exec "$instance_ip" "echo 'EFS validation test' > $test_file && cat $test_file && rm $test_file" 15; then
        success "EFS write and read access working"
    else
        error "EFS write/read access failed"
        return 1
    fi
    
    # Check EFS directories for services
    log "Checking service directories in EFS..."
    local service_dirs=("n8n" "postgres" "ollama" "qdrant" "shared" "crawl4ai")
    for dir in "${service_dirs[@]}"; do
        if ssh_exec "$instance_ip" "test -d /mnt/efs/$dir" 5; then
            success "EFS directory exists: $dir"
        else
            warning "EFS directory missing: $dir"
        fi
    done
    
    return 0
}

validate_docker_health() {
    local instance_ip="$1"
    separator "=== VALIDATING DOCKER HEALTH ==="
    
    log "Checking Docker daemon status..."
    
    # Check Docker service
    if ssh_exec "$instance_ip" "sudo systemctl is-active docker" 10; then
        success "Docker service is active"
    else
        error "Docker service is not active"
        return 1
    fi
    
    # Check Docker compose file
    if ssh_exec "$instance_ip" "test -f /home/ubuntu/ai-starter-kit/docker-compose.gpu-optimized.yml" 5; then
        success "Docker Compose file is present"
    else
        error "Docker Compose file not found"
        return 1
    fi
    
    # Check running containers
    log "Checking container status..."
    local container_status=$(ssh_exec "$instance_ip" "cd /home/ubuntu/ai-starter-kit && docker compose -f docker-compose.gpu-optimized.yml ps --format 'table {{.Name}}\t{{.State}}\t{{.Status}}'" 30)
    if [[ -n "$container_status" ]]; then
        success "Docker containers are running:"
        echo "$container_status"
    else
        error "No Docker containers found or Docker Compose not running"
        return 1
    fi
    
    # Check container health
    log "Checking container health status..."
    local unhealthy_containers=$(ssh_exec "$instance_ip" "docker ps --filter health=unhealthy --format '{{.Names}}'" 15)
    if [[ -z "$unhealthy_containers" ]]; then
        success "All containers are healthy"
    else
        error "Unhealthy containers found: $unhealthy_containers"
    fi
    
    # Check resource usage
    log "Checking container resource usage..."
    local resource_usage=$(ssh_exec "$instance_ip" "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'" 20)
    if [[ -n "$resource_usage" ]]; then
        info "Container resource usage:"
        echo "$resource_usage"
    fi
    
    return 0
}

validate_service_endpoints() {
    local instance_ip="$1"
    separator "=== VALIDATING SERVICE ENDPOINTS ==="
    
    # Service endpoints configuration
    declare -A services=(
        ["n8n"]="5678"
        ["ollama"]="11434"
        ["qdrant"]="6333"
        ["crawl4ai"]="11235"
    )
    
    # Test each service endpoint
    for service in "${!services[@]}"; do
        local port="${services[$service]}"
        log "Testing $service service on port $port..."
        
        # Test HTTP connectivity
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 10 --max-time 30 \
            "http://$instance_ip:$port" || echo "000")
        
        if [[ "$http_status" =~ ^[2-4][0-9][0-9]$ ]]; then
            success "$service is responding (HTTP $http_status)"
        else
            error "$service is not responding on port $port"
            continue
        fi
        
        # Service-specific health checks
        case "$service" in
            "n8n")
                local n8n_health=$(curl -s "http://$instance_ip:$port/healthz" || echo "ERROR")
                if [[ "$n8n_health" == *"ok"* ]]; then
                    success "n8n health check passed"
                else
                    warning "n8n health check failed"
                fi
                ;;
            "ollama")
                local ollama_version=$(curl -s "http://$instance_ip:$port/api/version" | jq -r '.version' 2>/dev/null || echo "ERROR")
                if [[ "$ollama_version" != "ERROR" ]]; then
                    success "Ollama API responding (version: $ollama_version)"
                else
                    warning "Ollama API version check failed"
                fi
                ;;
            "qdrant")
                local qdrant_health=$(curl -s "http://$instance_ip:$port/health" | jq -r '.status' 2>/dev/null || echo "ERROR")
                if [[ "$qdrant_health" == "ok" ]]; then
                    success "Qdrant health check passed"
                else
                    warning "Qdrant health check failed"
                fi
                ;;
            "crawl4ai")
                local crawl4ai_health=$(curl -s "http://$instance_ip:$port/health" || echo "ERROR")
                if [[ "$crawl4ai_health" != "ERROR" ]]; then
                    success "Crawl4AI health check passed"
                else
                    warning "Crawl4AI health check failed"
                fi
                ;;
        esac
    done
    
    return 0
}

validate_security_groups() {
    local instance_ip="$1"
    separator "=== VALIDATING SECURITY GROUPS ==="
    
    log "Checking security group configurations..."
    
    # Get instance security groups
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$instance_ip" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [[ "$instance_id" == "None" || -z "$instance_id" ]]; then
        error "Cannot find instance ID for IP: $instance_ip"
        return 1
    fi
    
    local security_groups=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' \
        --output text 2>/dev/null)
    
    if [[ -z "$security_groups" ]]; then
        error "No security groups found for instance"
        return 1
    fi
    
    success "Security groups attached: $security_groups"
    
    # Check security group rules
    for sg_id in $security_groups; do
        log "Checking security group rules for $sg_id..."
        
        # Check for required inbound rules
        local inbound_rules=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissions' \
            --output json 2>/dev/null)
        
        if [[ -n "$inbound_rules" && "$inbound_rules" != "null" ]]; then
            # Check for SSH access (port 22)
            local ssh_access=$(echo "$inbound_rules" | jq -r '.[] | select(.FromPort == 22 and .ToPort == 22) | .IpRanges[].CidrIp' 2>/dev/null || echo "")
            if [[ -n "$ssh_access" ]]; then
                success "SSH access configured from: $ssh_access"
            else
                warning "SSH access not found in security group rules"
            fi
            
            # Check for service ports
            local required_ports=(5678 11434 6333 11235 8000)
            for port in "${required_ports[@]}"; do
                local port_access=$(echo "$inbound_rules" | jq -r ".[] | select(.FromPort == $port and .ToPort == $port) | .IpRanges[].CidrIp" 2>/dev/null || echo "")
                if [[ -n "$port_access" ]]; then
                    success "Port $port accessible from: $port_access"
                else
                    warning "Port $port not accessible in security group"
                fi
            done
        fi
    done
    
    return 0
}

validate_cloudwatch_monitoring() {
    local instance_ip="$1"
    separator "=== VALIDATING CLOUDWATCH MONITORING ==="
    
    log "Checking CloudWatch monitoring setup..."
    
    # Get instance ID
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$instance_ip" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [[ "$instance_id" == "None" || -z "$instance_id" ]]; then
        error "Cannot find instance ID for monitoring check"
        return 1
    fi
    
    # Check if detailed monitoring is enabled
    local monitoring_state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].Monitoring.State' \
        --output text 2>/dev/null)
    
    if [[ "$monitoring_state" == "enabled" ]]; then
        success "CloudWatch detailed monitoring is enabled"
    else
        warning "CloudWatch detailed monitoring is disabled"
    fi
    
    # Check for recent metrics
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
    
    local cpu_metrics=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --query 'Datapoints | length(@)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$cpu_metrics" -gt 0 ]]; then
        success "CloudWatch metrics are being collected (CPU data points: $cpu_metrics)"
    else
        warning "No recent CloudWatch metrics found"
    fi
    
    # Check CloudWatch agent status on instance
    local cw_agent_status=$(ssh_exec "$instance_ip" "sudo systemctl is-active amazon-cloudwatch-agent" 10 || echo "inactive")
    if [[ "$cw_agent_status" == "active" ]]; then
        success "CloudWatch agent is running"
    else
        warning "CloudWatch agent is not active: $cw_agent_status"
    fi
    
    return 0
}

# =============================================================================
# DIAGNOSTIC FUNCTIONS
# =============================================================================

collect_diagnostics() {
    local instance_ip="$1"
    separator "=== COLLECTING DIAGNOSTICS ==="
    
    log "Gathering system diagnostics..."
    
    # System information
    info "System Information:"
    ssh_exec "$instance_ip" "uname -a" 15 || true
    
    # Memory usage
    info "Memory Usage:"
    ssh_exec "$instance_ip" "free -h" 10 || true
    
    # Disk usage
    info "Disk Usage:"
    ssh_exec "$instance_ip" "df -h" 10 || true
    
    # Docker system info
    info "Docker System Info:"
    ssh_exec "$instance_ip" "docker system df" 15 || true
    
    # Service logs (last 50 lines)
    info "Recent Docker Compose Logs:"
    ssh_exec "$instance_ip" "cd /home/ubuntu/ai-starter-kit && docker compose -f docker-compose.gpu-optimized.yml logs --tail=20" 30 || true
    
    # GPU status
    info "GPU Status:"
    ssh_exec "$instance_ip" "nvidia-smi" 15 || true
    
    return 0
}

generate_troubleshooting_guide() {
    separator "=== TROUBLESHOOTING GUIDE ==="
    
    if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
        echo -e "${RED}❌ FAILED CHECKS (${#FAILED_CHECKS[@]})${NC}"
        for check in "${FAILED_CHECKS[@]}"; do
            echo -e "${RED}  • $check${NC}"
        done
        echo ""
        
        info "🔧 Troubleshooting steps for common issues:"
        echo "1. SSH Connection Failed:"
        echo "   - Verify security group allows SSH (port 22) from your IP"
        echo "   - Check if SSH key file exists and has correct permissions (600)"
        echo "   - Ensure instance is in running state"
        echo ""
        echo "2. GPU Not Detected:"
        echo "   - Verify instance type supports GPU (g4dn, g5, p3, p4 families)"
        echo "   - Check if NVIDIA drivers are installed: 'nvidia-smi'"
        echo "   - Restart instance if drivers recently installed"
        echo ""
        echo "3. Docker GPU Runtime Issues:"
        echo "   - Restart Docker service: 'sudo systemctl restart docker'"
        echo "   - Check nvidia-docker2 installation"
        echo "   - Verify GPU is accessible: 'docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi'"
        echo ""
        echo "4. Service Endpoints Not Responding:"
        echo "   - Check container status: 'docker compose ps'"
        echo "   - Review container logs: 'docker compose logs [service-name]'"
        echo "   - Verify security group allows required ports"
        echo "   - Check if services are starting up (may take 2-5 minutes)"
        echo ""
        echo "5. EFS Mount Issues:"
        echo "   - Check EFS security group allows NFS (port 2049)"
        echo "   - Verify EFS file system is available in AWS console"
        echo "   - Check mount command in user-data script"
        echo ""
    fi
    
    if [[ ${#WARNING_CHECKS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠ WARNINGS (${#WARNING_CHECKS[@]})${NC}"
        for check in "${WARNING_CHECKS[@]}"; do
            echo -e "${YELLOW}  • $check${NC}"
        done
        echo ""
    fi
    
    if [[ ${#PASSED_CHECKS[@]} -gt 0 ]]; then
        echo -e "${GREEN}✅ PASSED CHECKS (${#PASSED_CHECKS[@]})${NC}"
        for check in "${PASSED_CHECKS[@]}"; do
            echo -e "${GREEN}  • $check${NC}"
        done
        echo ""
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local instance_ip="${1:-}"
    local verbose="${2:-false}"
    
    # Check if help is requested
    if [[ "$instance_ip" == "--help" || "$instance_ip" == "-h" ]]; then
        echo "Usage: $0 <instance-ip> [verbose]"
        echo ""
        echo "Comprehensive deployment validation for AI Starter Kit"
        echo ""
        echo "Options:"
        echo "  instance-ip    IP address of deployed instance"
        echo "  verbose        Enable verbose output (true/false)"
        echo ""
        echo "Examples:"
        echo "  $0 54.123.456.789"
        echo "  $0 54.123.456.789 true"
        exit 0
    fi
    
    if [[ -z "$instance_ip" ]]; then
        error "Instance IP address is required"
        echo "Usage: $0 <instance-ip> [verbose]"
        exit 1
    fi
    
    # Configure global variables
    KEY_NAME="${KEY_NAME:-ai-starter-kit-key}"
    STACK_NAME="${STACK_NAME:-ai-starter-kit}"
    
    separator "═══════════════════════════════════════════════════════════════════"
    log "🚀 AI Starter Kit - Comprehensive Deployment Validator"
    log "Instance IP: $instance_ip"
    log "Validation Timeout: ${VALIDATION_TIMEOUT}s"
    separator "═══════════════════════════════════════════════════════════════════"
    
    local overall_status=0
    
    # Run validation steps
    validate_prerequisites || overall_status=1
    validate_infrastructure "$instance_ip" || overall_status=1
    validate_ssh_connectivity "$instance_ip" || overall_status=1
    validate_gpu_functionality "$instance_ip" || overall_status=1
    validate_efs_mounting "$instance_ip" || overall_status=1
    validate_docker_health "$instance_ip" || overall_status=1
    validate_service_endpoints "$instance_ip" || overall_status=1
    validate_security_groups "$instance_ip" || overall_status=1
    validate_cloudwatch_monitoring "$instance_ip" || overall_status=1
    
    # Collect diagnostics if verbose or if there are failures
    if [[ "$verbose" == "true" || $overall_status -ne 0 ]]; then
        collect_diagnostics "$instance_ip"
    fi
    
    # Generate final report
    separator "═══════════════════════════════════════════════════════════════════"
    log "📊 VALIDATION SUMMARY"
    separator "═══════════════════════════════════════════════════════════════════"
    
    generate_troubleshooting_guide
    
    if [[ $overall_status -eq 0 ]]; then
        success "🎉 All validations passed! Deployment is healthy and ready for use."
        info "🌐 Access your services:"
        info "  • n8n: http://$instance_ip:5678"
        info "  • Ollama: http://$instance_ip:11434"
        info "  • Qdrant: http://$instance_ip:6333"
        info "  • Crawl4AI: http://$instance_ip:11235"
    else
        error "❌ Some validations failed. Please review the troubleshooting guide above."
    fi
    
    separator "═══════════════════════════════════════════════════════════════════"
    
    exit $overall_status
}

# Execute main function with all arguments
main "$@"