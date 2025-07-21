#!/bin/bash

# =============================================================================
# AI Starter Kit - Security Audit and Compliance Validator
# =============================================================================
# Comprehensive security validation for AWS infrastructure
# Features: Port scanning, IAM validation, credential security, network security,
# access controls, compliance checking, security recommendations
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
SECURITY_TIMEOUT=300  # 5 minutes for security checks
SSH_TIMEOUT=30

# Security tracking
SECURITY_ISSUES=()
SECURITY_WARNINGS=()
SECURITY_PASSED=()
COMPLIANCE_ISSUES=()

# Expected secure configurations
ALLOWED_INBOUND_PORTS=(22 5678 11434 6333 11235 8000 2049)  # SSH, n8n, Ollama, Qdrant, Crawl4AI, NFS
CRITICAL_PROCESSES=("sshd" "docker" "systemd")
SENSITIVE_FILES=("/etc/passwd" "/etc/shadow" "/etc/ssh/sshd_config" "/home/ubuntu/.ssh/authorized_keys")

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}"
}

security_pass() {
    echo -e "${GREEN}✓ $*${NC}"
    SECURITY_PASSED+=("$*")
}

security_warning() {
    echo -e "${YELLOW}⚠ $*${NC}"
    SECURITY_WARNINGS+=("$*")
}

security_issue() {
    echo -e "${RED}✗ $*${NC}"
    SECURITY_ISSUES+=("$*")
}

compliance_issue() {
    echo -e "${RED}⚡ COMPLIANCE: $*${NC}"
    COMPLIANCE_ISSUES+=("$*")
}

info() {
    echo -e "${CYAN}ℹ $*${NC}"
}

separator() {
    echo -e "${PURPLE}$1${NC}"
}

recommend() {
    echo -e "${YELLOW}🔒 SECURITY RECOMMENDATION: $*${NC}"
}

# Timeout wrapper for commands
run_with_timeout() {
    local timeout="$1"
    shift
    timeout "$timeout" "$@" 2>/dev/null || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            security_issue "Security check timed out after ${timeout}s: $*"
        else
            security_issue "Security check failed with exit code $exit_code: $*"
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

# Check if port is in allowed list
is_port_allowed() {
    local port="$1"
    for allowed_port in "${ALLOWED_INBOUND_PORTS[@]}"; do
        if [[ "$port" -eq "$allowed_port" ]]; then
            return 0
        fi
    done
    return 1
}

# =============================================================================
# NETWORK SECURITY VALIDATION
# =============================================================================

audit_network_security() {
    local instance_ip="$1"
    separator "=== NETWORK SECURITY AUDIT ==="
    
    log "Auditing network security configurations..."
    
    # Get instance security groups
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$instance_ip" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [[ "$instance_id" == "None" || -z "$instance_id" ]]; then
        security_issue "Cannot find instance ID for security audit"
        return 1
    fi
    
    local security_groups=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' \
        --output text 2>/dev/null)
    
    if [[ -z "$security_groups" ]]; then
        security_issue "No security groups found for instance"
        return 1
    fi
    
    security_pass "Security groups found: $security_groups"
    
    # Analyze security group rules
    for sg_id in $security_groups; do
        log "Auditing security group: $sg_id"
        
        # Get inbound rules
        local inbound_rules=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissions' \
            --output json 2>/dev/null)
        
        if [[ -n "$inbound_rules" && "$inbound_rules" != "null" ]]; then
            # Check for overly permissive rules
            local open_rules=$(echo "$inbound_rules" | jq -r '.[] | select(.IpRanges[]?.CidrIp == "0.0.0.0/0") | "\(.FromPort)-\(.ToPort)"' 2>/dev/null || echo "")
            
            if [[ -n "$open_rules" ]]; then
                echo "$open_rules" | while read -r port_range; do
                    if [[ -n "$port_range" ]]; then
                        IFS='-' read -r from_port to_port <<< "$port_range"
                        
                        # Check if this is an expected open port
                        if is_port_allowed "$from_port"; then
                            if [[ "$from_port" == "22" ]]; then
                                security_warning "SSH (port 22) is open to 0.0.0.0/0 - consider restricting to specific IPs"
                            else
                                security_pass "Port $from_port is appropriately open for service access"
                            fi
                        else
                            security_issue "Unexpected port $from_port open to 0.0.0.0/0"
                        fi
                    fi
                done
            else
                security_pass "No overly permissive inbound rules found"
            fi
            
            # Check for required service ports
            for required_port in "${ALLOWED_INBOUND_PORTS[@]}"; do
                if [[ "$required_port" != "22" ]]; then  # Skip SSH check for services
                    local port_exists=$(echo "$inbound_rules" | jq -r ".[] | select(.FromPort == $required_port and .ToPort == $required_port) | .FromPort" 2>/dev/null || echo "")
                    if [[ -n "$port_exists" ]]; then
                        security_pass "Required service port $required_port is accessible"
                    else
                        security_warning "Service port $required_port may not be accessible"
                    fi
                fi
            done
        fi
        
        # Check outbound rules
        local outbound_rules=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissionsEgress' \
            --output json 2>/dev/null)
        
        if [[ -n "$outbound_rules" && "$outbound_rules" != "null" ]]; then
            local unrestricted_egress=$(echo "$outbound_rules" | jq -r '.[] | select(.IpRanges[]?.CidrIp == "0.0.0.0/0" and .FromPort == 0 and .ToPort == 65535) | "found"' 2>/dev/null || echo "")
            
            if [[ "$unrestricted_egress" == "found" ]]; then
                security_warning "Unrestricted outbound access detected - consider implementing egress filtering"
            else
                security_pass "Outbound rules are appropriately restricted"
            fi
        fi
    done
    
    # Network interface security
    log "Checking network interface security..."
    local public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null)
    
    local private_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text 2>/dev/null)
    
    if [[ "$public_ip" != "None" && -n "$public_ip" ]]; then
        security_warning "Instance has public IP address: $public_ip - ensure this is necessary"
        info "Consider using VPN or bastion host for enhanced security"
    else
        security_pass "Instance uses private IP only: $private_ip"
    fi
    
    return 0
}

