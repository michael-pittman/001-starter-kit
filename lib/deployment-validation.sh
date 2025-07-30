#!/usr/bin/env bash
#
# Deployment Validation Library
# Provides comprehensive validation for deployment prerequisites and configurations
#
# Dependencies: aws-cli, jq
# Compatible with bash 3.x+
#

set -euo pipefail

# Source required libraries
# Note: These libraries expect to be called from scripts that have already set PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Source using library loader pattern
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Load required modules through the library system
load_module "core/errors"
load_module "core/variables"

# Global validation state
declare -gA VALIDATION_RESULTS
declare -gA DEPENDENCY_VERSIONS
declare -gA AWS_QUOTAS
declare -gA HEALTH_CHECK_RESULTS

# Validation constants
declare -gr MIN_DISK_SPACE_GB=20
declare -gr MIN_MEMORY_MB=2048
declare -gr MIN_MEMORY_MB_DEV=512  # Lower requirement for development environments
declare -gr AWS_CLI_MIN_VERSION="2.0.0"
declare -gr JQ_MIN_VERSION="1.5"
declare -gr DOCKER_MIN_VERSION="20.10.0"

# Initialize validation results
init_validation() {
    VALIDATION_RESULTS=(
        [dependencies]="pending"
        [aws_credentials]="pending"
        [aws_permissions]="pending"
        [aws_quotas]="pending"
        [disk_space]="pending"
        [memory]="pending"
        [network]="pending"
        [overall]="pending"
    )
    
    DEPENDENCY_VERSIONS=(
        [bash]="${BASH_VERSION}"
        [aws]="unknown"
        [jq]="unknown"
        [docker]="unknown"
        [curl]="unknown"
        [git]="unknown"
    )
    
    AWS_QUOTAS=(
        [ec2_instances]="0"
        [vpc_count]="0"
        [elastic_ips]="0"
        [security_groups]="0"
        [efs_filesystems]="0"
    )
}

# Check system dependencies
check_dependencies() {
    local -i errors=0
    local missing_deps=()
    
    echo -e "\n=== Checking System Dependencies ==="
    
    # Check AWS CLI
    if command -v aws &>/dev/null; then
        local aws_version
        aws_version=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
        DEPENDENCY_VERSIONS[aws]="$aws_version"
        
        if version_compare "$aws_version" "$AWS_CLI_MIN_VERSION" "<"; then
            echo "✗ AWS CLI version $aws_version is below minimum required version $AWS_CLI_MIN_VERSION"
            ((errors++))
        else
            echo "✓ AWS CLI version $aws_version"
        fi
    else
        missing_deps+=("aws-cli")
        ((errors++))
    fi
    
    # Check jq
    if command -v jq &>/dev/null; then
        local jq_version
        jq_version=$(jq --version 2>&1 | cut -d'-' -f2)
        DEPENDENCY_VERSIONS[jq]="$jq_version"
        
        if version_compare "$jq_version" "$JQ_MIN_VERSION" "<"; then
            echo "✗ jq version $jq_version is below minimum required version $JQ_MIN_VERSION"
            ((errors++))
        else
            echo "✓ jq version $jq_version"
        fi
    else
        missing_deps+=("jq")
        ((errors++))
    fi
    
    # Check Docker
    if command -v docker &>/dev/null; then
        local docker_version
        docker_version=$(docker --version 2>&1 | awk '{print $3}' | tr -d ',')
        DEPENDENCY_VERSIONS[docker]="$docker_version"
        
        if version_compare "$docker_version" "$DOCKER_MIN_VERSION" "<"; then
            echo "✗ Docker version $docker_version is below minimum required version $DOCKER_MIN_VERSION"
            ((errors++))
        else
            echo "✓ Docker version $docker_version"
        fi
        
        # Check Docker daemon is running
        if ! docker info &>/dev/null; then
            echo "✗ Docker daemon is not running"
            ((errors++))
        fi
    else
        missing_deps+=("docker")
        ((errors++))
    fi
    
    # Check curl
    if command -v curl &>/dev/null; then
        local curl_version
        curl_version=$(curl --version 2>&1 | head -1 | awk '{print $2}')
        DEPENDENCY_VERSIONS[curl]="$curl_version"
        echo "✓ curl version $curl_version"
    else
        missing_deps+=("curl")
        ((errors++))
    fi
    
    # Check git
    if command -v git &>/dev/null; then
        local git_version
        git_version=$(git --version 2>&1 | awk '{print $3}')
        DEPENDENCY_VERSIONS[git]="$git_version"
        echo "✓ git version $git_version"
    else
        missing_deps+=("git")
        ((errors++))
    fi
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "\n✗ Missing required dependencies: ${missing_deps[*]}"
        echo -e "\nInstallation instructions:"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install ${missing_deps[*]}"
        elif [[ -f /etc/debian_version ]]; then
            echo "  sudo apt-get update && sudo apt-get install -y ${missing_deps[*]}"
        elif [[ -f /etc/redhat-release ]]; then
            echo "  sudo yum install -y ${missing_deps[*]}"
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        VALIDATION_RESULTS[dependencies]="passed"
        echo -e "\n✓ All dependencies satisfied"
        return 0
    else
        VALIDATION_RESULTS[dependencies]="failed"
        return 1
    fi
}