# =============================================================================
# PORT SCANNING AND SERVICE EXPOSURE AUDIT
# =============================================================================

audit_exposed_services() {
    local instance_ip="$1"
    separator "=== EXPOSED SERVICES AUDIT ==="
    
    log "Scanning for exposed services and open ports..."
    
    # Check if nmap is available, if not use basic tools
    if command -v nmap >/dev/null 2>&1; then
        log "Using nmap for comprehensive port scan..."
        local nmap_results=$(nmap -sS -O -sV -p 1-65535 "$instance_ip" 2>/dev/null || echo "NMAP_FAILED")
        
        if [[ "$nmap_results" != "NMAP_FAILED" ]]; then
            local open_ports=$(echo "$nmap_results" | grep "^[0-9]" | grep "open" | awk '{print $1}' | cut -d'/' -f1)
            
            if [[ -n "$open_ports" ]]; then
                info "Open ports detected:"
                echo "$open_ports" | while read -r port; do
                    if [[ -n "$port" ]]; then
                        if is_port_allowed "$port"; then
                            security_pass "Expected port $port is open"
                        else
                            security_issue "Unexpected port $port is open"
                        fi
                    fi
                done
            else
                security_warning "No open ports detected by nmap - this may indicate connectivity issues"
            fi
        else
            security_warning "nmap scan failed - using alternative methods"
        fi
    else
        log "nmap not available - using basic connectivity tests..."
    fi
    
    # Test expected service endpoints
    local services=(
        "SSH:22"
        "n8n:5678"
        "Ollama:11434"
        "Qdrant:6333"
        "Crawl4AI:11235"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        log "Testing $service_name service connectivity on port $port..."
        
        if timeout 10 bash -c "echo >/dev/tcp/$instance_ip/$port" 2>/dev/null; then
            security_pass "$service_name service is accessible on port $port"
            
            # Additional service-specific security checks
            case "$service_name" in
                "SSH")
                    # Check SSH configuration
                    local ssh_banner=$(timeout 5 ssh -o ConnectTimeout=5 -o BatchMode=yes "$instance_ip" 2>&1 | head -1 || echo "")
                    if [[ "$ssh_banner" == *"OpenSSH"* ]]; then
                        security_pass "SSH service is running OpenSSH"
                        # Check for SSH version vulnerabilities (basic check)
                        local ssh_version=$(echo "$ssh_banner" | grep -o "OpenSSH_[0-9]\+\.[0-9]\+" || echo "")
                        if [[ -n "$ssh_version" ]]; then
                            info "SSH version: $ssh_version"
                        fi
                    fi
                    ;;
                "n8n")
                    # Check if n8n has authentication enabled
                    local n8n_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$instance_ip:$port/" --max-time 10 2>/dev/null || echo "000")
                    if [[ "$n8n_response" == "200" ]]; then
                        security_warning "n8n may be accessible without authentication - verify security settings"
                    fi
                    ;;
            esac
        else
            if [[ "$service_name" == "SSH" ]]; then
                security_issue "$service_name service is not accessible on port $port"
            else
                security_warning "$service_name service is not accessible on port $port - may be starting up"
            fi
        fi
    done
    
    # Check for unexpected services
    log "Scanning for unexpected services..."
    local common_vulnerable_ports=(21 23 25 53 80 110 143 443 993 995 1433 3306 3389 5432 6379 27017 8080 9000 9200 9300)
    
    for port in "${common_vulnerable_ports[@]}"; do
        if timeout 3 bash -c "echo >/dev/tcp/$instance_ip/$port" 2>/dev/null; then
            if ! is_port_allowed "$port"; then
                security_issue "Unexpected service found on port $port - investigate immediately"
            fi
        fi
    done
    
    return 0
}

# =============================================================================
# IAM AND ACCESS CONTROL AUDIT
# =============================================================================

audit_iam_and_access() {
    local instance_ip="$1"
    separator "=== IAM AND ACCESS CONTROL AUDIT ==="
    
    log "Auditing IAM roles and access controls..."
    
    # Get instance IAM role
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$instance_ip" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [[ "$instance_id" != "None" && -n "$instance_id" ]]; then
        local iam_role=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$iam_role" != "None" && -n "$iam_role" ]]; then
            security_pass "IAM instance profile attached: $iam_role"
            
            # Extract role name
            local role_name=$(echo "$iam_role" | cut -d'/' -f2)
            
            # Check role policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$attached_policies" ]]; then
                info "Attached policies: $attached_policies"
                
                # Check for overly permissive policies
                echo "$attached_policies" | tr '\t' '\n' | while read -r policy_arn; do
                    if [[ -n "$policy_arn" ]]; then
                        if [[ "$policy_arn" == *"AdministratorAccess"* ]]; then
                            security_issue "AdministratorAccess policy attached - excessive permissions"
                        elif [[ "$policy_arn" == *"PowerUserAccess"* ]]; then
                            security_warning "PowerUserAccess policy attached - consider more restrictive permissions"
                        else
                            security_pass "Policy appears to follow least privilege: $policy_arn"
                        fi
                    fi
                done
            fi
            
            # Check inline policies
            local inline_policies=$(aws iam list-role-policies \
                --role-name "$role_name" \
                --query 'PolicyNames' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$inline_policies" && "$inline_policies" != "None" ]]; then
                info "Inline policies found: $inline_policies"
                # Could add more detailed inline policy analysis here
            fi
            
        else
            security_warning "No IAM instance profile attached - limited AWS service access"
        fi
    fi
    
    # Check SSH key security
    log "Auditing SSH key security..."
    
    if [[ -f "${KEY_NAME}.pem" ]]; then
        local key_permissions=$(ls -l "${KEY_NAME}.pem" | awk '{print $1}')
        if [[ "$key_permissions" == "-rw-------" ]]; then
            security_pass "SSH private key has correct permissions (600)"
        else
            security_issue "SSH private key has incorrect permissions: $key_permissions"
            recommend "Run: chmod 600 ${KEY_NAME}.pem"
        fi
        
        # Check key strength (basic check)
        local key_type=$(ssh-keygen -l -f "${KEY_NAME}.pem" 2>/dev/null | awk '{print $4}' | tr -d '()' || echo "unknown")
        local key_bits=$(ssh-keygen -l -f "${KEY_NAME}.pem" 2>/dev/null | awk '{print $1}' || echo "0")
        
        if [[ "$key_type" == "RSA" && "$key_bits" -ge 2048 ]]; then
            security_pass "SSH key uses strong encryption: $key_bits-bit $key_type"
        elif [[ "$key_type" == "ED25519" ]]; then
            security_pass "SSH key uses modern encryption: $key_type"
        else
            security_warning "SSH key may use weak encryption: $key_bits-bit $key_type"
        fi
    else
        security_issue "SSH private key file not found: ${KEY_NAME}.pem"
    fi
    
    return 0
}

# =============================================================================
# SYSTEM SECURITY AUDIT
# =============================================================================

audit_system_security() {
    local instance_ip="$1"
    separator "=== SYSTEM SECURITY AUDIT ==="
    
    log "Auditing system-level security configurations..."
    
    # Check system users
    log "Checking system user accounts..."
    local system_users=$(ssh_exec "$instance_ip" "cat /etc/passwd | grep -E '/bin/(bash|sh)$' | cut -d: -f1" 30)
    if [[ -n "$system_users" ]]; then
        local user_count=$(echo "$system_users" | wc -l)
        info "Users with shell access ($user_count): $(echo "$system_users" | tr '\n' ' ')"
        
        # Check for unexpected users
        echo "$system_users" | while read -r username; do
            if [[ -n "$username" ]]; then
                case "$username" in
                    "root"|"ubuntu"|"ec2-user")
                        security_pass "Expected system user: $username"
                        ;;
                    *)
                        security_warning "Unexpected user with shell access: $username"
                        ;;
                esac
            fi
        done
    fi
    
    # Check sudo access
    log "Checking sudo configurations..."
    local sudo_users=$(ssh_exec "$instance_ip" "sudo cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -E '^[^#]*ALL.*ALL' | grep -v 'root'" 15 || echo "")
    if [[ -n "$sudo_users" ]]; then
        info "Sudo access configured for:"
        echo "$sudo_users" | while read -r sudo_line; do
            if [[ -n "$sudo_line" ]]; then
                info "  $sudo_line"
                if [[ "$sudo_line" == *"NOPASSWD"* ]]; then
                    security_warning "Passwordless sudo detected: $sudo_line"
                fi
            fi
        done
    fi
    
    # Check for running processes
    log "Checking critical system processes..."
    for process in "${CRITICAL_PROCESSES[@]}"; do
        local process_status=$(ssh_exec "$instance_ip" "pgrep $process > /dev/null && echo 'running' || echo 'not running'" 10)
        if [[ "$process_status" == "running" ]]; then
            security_pass "Critical process $process is running"
        else
            security_issue "Critical process $process is not running"
        fi
    done
    
    # Check file permissions on sensitive files
    log "Checking sensitive file permissions..."
    for file in "${SENSITIVE_FILES[@]}"; do
        local file_perms=$(ssh_exec "$instance_ip" "ls -l $file 2>/dev/null | awk '{print \$1\" \"\$3\" \"\$4}'" 10 || echo "FILE_NOT_FOUND")
        
        if [[ "$file_perms" != "FILE_NOT_FOUND" ]]; then
            case "$file" in
                "/etc/shadow")
                    if [[ "$file_perms" == "-rw-r-----"* || "$file_perms" == "-rw-------"* ]]; then
                        security_pass "Shadow file has secure permissions: $file_perms"
                    else
                        security_issue "Shadow file has insecure permissions: $file_perms"
                    fi
                    ;;
                "/etc/ssh/sshd_config")
                    if [[ "$file_perms" == "-rw-r--r--"* ]]; then
                        security_pass "SSH config has appropriate permissions: $file_perms"
                    else
                        security_warning "SSH config has unusual permissions: $file_perms"
                    fi
                    ;;
                "/home/ubuntu/.ssh/authorized_keys")
                    if [[ "$file_perms" == "-rw-------"* ]]; then
                        security_pass "Authorized keys has secure permissions: $file_perms"
                    else
                        security_issue "Authorized keys has insecure permissions: $file_perms"
                    fi
                    ;;
                *)
                    info "$file permissions: $file_perms"
                    ;;
            esac
        else
            security_warning "Sensitive file not found: $file"
        fi
    done
    
    # Check SSH configuration security
    log "Checking SSH security configuration..."
    local ssh_config=$(ssh_exec "$instance_ip" "sudo cat /etc/ssh/sshd_config | grep -E '^[^#]*(PasswordAuthentication|PermitRootLogin|Protocol|PermitEmptyPasswords)'" 15 || echo "")
    
    if [[ -n "$ssh_config" ]]; then
        echo "$ssh_config" | while read -r config_line; do
            if [[ -n "$config_line" ]]; then
                case "$config_line" in
                    *"PasswordAuthentication no"*)
                        security_pass "Password authentication is disabled"
                        ;;
                    *"PasswordAuthentication yes"*)
                        security_issue "Password authentication is enabled - security risk"
                        ;;
                    *"PermitRootLogin no"*)
                        security_pass "Root login is disabled"
                        ;;
                    *"PermitRootLogin yes"*)
                        security_issue "Root login is enabled - security risk"
                        ;;
                    *"PermitEmptyPasswords no"*)
                        security_pass "Empty passwords are not permitted"
                        ;;
                    *"PermitEmptyPasswords yes"*)
                        security_issue "Empty passwords are permitted - security risk"
                        ;;
                    *)
                        info "SSH config: $config_line"
                        ;;
                esac
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# CONTAINER AND APPLICATION SECURITY AUDIT
# =============================================================================