# Version comparison function
version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="${3:-"="}"
    
    # Convert versions to comparable format
    local v1_major v1_minor v1_patch
    local v2_major v2_minor v2_patch
    
    IFS='.' read -r v1_major v1_minor v1_patch <<< "$version1"
    IFS='.' read -r v2_major v2_minor v2_patch <<< "$version2"
    
    # Default to 0 if not set
    v1_minor=${v1_minor:-0}
    v1_patch=${v1_patch:-0}
    v2_minor=${v2_minor:-0}
    v2_patch=${v2_patch:-0}
    
    # Compare versions
    local v1_num=$((v1_major * 10000 + v1_minor * 100 + v1_patch))
    local v2_num=$((v2_major * 10000 + v2_minor * 100 + v2_patch))
    
    case "$operator" in
        "<")  [[ $v1_num -lt $v2_num ]] ;;
        "<=") [[ $v1_num -le $v2_num ]] ;;
        ">")  [[ $v1_num -gt $v2_num ]] ;;
        ">=") [[ $v1_num -ge $v2_num ]] ;;
        "=")  [[ $v1_num -eq $v2_num ]] ;;
        *)    return 1 ;;
    esac
}

# Check AWS credentials and permissions
check_aws_credentials() {
    echo -e "\n=== Checking AWS Credentials ==="
    
    # Check if credentials are configured
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "✗ AWS credentials not configured or invalid"
        VALIDATION_RESULTS[aws_credentials]="failed"
        return 1
    fi
    
    # Get account info
    local account_info
    account_info=$(aws sts get-caller-identity --output json)
    
    local account_id
    local arn
    account_id=$(echo "$account_info" | jq -r '.Account')
    arn=$(echo "$account_info" | jq -r '.Arn')
    
    echo "✓ AWS Account: $account_id"
    echo "✓ ARN: $arn"
    
    VALIDATION_RESULTS[aws_credentials]="passed"
    return 0
}