audit_container_security() {
    local instance_ip="$1"
    separator "=== CONTAINER SECURITY AUDIT ==="
    
    log "Auditing Docker and container security..."
    
    # Check Docker daemon security
    log "Checking Docker daemon configuration..."
    local docker_version=$(ssh_exec "$instance_ip" "docker version --format '{{.Server.Version}}'" 15 || echo "unknown")
    if [[ "$docker_version" != "unknown" ]]; then
        security_pass "Docker daemon is running (version: $docker_version)"
        
        # Check for known vulnerable Docker versions (basic check)
        local version_major=$(echo "$docker_version" | cut -d'.' -f1)
        local version_minor=$(echo "$docker_version" | cut -d'.' -f2)
        
        if [[ "$version_major" -ge 20 || ("$version_major" -eq 19 && "$version_minor" -ge 3) ]]; then
            security_pass "Docker version is reasonably recent"
        else
            security_warning "Docker version may be outdated: $docker_version"
        fi
    else
        security_issue "Cannot determine Docker version"
    fi
    
    # Check running containers
    log "Checking container configurations..."
    local containers=$(ssh_exec "$instance_ip" "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'" 30)
    
    if [[ -n "$containers" ]]; then
        info "Running containers:"
        echo "$containers"
        
        # Check for containers running as root
        local container_names=$(ssh_exec "$instance_ip" "docker ps --format '{{.Names}}'" 15)
        echo "$container_names" | while read -r container_name; do
            if [[ -n "$container_name" ]]; then
                local container_user=$(ssh_exec "$instance_ip" "docker exec $container_name whoami 2>/dev/null" 10 || echo "unknown")
                if [[ "$container_user" == "root" ]]; then
                    security_warning "Container $container_name is running as root"
                elif [[ "$container_user" != "unknown" ]]; then
                    security_pass "Container $container_name is running as non-root user: $container_user"
                fi
            fi
        done
        
        # Check for privileged containers
        local privileged_containers=$(ssh_exec "$instance_ip" "docker ps --filter 'label=privileged=true' --format '{{.Names}}'" 15 || echo "")
        if [[ -n "$privileged_containers" ]]; then
            security_warning "Privileged containers detected: $privileged_containers"
        else
            security_pass "No privileged containers detected"
        fi
    else
        security_warning "No running containers found"
    fi
    
    # Check for exposed Docker API
    log "Checking Docker API exposure..."
    if timeout 3 bash -c "echo >/dev/tcp/$instance_ip/2375" 2>/dev/null || timeout 3 bash -c "echo >/dev/tcp/$instance_ip/2376" 2>/dev/null; then
        security_issue "Docker API appears to be exposed - immediate security risk"
    else
        security_pass "Docker API is not externally exposed"
    fi
    
    # Check image security (basic)
    log "Checking container image security..."
    local images=$(ssh_exec "$instance_ip" "docker images --format '{{.Repository}}:{{.Tag}}'" 15)
    if [[ -n "$images" ]]; then
        echo "$images" | while read -r image; do
            if [[ -n "$image" ]]; then
                if [[ "$image" == *":latest" ]]; then
                    security_warning "Image using 'latest' tag: $image - consider using specific versions"
                else
                    security_pass "Image using specific tag: $image"
                fi
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# CREDENTIAL AND SECRET SECURITY AUDIT
# =============================================================================

audit_credential_security() {
    local instance_ip="$1"
    separator "=== CREDENTIAL AND SECRET SECURITY AUDIT ==="
    
    log "Auditing credential and secret management..."
    
    # Check for hardcoded secrets in environment variables
    log "Checking environment variables for secrets..."
    local env_vars=$(ssh_exec "$instance_ip" "env | grep -E '(PASSWORD|SECRET|KEY|TOKEN)' | cut -d'=' -f1" 15 || echo "")
    
    if [[ -n "$env_vars" ]]; then
        echo "$env_vars" | while read -r var_name; do
            if [[ -n "$var_name" ]]; then
                case "$var_name" in
                    "SSH_AUTH_SOCK"|"GPG_AGENT_INFO")
                        # These are normal system variables
                        ;;
                    *)
                        security_warning "Sensitive environment variable found: $var_name"
                        ;;
                esac
            fi
        done
    else
        security_pass "No obvious sensitive environment variables found"
    fi
    
    # Check for secrets in Docker environment
    log "Checking Docker container environment variables..."
    local container_names=$(ssh_exec "$instance_ip" "docker ps --format '{{.Names}}'" 15)
    echo "$container_names" | while read -r container_name; do
        if [[ -n "$container_name" ]]; then
            local container_env=$(ssh_exec "$instance_ip" "docker exec $container_name env 2>/dev/null | grep -E '(PASSWORD|SECRET|KEY|TOKEN)' | cut -d'=' -f1" 10 || echo "")
            if [[ -n "$container_env" ]]; then
                echo "$container_env" | while read -r env_var; do
                    if [[ -n "$env_var" ]]; then
                        security_warning "Container $container_name has sensitive env var: $env_var"
                    fi
                done
            fi
        fi
    done
    
    # Check for secrets in files
    log "Checking for potential secrets in common locations..."
    local secret_patterns=("password" "secret" "private_key" "api_key" "token")
    
    for pattern in "${secret_patterns[@]}"; do
        local found_files=$(ssh_exec "$instance_ip" "find /home/ubuntu -type f -name '*.env' -o -name '*.conf' -o -name '*.config' 2>/dev/null | head -10 | xargs grep -l -i '$pattern' 2>/dev/null" 15 || echo "")
        if [[ -n "$found_files" ]]; then
            security_warning "Files potentially containing secrets ($pattern): $found_files"
        fi
    done
    
    # Check AWS credentials configuration
    log "Checking AWS credential configuration..."
    local aws_creds=$(ssh_exec "$instance_ip" "ls -la ~/.aws/ 2>/dev/null || echo 'NO_AWS_CONFIG'" 10)
    
    if [[ "$aws_creds" != "NO_AWS_CONFIG" ]]; then
        if [[ "$aws_creds" == *"credentials"* ]]; then
            security_warning "AWS credentials file found - consider using IAM roles instead"
        fi
        if [[ "$aws_creds" == *"config"* ]]; then
            security_pass "AWS config file found"
        fi
    else
        security_pass "No AWS credentials file found - likely using IAM roles"
    fi
    
    return 0
}

# =============================================================================
# COMPLIANCE AND BEST PRACTICES AUDIT
# =============================================================================

audit_compliance() {
    local instance_ip="$1"
    separator "=== COMPLIANCE AND BEST PRACTICES AUDIT ==="
    
    log "Checking compliance with security best practices..."
    
    # Check system updates
    log "Checking system update status..."
    local security_updates=$(ssh_exec "$instance_ip" "sudo apt list --upgradable 2>/dev/null | grep -i security | wc -l" 30 || echo "0")
    
    if [[ "$security_updates" -eq 0 ]]; then
        security_pass "No pending security updates"
    else
        compliance_issue "$security_updates pending security updates found"
        recommend "Run: sudo apt update && sudo apt upgrade"
    fi
    
    # Check firewall status
    log "Checking firewall configuration..."
    local ufw_status=$(ssh_exec "$instance_ip" "sudo ufw status" 10 || echo "ERROR")
    
    if [[ "$ufw_status" == *"Status: active"* ]]; then
        security_pass "UFW firewall is active"
    elif [[ "$ufw_status" == *"Status: inactive"* ]]; then
        compliance_issue "UFW firewall is inactive"
        recommend "Consider enabling UFW firewall for defense in depth"
    else
        security_warning "Cannot determine firewall status"
    fi
    
    # Check logging configuration
    log "Checking system logging..."
    local rsyslog_status=$(ssh_exec "$instance_ip" "sudo systemctl is-active rsyslog" 10 || echo "inactive")
    local journal_status=$(ssh_exec "$instance_ip" "sudo systemctl is-active systemd-journald" 10 || echo "inactive")
    
    if [[ "$rsyslog_status" == "active" || "$journal_status" == "active" ]]; then
        security_pass "System logging is configured"
    else
        compliance_issue "System logging may not be properly configured"
    fi
    
    # Check for security monitoring tools
    log "Checking for security monitoring tools..."
    local monitoring_tools=("fail2ban" "rkhunter" "chkrootkit" "aide")
    local found_tools=()
    
    for tool in "${monitoring_tools[@]}"; do
        local tool_status=$(ssh_exec "$instance_ip" "command -v $tool >/dev/null 2>&1 && echo 'installed' || echo 'not_installed'" 10)
        if [[ "$tool_status" == "installed" ]]; then
            found_tools+=("$tool")
        fi
    done
    
    if [[ ${#found_tools[@]} -gt 0 ]]; then
        security_pass "Security monitoring tools found: ${found_tools[*]}"
    else
        recommend "Consider installing security monitoring tools like fail2ban"
    fi
    
    # Check for backup configuration
    log "Checking backup configuration..."
    local backup_jobs=$(ssh_exec "$instance_ip" "crontab -l 2>/dev/null | grep -i backup | wc -l" 10 || echo "0")
    
    if [[ "$backup_jobs" -gt 0 ]]; then
        security_pass "Backup jobs configured in crontab"
    else
        recommend "Consider implementing automated backup procedures"
    fi
    
    # Check EFS encryption
    log "Checking EFS encryption status..."
    local efs_id=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME:-ai-starter-kit}" \
        --query 'Stacks[0].Outputs[?OutputKey==`EFSFileSystemId`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$efs_id" ]]; then
        local efs_encrypted=$(aws efs describe-file-systems \
            --file-system-id "$efs_id" \
            --query 'FileSystems[0].Encrypted' \
            --output text 2>/dev/null || echo "false")
        
        if [[ "$efs_encrypted" == "true" ]]; then
            security_pass "EFS file system is encrypted"
        else
            compliance_issue "EFS file system is not encrypted"
        fi
    fi
    
    return 0
}