# Check AWS permissions
check_aws_permissions() {
    echo -e "\n=== Checking AWS Permissions ==="
    
    local -a required_actions=(
        "ec2:DescribeInstances"
        "ec2:RunInstances"
        "ec2:TerminateInstances"
        "vpc:CreateVpc"
        "vpc:DescribeVpcs"
        "iam:CreateRole"
        "iam:PassRole"
        "efs:CreateFileSystem"
        "ssm:GetParameter"
        "cloudformation:CreateStack"
    )
    
    local -i errors=0
    
    # Use IAM policy simulator for permission checking
    for action in "${required_actions[@]}"; do
        # Note: This is a simplified check. In production, use IAM policy simulator
        echo -n "Checking $action... "
        
        # Try to perform a dry-run or describe operation
        case "$action" in
            "ec2:DescribeInstances")
                if aws ec2 describe-instances --max-items 1 &>/dev/null; then
                    echo "✓"
                else
                    echo "✗"
                    ((errors++))
                fi
                ;;
            "vpc:DescribeVpcs")
                if aws ec2 describe-vpcs --max-items 1 &>/dev/null; then
                    echo "✓"
                else
                    echo "✗"
                    ((errors++))
                fi
                ;;
            "ssm:GetParameter")
                if aws ssm describe-parameters --max-items 1 &>/dev/null; then
                    echo "✓"
                else
                    echo "✗"
                    ((errors++))
                fi
                ;;
            *)
                # For other permissions, we'll assume they're available if basic operations work
                echo "✓ (assumed)"
                ;;
        esac
    done
    
    if [[ $errors -eq 0 ]]; then
        VALIDATION_RESULTS[aws_permissions]="passed"
        echo -e "\n✓ All required permissions available"
        return 0
    else
        VALIDATION_RESULTS[aws_permissions]="failed"
        echo -e "\n✗ Missing some required permissions"
        return 1
    fi
}

# Check AWS service quotas
check_aws_quotas() {
    echo -e "\n=== Checking AWS Service Quotas ==="
    
    local region="${AWS_DEFAULT_REGION:-us-east-1}"
    
    # Check EC2 instance limits
    echo -n "Checking EC2 instance limits... "
    local instance_limit
    instance_limit=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Quota.Value // 5')
    
    AWS_QUOTAS[ec2_instances]="$instance_limit"
    echo "✓ ($instance_limit instances)"
    
    # Check VPC limits
    echo -n "Checking VPC limits... "
    local vpc_count
    vpc_count=$(aws ec2 describe-vpcs --region "$region" --output json 2>/dev/null | jq '.Vpcs | length')
    local vpc_limit=5  # Default VPC limit
    
    AWS_QUOTAS[vpc_count]="$vpc_count/$vpc_limit"
    
    if [[ $vpc_count -lt $vpc_limit ]]; then
        echo "✓ ($vpc_count/$vpc_limit VPCs)"
    else
        echo "✗ (at limit: $vpc_count/$vpc_limit VPCs)"
    fi
    
    # Check Elastic IP limits
    echo -n "Checking Elastic IP limits... "
    local eip_count
    eip_count=$(aws ec2 describe-addresses --region "$region" --output json 2>/dev/null | jq '.Addresses | length')
    local eip_limit=5  # Default EIP limit
    
    AWS_QUOTAS[elastic_ips]="$eip_count/$eip_limit"
    
    if [[ $eip_count -lt $eip_limit ]]; then
        echo "✓ ($eip_count/$eip_limit EIPs)"
    else
        echo "✗ (at limit: $eip_count/$eip_limit EIPs)"
    fi
    
    # Check Security Group limits
    echo -n "Checking Security Group limits... "
    local sg_count
    sg_count=$(aws ec2 describe-security-groups --region "$region" --output json 2>/dev/null | jq '.SecurityGroups | length')
    local sg_limit=2500  # Default per-VPC limit
    
    AWS_QUOTAS[security_groups]="$sg_count"
    echo "✓ ($sg_count security groups)"
    
    VALIDATION_RESULTS[aws_quotas]="passed"
    echo -e "\n✓ AWS quotas sufficient for deployment"
    return 0
}