# =============================================================================
# SECURITY RECOMMENDATIONS AND REPORTING
# =============================================================================

generate_security_report() {
    separator "=== SECURITY AUDIT REPORT ==="
    
    local total_issues=${#SECURITY_ISSUES[@]}
    local total_warnings=${#SECURITY_WARNINGS[@]}
    local total_passed=${#SECURITY_PASSED[@]}
    local total_compliance=${#COMPLIANCE_ISSUES[@]}
    
    if [[ $total_issues -gt 0 ]]; then
        echo -e "${RED}🚨 CRITICAL SECURITY ISSUES ($total_issues)${NC}"
        for issue in "${SECURITY_ISSUES[@]}"; do
            echo -e "${RED}  • $issue${NC}"
        done
        echo ""
    fi
    
    if [[ $total_compliance -gt 0 ]]; then
        echo -e "${RED}⚡ COMPLIANCE ISSUES ($total_compliance)${NC}"
        for issue in "${COMPLIANCE_ISSUES[@]}"; do
            echo -e "${RED}  • $issue${NC}"
        done
        echo ""
    fi
    
    if [[ $total_warnings -gt 0 ]]; then
        echo -e "${YELLOW}⚠ SECURITY WARNINGS ($total_warnings)${NC}"
        for warning in "${SECURITY_WARNINGS[@]}"; do
            echo -e "${YELLOW}  • $warning${NC}"
        done
        echo ""
    fi
    
    if [[ $total_passed -gt 0 ]]; then
        echo -e "${GREEN}✅ SECURITY CHECKS PASSED ($total_passed)${NC}"
        for check in "${SECURITY_PASSED[@]}"; do
            echo -e "${GREEN}  • $check${NC}"
        done
        echo ""
    fi
    
    # Security recommendations
    separator "=== SECURITY RECOMMENDATIONS ==="
    
    if [[ $total_issues -gt 0 || $total_compliance -gt 0 ]]; then
        recommend "Address critical security issues immediately before proceeding"
        recommend "Review and update security group rules to follow principle of least privilege"
        recommend "Implement monitoring and alerting for security events"
        recommend "Regular security audits and penetration testing"
        recommend "Keep all systems and software updated with latest security patches"
    fi
    
    if [[ $total_warnings -gt 0 ]]; then
        recommend "Review security warnings and implement improvements where possible"
        recommend "Consider implementing additional security hardening measures"
    fi
    
    # Overall security score
    local security_score=0
    if [[ $total_passed -gt 0 ]]; then
        security_score=$(( (total_passed * 100) / (total_passed + total_warnings + total_issues + total_compliance) ))
    fi
    
    separator "=== SECURITY SCORE ==="
    if [[ $security_score -ge 90 ]]; then
        echo -e "${GREEN}🏆 Security Score: $security_score/100 - Excellent${NC}"
    elif [[ $security_score -ge 75 ]]; then
        echo -e "${YELLOW}🥉 Security Score: $security_score/100 - Good${NC}"
    elif [[ $security_score -ge 50 ]]; then
        echo -e "${YELLOW}⚠ Security Score: $security_score/100 - Needs Improvement${NC}"
    else
        echo -e "${RED}🚨 Security Score: $security_score/100 - Critical Issues${NC}"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local instance_ip="${1:-}"
    local audit_type="${2:-all}"
    
    # Check if help is requested
    if [[ "$instance_ip" == "--help" || "$instance_ip" == "-h" ]]; then
        echo "Usage: $0 <instance-ip> [audit-type]"
        echo ""
        echo "Comprehensive security audit for AI Starter Kit"
        echo ""
        echo "Audit Types:"
        echo "  all         Run all security audits (default)"
        echo "  network     Network security audit only"
        echo "  iam         IAM and access control audit only"
        echo "  system      System security audit only"
        echo "  container   Container security audit only"
        echo "  credential  Credential and secret audit only"
        echo "  compliance  Compliance and best practices audit only"
        echo ""
        echo "Examples:"
        echo "  $0 54.123.456.789"
        echo "  $0 54.123.456.789 network"
        echo "  $0 54.123.456.789 compliance"
        exit 0
    fi
    
    if [[ -z "$instance_ip" ]]; then
        security_issue "Instance IP address is required"
        echo "Usage: $0 <instance-ip> [audit-type]"
        exit 1
    fi
    
    # Configure global variables
    KEY_NAME="${KEY_NAME:-ai-starter-kit-key}"
    STACK_NAME="${STACK_NAME:-ai-starter-kit}"
    
    separator "═══════════════════════════════════════════════════════════════════"
    log "🔒 AI Starter Kit - Security Audit and Compliance Validator"
    log "Instance IP: $instance_ip"
    log "Audit Type: $audit_type"
    log "Security Timeout: ${SECURITY_TIMEOUT}s"
    separator "═══════════════════════════════════════════════════════════════════"
    
    local overall_status=0
    
    # Run security audits based on type
    case "$audit_type" in
        "all")
            audit_network_security "$instance_ip" || overall_status=1
            audit_exposed_services "$instance_ip" || overall_status=1
            audit_iam_and_access "$instance_ip" || overall_status=1
            audit_system_security "$instance_ip" || overall_status=1
            audit_container_security "$instance_ip" || overall_status=1
            audit_credential_security "$instance_ip" || overall_status=1
            audit_compliance "$instance_ip" || overall_status=1
            ;;
        "network")
            audit_network_security "$instance_ip" || overall_status=1
            audit_exposed_services "$instance_ip" || overall_status=1
            ;;
        "iam")
            audit_iam_and_access "$instance_ip" || overall_status=1
            ;;
        "system")
            audit_system_security "$instance_ip" || overall_status=1
            ;;
        "container")
            audit_container_security "$instance_ip" || overall_status=1
            ;;
        "credential")
            audit_credential_security "$instance_ip" || overall_status=1
            ;;
        "compliance")
            audit_compliance "$instance_ip" || overall_status=1
            ;;
        *)
            security_issue "Unknown audit type: $audit_type"
            exit 1
            ;;
    esac
    
    # Generate final security report
    separator "═══════════════════════════════════════════════════════════════════"
    log "📋 SECURITY AUDIT RESULTS"
    separator "═══════════════════════════════════════════════════════════════════"
    
    generate_security_report
    
    local total_critical=$((${#SECURITY_ISSUES[@]} + ${#COMPLIANCE_ISSUES[@]}))
    
    if [[ $total_critical -eq 0 ]]; then
        security_pass "🛡️ Security audit completed - no critical issues found!"
    else
        security_issue "🚨 Security audit found $total_critical critical issues that require immediate attention"
        overall_status=1
    fi
    
    separator "═══════════════════════════════════════════════════════════════════"
    
    exit $overall_status
}

# Execute main function with all arguments
main "$@"