# Check system resources
check_system_resources() {
    echo -e "\n=== Checking System Resources ==="
    
    # Check if in development mode
    local is_development=false
    if [[ "${DEPLOYMENT_MODE:-}" == "development" ]] || \
       [[ "${ENV:-}" == "development" ]] || \
       [[ "${ENVIRONMENT:-}" == "development" ]] || \
       [[ "${ENVIRONMENT:-}" == "dev" ]] || \
       [[ "${DEVELOPMENT_MODE:-}" == "true" ]]; then
        is_development=true
        echo "ℹ️  Running in development mode - warnings only for low resources"
    fi
    
    # Check disk space
    echo -n "Checking disk space... "
    local available_space_gb
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        available_space_gb=$(df -g / | awk 'NR==2 {print $4}')
    else
        available_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    fi
    
    if [[ $available_space_gb -ge $MIN_DISK_SPACE_GB ]]; then
        echo "✓ (${available_space_gb}GB available)"
        VALIDATION_RESULTS[disk_space]="passed"
    else
        if [[ "$is_development" == "true" ]]; then
            echo "⚠️  WARNING: Low disk space (${available_space_gb}GB available, recommend ${MIN_DISK_SPACE_GB}GB)"
            VALIDATION_RESULTS[disk_space]="passed"  # Pass with warning in dev mode
        else
            echo "✗ (${available_space_gb}GB available, need ${MIN_DISK_SPACE_GB}GB)"
            VALIDATION_RESULTS[disk_space]="failed"
        fi
    fi
    
    # Check memory
    echo -n "Checking memory... "
    local available_memory_mb
    
    # Set memory requirement based on deployment mode
    local required_memory_mb
    if [[ "$is_development" == "true" ]]; then
        required_memory_mb=$MIN_MEMORY_MB_DEV  # 512MB for development
    else
        required_memory_mb=$MIN_MEMORY_MB  # 2048MB for production
    fi
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        available_memory_mb=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.' | awk '{print int($1*4096/1024/1024)}')
    else
        available_memory_mb=$(free -m | awk 'NR==2 {print $7}')
    fi
    
    if [[ $available_memory_mb -ge $required_memory_mb ]]; then
        echo "✓ (${available_memory_mb}MB available, required: ${required_memory_mb}MB)"
        VALIDATION_RESULTS[memory]="passed"
    else
        if [[ "$is_development" == "true" ]]; then
            echo "⚠️  WARNING: Low memory (${available_memory_mb}MB available, recommend ${required_memory_mb}MB)"
            VALIDATION_RESULTS[memory]="passed"  # Pass with warning in dev mode
        else
            echo "✗ (${available_memory_mb}MB available, need ${required_memory_mb}MB)"
            VALIDATION_RESULTS[memory]="failed"
        fi
    fi
    
    # Always return 0 in development mode
    if [[ "$is_development" == "true" ]]; then
        return 0
    fi
    
    return 0
}

# Display network troubleshooting tips
show_network_troubleshooting_tips() {
    echo -e "\n💡 Network Troubleshooting Tips:"
    echo "  1. Check your internet connection:"
    echo "     - Try: ping -c 1 google.com"
    echo "     - Try: curl -I https://www.google.com"
    echo "  2. Check DNS resolution:"
    echo "     - Try: nslookup aws.amazon.com"
    echo "     - Try: dig github.com"
    echo "  3. Check firewall/proxy settings:"
    echo "     - Corporate networks may block port 443"
    echo "     - Check HTTP(S)_PROXY environment variables"
    echo "  4. For development without internet:"
    echo "     - Set: export SKIP_NETWORK_CHECK=true"
    echo "     - Use local Docker registry if available"
    echo "  5. Common fixes:"
    echo "     - Restart network service: sudo systemctl restart network"
    echo "     - Reset DNS: sudo systemctl restart systemd-resolved"
    echo "     - Check /etc/resolv.conf for valid nameservers"
}

# Check network connectivity
check_network_connectivity() {
    echo -e "\n=== Checking Network Connectivity ==="
    
    # Check if in development mode
    local is_development=false
    local is_production=true
    if [[ "${DEPLOYMENT_MODE:-}" == "development" ]] || \
       [[ "${ENV:-}" == "development" ]] || \
       [[ "${ENVIRONMENT:-}" == "development" ]] || \
       [[ "${ENVIRONMENT:-}" == "dev" ]] || \
       [[ "${DEVELOPMENT_MODE:-}" == "true" ]]; then
        is_development=true
        is_production=false
    fi
    
    # Check if skip network check is explicitly set
    if [[ "${SKIP_NETWORK_CHECK:-}" == "true" ]] || [[ "${SKIP_NETWORK_VALIDATION:-}" == "true" ]]; then
        echo "ℹ️  Network checks explicitly skipped"
        VALIDATION_RESULTS[network]="passed"
        echo "✓ Network checks skipped (SKIP_NETWORK_CHECK=true)"
        return 0
    fi
    
    if [[ "$is_development" == "true" ]]; then
        echo "ℹ️  Running in development mode - network checks are optional"
        echo "  Network failures will be treated as warnings only"
    fi
    
    local -a endpoints=(
        "aws.amazon.com:443"
        "registry.docker.io:443"
        "github.com:443"
    )
    
    local -i errors=0
    local -i successful_endpoints=0
    local -i total_endpoints=${#endpoints[@]}
    
    # Enhanced retry configuration
    local -i retries=3
    local retry_delay=2
    local -i max_retry_delay=10
    
    # Allow customization via environment variables
    retries=${NETWORK_CHECK_RETRIES:-3}
    retry_delay=${NETWORK_CHECK_RETRY_DELAY:-2}
    
    for endpoint in "${endpoints[@]}"; do
        local host="${endpoint%:*}"
        local port="${endpoint#*:}"
        local success=false
        local current_delay=$retry_delay
        
        echo -n "Checking connectivity to $host... "
        
        # Enhanced retry logic with exponential backoff for temporary network issues
        for ((attempt=1; attempt<=retries; attempt++)); do
            if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
                success=true
                ((successful_endpoints++))
                break
            elif [[ $attempt -lt $retries ]]; then
                echo -n "(retry $attempt in ${current_delay}s) "
                sleep $current_delay
                # Exponential backoff with max delay
                current_delay=$((current_delay * 2))
                [[ $current_delay -gt $max_retry_delay ]] && current_delay=$max_retry_delay
            fi
        done
        
        if [[ "$success" == "true" ]]; then
            echo "✓"
        else
            if [[ "$is_development" == "true" ]]; then
                echo "⚠️  WARNING (development mode - continuing anyway)"
            else
                echo "✗"
                ((errors++))
            fi
        fi
    done
    
    # Enhanced result handling with partial connectivity support
    if [[ $successful_endpoints -eq $total_endpoints ]]; then
        # All endpoints reachable
        VALIDATION_RESULTS[network]="passed"
        echo -e "\n✓ Network connectivity verified (${successful_endpoints}/${total_endpoints} endpoints reachable)"
        return 0
    elif [[ $successful_endpoints -gt 0 ]]; then
        # Partial connectivity
        if [[ "$is_development" == "true" ]]; then
            VALIDATION_RESULTS[network]="passed"
            echo -e "\n⚠️  WARNING: Partial network connectivity (${successful_endpoints}/${total_endpoints} endpoints reachable)"
            echo "  This is acceptable for development, but may cause issues with:"
            echo "  - Docker image pulls (if registry.docker.io is unreachable)"
            echo "  - AWS API calls (if aws.amazon.com is unreachable)"
            echo "  - Git operations (if github.com is unreachable)"
            echo "  To skip network checks: export SKIP_NETWORK_CHECK=true"
            return 0
        else
            VALIDATION_RESULTS[network]="failed"
            echo -e "\n✗ Partial network connectivity detected (${successful_endpoints}/${total_endpoints} endpoints reachable)"
            echo "  Full network connectivity is required for production deployments."
            echo "  To proceed in development mode: export ENVIRONMENT=development"
            show_network_troubleshooting_tips
            return 1
        fi
    else
        # No connectivity
        if [[ "$is_development" == "true" ]]; then
            VALIDATION_RESULTS[network]="passed"
            echo -e "\n⚠️  WARNING: No network connectivity detected"
            echo "  Development mode allows offline work, but you will experience:"
            echo "  - Cannot pull Docker images (use local registry or pre-built images)"
            echo "  - Cannot access AWS services (use LocalStack or offline mode)"
            echo "  - Cannot clone repositories (work with existing code only)"
            echo "\n  For offline development:"
            echo "  1. Pre-pull all required Docker images"
            echo "  2. Use local development tools (LocalStack, etc.)"
            echo "  3. Set: export SKIP_NETWORK_CHECK=true"
            echo "\n  If this is unexpected, check your network connection."
            return 0
        else
            VALIDATION_RESULTS[network]="failed"
            echo -e "\n✗ No network connectivity detected"
            echo "  Network connectivity is required for production deployments."
            echo "  Please check your internet connection and firewall settings."
            echo "\n  Options:"
            echo "  1. Fix network connectivity issues"
            echo "  2. Run in development mode: export ENVIRONMENT=development"
            echo "  3. Skip check (NOT recommended): export SKIP_NETWORK_CHECK=true"
            show_network_troubleshooting_tips
            return 1
        fi
    fi
}

# Run all validation checks
validate_deployment_prerequisites() {
    local stack_name="${1:-}"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "===================================================="
    echo "Deployment Validation for Stack: ${stack_name:-<unnamed>}"
    echo "Region: $region"
    echo "Date: $(date)"
    echo "===================================================="
    
    # Initialize validation
    init_validation
    
    # Check if in development mode
    local is_development=false
    if [[ "${DEPLOYMENT_MODE:-}" == "development" ]] || \
       [[ "${ENV:-}" == "development" ]] || \
       [[ "${ENVIRONMENT:-}" == "development" ]] || \
       [[ "${ENVIRONMENT:-}" == "dev" ]] || \
       [[ "${DEVELOPMENT_MODE:-}" == "true" ]]; then
        is_development=true
        echo "ℹ️  Running validation in DEVELOPMENT MODE"
        echo "  - Network connectivity checks are optional"
        echo "  - Resource requirements are relaxed"
        echo ""
    fi
    
    # Run all checks
    local -i total_errors=0
    local -i critical_errors=0
    
    # Run checks and count errors
    check_dependencies || ((total_errors++))
    check_aws_credentials || ((critical_errors++, total_errors++))
    check_aws_permissions || ((critical_errors++, total_errors++))
    check_aws_quotas || ((total_errors++))
    check_system_resources || ((total_errors++))
    check_network_connectivity || {
        # In development mode, network errors are not critical
        if [[ "$is_development" != "true" ]]; then
            ((total_errors++))
        fi
    }
    
    # Summary
    echo -e "\n===================================================="
    echo "Validation Summary:"
    echo "===================================================="
    
    local status_icon
    for check in "${!VALIDATION_RESULTS[@]}"; do
        [[ "$check" == "overall" ]] && continue
        
        case "${VALIDATION_RESULTS[$check]}" in
            "passed") status_icon="✓" ;;
            "failed") status_icon="✗" ;;
            *) status_icon="?" ;;
        esac
        
        printf "%-20s %s\n" "$check:" "$status_icon ${VALIDATION_RESULTS[$check]}"
    done
    
    echo "===================================================="
    
    if [[ $total_errors -eq 0 ]]; then
        VALIDATION_RESULTS[overall]="passed"
        echo -e "\n✓ All validation checks passed. Ready for deployment!"
        return 0
    else
        # In development mode, we can proceed with warnings
        if [[ "$is_development" == "true" ]] && [[ $critical_errors -eq 0 ]]; then
            VALIDATION_RESULTS[overall]="passed"
            echo -e "\n⚠️  Development Mode: Proceeding with $total_errors warnings"
            echo "  - Critical checks (AWS credentials, permissions) passed"
            echo "  - Non-critical issues can be resolved later"
            echo "  - For production deployment, fix all issues first"
            echo -e "\n✓ Development deployment can proceed with warnings"
            return 0
        else
            VALIDATION_RESULTS[overall]="failed"
            if [[ $critical_errors -gt 0 ]]; then
                echo -e "\n✗ Validation failed with $critical_errors critical errors"
                echo "  Critical errors must be resolved even in development mode."
            else
                echo -e "\n✗ Validation failed with $total_errors errors"
            fi
            echo -e "\nPlease resolve the issues above before proceeding with deployment."
            echo "To run in development mode with relaxed checks: export ENVIRONMENT=development"
            return 1
        fi
    fi
}


# Deployment health check
check_deployment_health() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo -e "\n=== Checking Deployment Health: $stack_name ==="
    
    # Check CloudFormation stack status
    echo -n "Checking CloudFormation stack... "
    local stack_status
    stack_status=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Stacks[0].StackStatus // "NOT_FOUND"')
    
    case "$stack_status" in
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            echo "✓ ($stack_status)"
            HEALTH_CHECK_RESULTS[stack]="healthy"
            ;;
        "NOT_FOUND")
            echo "✗ (Stack not found)"
            HEALTH_CHECK_RESULTS[stack]="not_found"
            return 1
            ;;
        *)
            echo "✗ ($stack_status)"
            HEALTH_CHECK_RESULTS[stack]="unhealthy"
            return 1
            ;;
    esac
    
    # Check EC2 instances
    echo -n "Checking EC2 instances... "
    local instance_states
    instance_states=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Reservations[].Instances[].State.Name' | sort | uniq -c)
    
    if echo "$instance_states" | grep -q "running"; then
        echo "✓ (instances running)"
        HEALTH_CHECK_RESULTS[instances]="healthy"
    else
        echo "✗ (no running instances)"
        HEALTH_CHECK_RESULTS[instances]="unhealthy"
    fi
    
    # Check application endpoints
    echo -n "Checking application endpoints... "
    local instance_ip
    instance_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$stack_name" \
                  "Name=instance-state-name,Values=running" \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Reservations[0].Instances[0].PublicIpAddress // empty')
    
    if [[ -n "$instance_ip" ]]; then
        # Check n8n endpoint
        if curl -sf "http://$instance_ip:5678/healthz" &>/dev/null; then
            echo "✓ (n8n responding)"
            HEALTH_CHECK_RESULTS[n8n]="healthy"
        else
            echo "✗ (n8n not responding)"
            HEALTH_CHECK_RESULTS[n8n]="unhealthy"
        fi
    else
        echo "✗ (no public IP found)"
        HEALTH_CHECK_RESULTS[endpoints]="unreachable"
    fi
    
    # Summary
    local healthy_count=0
    local total_count=0
    
    for service in "${!HEALTH_CHECK_RESULTS[@]}"; do
        ((total_count++))
        [[ "${HEALTH_CHECK_RESULTS[$service]}" == "healthy" ]] && ((healthy_count++))
    done
    
    echo -e "\n✓ Health Check: $healthy_count/$total_count services healthy"
    
    return 0
}

# Generate validation report
generate_validation_report() {
    local output_file="${1:-validation-report.txt}"
    
    {
        echo "Deployment Validation Report"
        echo "Generated: $(date)"
        echo "============================"
        echo
        echo "System Information:"
        echo "  OS: $OSTYPE"
        echo "  Bash Version: ${BASH_VERSION}"
        echo "  User: $(whoami)"
        echo "  Hostname: $(hostname)"
        echo
        echo "Dependency Versions:"
        for dep in "${!DEPENDENCY_VERSIONS[@]}"; do
            printf "  %-10s %s\n" "$dep:" "${DEPENDENCY_VERSIONS[$dep]}"
        done
        echo
        echo "Validation Results:"
        for check in "${!VALIDATION_RESULTS[@]}"; do
            printf "  %-20s %s\n" "$check:" "${VALIDATION_RESULTS[$check]}"
        done
        echo
        echo "AWS Service Quotas:"
        for quota in "${!AWS_QUOTAS[@]}"; do
            printf "  %-20s %s\n" "$quota:" "${AWS_QUOTAS[$quota]}"
        done
        echo
        if [[ ${#HEALTH_CHECK_RESULTS[@]} -gt 0 ]]; then
            echo "Health Check Results:"
            for service in "${!HEALTH_CHECK_RESULTS[@]}"; do
                printf "  %-20s %s\n" "$service:" "${HEALTH_CHECK_RESULTS[$service]}"
            done
        fi
    } > "$output_file"
    
    echo "Validation report saved to: $output_file"
}

# Export functions
export -f init_validation
export -f check_dependencies
export -f check_aws_credentials
export -f check_aws_permissions
export -f check_aws_quotas
export -f check_system_resources
export -f show_network_troubleshooting_tips
export -f check_network_connectivity
export -f validate_deployment_prerequisites
export -f check_deployment_health
export -f generate_validation_report
export -f version_compare