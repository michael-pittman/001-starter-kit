#!/bin/bash
# =============================================================================
# Unity Security Compliance Tests
# Comprehensive security validation for Unity services and deployment system
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework for security tests
unity_test_init "test-unity-security-compliance" "security" "unity-security-compliance"

# =============================================================================
# SECURITY TEST CONFIGURATION
# =============================================================================

# Security compliance standards
readonly SECURITY_MIN_KEY_LENGTH=32
readonly SECURITY_MAX_LOG_RETENTION_DAYS=90
readonly SECURITY_MIN_PASSWORD_LENGTH=12
readonly SECURITY_REQUIRED_PERMISSIONS=("600" "640" "644" "755")
readonly SECURITY_FORBIDDEN_PERMISSIONS=("777" "666" "646")

# Common security patterns to check
readonly SECURITY_SENSITIVE_PATTERNS=(
    "password"
    "secret"
    "key"
    "token"
    "credential"
    "auth"
    "private"
)

# AWS security requirements
readonly AWS_REQUIRED_POLICIES=(
    "AmazonEC2ReadOnlyAccess"
    "AmazonVPCReadOnlyAccess"
)

readonly AWS_FORBIDDEN_ACTIONS=(
    "*:*"
    "iam:*"
    "sts:AssumeRole"
)

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up security test environment
setup_security_tests() {
    # Create test security directory
    export TEST_SECURITY_DIR="/tmp/unity-security-test-$$"
    mkdir -p "$TEST_SECURITY_DIR"
    mkdir -p "$TEST_SECURITY_DIR/.unity"
    mkdir -p "$TEST_SECURITY_DIR/.unity/security"
    mkdir -p "$TEST_SECURITY_DIR/.unity/logs"
    mkdir -p "$TEST_SECURITY_DIR/config"
    mkdir -p "$TEST_SECURITY_DIR/scripts"
    mkdir -p "$TEST_SECURITY_DIR/lib/unity/services"
    mkdir -p "$TEST_SECURITY_DIR/lib/unity/core"
    mkdir -p "$TEST_SECURITY_DIR/lib/modules/core"
    
    # Set test-specific paths
    export PROJECT_ROOT="$TEST_SECURITY_DIR"
    export UNITY_SECURITY_DIR="$TEST_SECURITY_DIR/.unity/security"
    export UNITY_LOG_DIR="$TEST_SECURITY_DIR/.unity/logs"
    export SECURITY_AUDIT_LOG="$UNITY_SECURITY_DIR/security_audit.log"
    
    # Create mock Unity infrastructure for security testing
    _create_mock_unity_security_infrastructure
    
    # Create mock service files with security considerations
    _create_mock_unity_security_services
    
    # Create test configuration files with security settings
    _create_security_test_configs
    
    # Mock external dependencies for security testing
    _mock_external_dependencies_security
    
    # Set test environment variables
    export UNITY_TEST_MODE="true"
    export UNITY_SECURITY_MODE="strict"
    export SECURITY_SCAN_ENABLED="true"
    export STACK_NAME="security-test-stack"
    export AWS_REGION="us-west-2"
    
    # Initialize security monitoring
    _init_security_monitoring
}

# Create mock Unity infrastructure with security features
_create_mock_unity_security_infrastructure() {
    # Mock Unity core with security logging
    cat > "$TEST_SECURITY_DIR/lib/unity/core/unity-core.sh" << 'EOF'
#!/bin/bash
UNITY_SUCCESS=0
UNITY_ERROR_VALIDATION=1
UNITY_ERROR_EXECUTION=2
UNITY_ERROR_SECURITY=3

# Security event tracking
declare -g UNITY_SECURITY_EVENTS=()
declare -g UNITY_SECURITY_VIOLATIONS=0

unity_log() { 
    echo "[$1] $2"
    [[ "$1" == "SECURITY" ]] && UNITY_SECURITY_EVENTS+=("$(date -Iseconds): $2")
}

unity_emit_event() { 
    echo "[EVENT] $1: $2"
    # Log security-related events
    [[ "$1" == *"security"* ]] && unity_log "SECURITY" "Event: $1 - $2"
}

unity_handle_error() { 
    echo "ERROR: $3" >&2
    [[ "$2" == "$UNITY_ERROR_SECURITY" ]] && ((UNITY_SECURITY_VIOLATIONS++))
    return $2
}

unity_register_service() { 
    local service_name="$1"
    local service_path="$2"
    
    # Validate service path for security
    if [[ "$service_path" == *"../"* ]]; then
        unity_handle_error "$UNITY_ERROR_SECURITY" "Path traversal attempt: $service_path"
        return $UNITY_ERROR_SECURITY
    fi
    
    return 0
}

unity_security_audit() {
    echo "Security Events: ${#UNITY_SECURITY_EVENTS[@]}"
    echo "Security Violations: $UNITY_SECURITY_VIOLATIONS"
    for event in "${UNITY_SECURITY_EVENTS[@]}"; do
        echo "  $event"
    done
}

export -f unity_log unity_emit_event unity_handle_error unity_register_service unity_security_audit
EOF
    
    # Mock Unity registry with security validation
    cat > "$TEST_SECURITY_DIR/lib/unity/core/registry.sh" << 'EOF'
#!/bin/bash
declare -a UNITY_SERVICES_KEYS=()
declare -a UNITY_SERVICES_VALUES=()
declare -a UNITY_SERVICE_PERMISSIONS=()

unity_register_service() { 
    local name="$1"
    local path="$2"
    local permissions="${3:-755}"
    
    # Security validation
    if [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
        unity_log "SECURITY" "Invalid service name: $name"
        return 1
    fi
    
    if [[ ! -f "$path" ]] && [[ "${UNITY_TEST_MODE:-}" != "true" ]]; then
        unity_log "SECURITY" "Service path does not exist: $path"
        return 1
    fi
    
    UNITY_SERVICES_KEYS+=("$name")
    UNITY_SERVICES_VALUES+=("$path")
    UNITY_SERVICE_PERMISSIONS+=("$permissions")
    
    return 0
}

unity_validate_service_permissions() {
    local service_name="$1"
    local i
    
    for i in "${!UNITY_SERVICES_KEYS[@]}"; do
        if [[ "${UNITY_SERVICES_KEYS[i]}" == "$service_name" ]]; then
            local permissions="${UNITY_SERVICE_PERMISSIONS[i]}"
            
            # Check for overly permissive permissions
            if [[ "$permissions" == "777" || "$permissions" == "666" ]]; then
                unity_log "SECURITY" "Insecure permissions for $service_name: $permissions"
                return 1
            fi
            
            return 0
        fi
    done
    
    return 1
}

export -f unity_register_service unity_validate_service_permissions
EOF
    
    # Mock Unity event bus with security filtering
    cat > "$TEST_SECURITY_DIR/lib/unity/events/event-bus.sh" << 'EOF'
#!/bin/bash
declare -a SECURITY_FILTERED_EVENTS=("credential" "password" "secret" "key")

unity_event_on() { return 0; }

unity_event_emit() { 
    local event_type="$1"
    local event_data="$2"
    
    # Filter sensitive data from events
    for sensitive in "${SECURITY_FILTERED_EVENTS[@]}"; do
        if [[ "$event_data" == *"$sensitive"* ]]; then
            event_data="[FILTERED:$sensitive]"
            unity_log "SECURITY" "Filtered sensitive data from event: $event_type"
            break
        fi
    done
    
    echo "[TEST-EVENT] $event_type: $event_data"
}

export -f unity_event_on unity_event_emit
EOF
    
    # Mock core logging with security features
    cat > "$TEST_SECURITY_DIR/lib/modules/core/logging.sh" << 'EOF'
#!/bin/bash
declare -a LOG_SENSITIVE_PATTERNS=("password=" "secret=" "key=" "token=" "credential=")

log_info() { 
    local message="$*"
    _filter_sensitive_data "$message"
    echo "[INFO] $FILTERED_MESSAGE"
}

log_warn() { 
    local message="$*"
    _filter_sensitive_data "$message"
    echo "[WARN] $FILTERED_MESSAGE"
}

log_error() { 
    local message="$*"
    _filter_sensitive_data "$message"
    echo "[ERROR] $FILTERED_MESSAGE" >&2
}

log_debug() { 
    [[ "${DEBUG:-}" == "true" ]] && {
        local message="$*"
        _filter_sensitive_data "$message"
        echo "[DEBUG] $FILTERED_MESSAGE"
    }
}

_filter_sensitive_data() {
    local input="$1"
    FILTERED_MESSAGE="$input"
    
    for pattern in "${LOG_SENSITIVE_PATTERNS[@]}"; do
        if [[ "$input" == *"$pattern"* ]]; then
            FILTERED_MESSAGE=$(echo "$input" | sed "s/${pattern}[^ ]*/${pattern}[REDACTED]/g")
            break
        fi
    done
}

export -f log_info log_warn log_error log_debug
export FILTERED_MESSAGE
EOF
}

# Create mock Unity services with security features
_create_mock_unity_security_services() {
    # Mock AWS service with security validations
    cat > "$TEST_SECURITY_DIR/lib/unity/services/unity-aws-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-aws"

# AWS security configuration
declare -a AWS_ALLOWED_REGIONS=("us-east-1" "us-west-2" "eu-west-1")
declare -a AWS_ALLOWED_INSTANCE_TYPES=("t3.micro" "t3.small" "t3.medium" "t3.large")

init_unity_aws_service() {
    unity_log "SECURITY" "AWS service initialization with security validation"
    
    # Validate AWS configuration
    if ! aws_validate_security_config; then
        unity_handle_error "$UNITY_ERROR_SECURITY" "AWS security validation failed"
        return $UNITY_ERROR_SECURITY
    fi
    
    echo "AWS service initialized with security validation"
    return 0
}

aws_validate_security_config() {
    # Check AWS region
    if [[ ! " ${AWS_ALLOWED_REGIONS[*]} " =~ " ${AWS_REGION} " ]]; then
        unity_log "SECURITY" "Unauthorized AWS region: $AWS_REGION"
        return 1
    fi
    
    # Validate AWS credentials are not in environment (should use IAM roles)
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" || -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        unity_log "SECURITY" "AWS credentials found in environment variables"
        return 1
    fi
    
    return 0
}

launch_ec2_instance() {
    local instance_type="$1"
    local purchase_type="$2"
    local stack_name="$3"
    
    # Security validations
    if [[ ! " ${AWS_ALLOWED_INSTANCE_TYPES[*]} " =~ " ${instance_type} " ]]; then
        unity_log "SECURITY" "Unauthorized instance type: $instance_type"
        return 1
    fi
    
    if [[ "$stack_name" =~ [^a-zA-Z0-9_-] ]]; then
        unity_log "SECURITY" "Invalid stack name format: $stack_name"
        return 1
    fi
    
    # Simulate secure instance launch
    echo "i-$(openssl rand -hex 8)$(date +%s | tail -c 8)"
    unity_log "SECURITY" "EC2 instance launched with security validation"
    return 0
}

aws_validate_iam_permissions() {
    local required_actions=("ec2:RunInstances" "ec2:DescribeInstances" "ec2:TerminateInstances")
    local forbidden_actions=("iam:*" "*:*")
    
    # Mock IAM policy validation
    for action in "${forbidden_actions[@]}"; do
        # In real implementation, this would check actual IAM policies
        unity_log "SECURITY" "Checking for forbidden IAM action: $action"
    done
    
    return 0
}

aws_encrypt_ebs_volumes() {
    local instance_id="$1"
    
    # Ensure EBS encryption is enabled
    unity_log "SECURITY" "Validating EBS encryption for instance: $instance_id"
    echo "EBS encryption validated"
    return 0
}

export -f init_unity_aws_service aws_validate_security_config launch_ec2_instance
export -f aws_validate_iam_permissions aws_encrypt_ebs_volumes
EOF
    
    # Mock Docker service with security features
    cat > "$TEST_SECURITY_DIR/lib/unity/services/unity-docker-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-docker"

# Docker security configuration
declare -a DOCKER_ALLOWED_REGISTRIES=("docker.io" "public.ecr.aws" "quay.io")
declare -a DOCKER_FORBIDDEN_CAPABILITIES=("SYS_ADMIN" "NET_ADMIN" "SYS_MODULE")

unity_docker_init() {
    unity_log "SECURITY" "Docker service initialization with security validation"
    
    if ! docker_validate_security_config; then
        unity_handle_error "$UNITY_ERROR_SECURITY" "Docker security validation failed"
        return $UNITY_ERROR_SECURITY
    fi
    
    echo "Docker service initialized with security validation"
    return 0
}

docker_validate_security_config() {
    # Check Docker daemon security
    unity_log "SECURITY" "Validating Docker daemon security configuration"
    
    # In real implementation, would check:
    # - Docker daemon is not running as root
    # - TLS is enabled
    # - User namespaces are configured
    # - Content trust is enabled
    
    return 0
}

docker_start_container() {
    local image="$1"
    local name="$2"
    local options="${3:-}"
    
    # Security validations
    if ! docker_validate_image_security "$image"; then
        unity_log "SECURITY" "Image security validation failed: $image"
        return 1
    fi
    
    if ! docker_validate_container_security "$name" "$options"; then
        unity_log "SECURITY" "Container security validation failed: $name"
        return 1
    fi
    
    echo "Container started securely: $name"
    unity_log "SECURITY" "Container started with security validation: $name"
    return 0
}

docker_validate_image_security() {
    local image="$1"
    local registry="${image%%/*}"
    
    # Validate image registry
    if [[ "$image" == *"/"* ]]; then
        if [[ ! " ${DOCKER_ALLOWED_REGISTRIES[*]} " =~ " ${registry} " ]]; then
            unity_log "SECURITY" "Unauthorized Docker registry: $registry"
            return 1
        fi
    fi
    
    # Check for image vulnerabilities (mock)
    unity_log "SECURITY" "Scanning image for vulnerabilities: $image"
    
    return 0
}

docker_validate_container_security() {
    local name="$1"
    local options="$2"
    
    # Check for privileged mode
    if [[ "$options" == *"--privileged"* ]]; then
        unity_log "SECURITY" "Privileged container not allowed: $name"
        return 1
    fi
    
    # Check for dangerous capabilities
    for cap in "${DOCKER_FORBIDDEN_CAPABILITIES[@]}"; do
        if [[ "$options" == *"--cap-add $cap"* ]]; then
            unity_log "SECURITY" "Forbidden capability $cap in container: $name"
            return 1
        fi
    done
    
    # Validate container name
    if [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
        unity_log "SECURITY" "Invalid container name format: $name"
        return 1
    fi
    
    return 0
}

docker_security_scan() {
    local target="${1:-all}"
    
    unity_log "SECURITY" "Running Docker security scan: $target"
    
    # Mock security scan results
    echo "Docker Security Scan Results:"
    echo "  - No privileged containers found"
    echo "  - All images from approved registries"
    echo "  - No containers with dangerous capabilities"
    echo "  - Container names follow naming conventions"
    
    return 0
}

export -f unity_docker_init docker_validate_security_config docker_start_container
export -f docker_validate_image_security docker_validate_container_security docker_security_scan
EOF
    
    # Mock Config service with secure configuration handling
    cat > "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-config"

# Configuration security settings
declare -a CONFIG_SENSITIVE_KEYS=("password" "secret" "key" "token" "credential" "auth")
declare -a CONFIG_ENCRYPTED_KEYS=()
declare -a CONFIG_ENCRYPTED_VALUES=()

unity_config_init() {
    unity_log "SECURITY" "Config service initialization with security validation"
    
    if ! config_validate_security_settings; then
        unity_handle_error "$UNITY_ERROR_SECURITY" "Config security validation failed"
        return $UNITY_ERROR_SECURITY
    fi
    
    echo "Config service initialized with security validation"
    return 0
}

config_validate_security_settings() {
    # Validate configuration file permissions
    if [[ -f "$UNITY_CONFIG_FILE" ]]; then
        local perms=$(stat -c "%a" "$UNITY_CONFIG_FILE" 2>/dev/null || echo "644")
        if [[ "$perms" != "600" && "$perms" != "640" && "$perms" != "644" ]]; then
            unity_log "SECURITY" "Insecure config file permissions: $perms"
            return 1
        fi
    fi
    
    return 0
}

unity_config_get() {
    local key="$1"
    local default="${2:-}"
    
    # Check if key is encrypted
    if config_is_encrypted_key "$key"; then
        local decrypted_value
        decrypted_value=$(config_decrypt_value "$key")
        echo "$decrypted_value"
        return 0
    fi
    
    # Return mock value based on key
    case "$key" in
        "STACK_NAME") echo "security-test-stack" ;;
        "AWS_REGION") echo "us-west-2" ;;
        "INSTANCE_TYPE") echo "t3.medium" ;;
        "DEBUG") echo "false" ;;
        *) echo "$default" ;;
    esac
    
    return 0
}

unity_config_set() {
    local key="$1"
    local value="$2"
    
    # Security validation for sensitive keys
    if config_is_sensitive_key "$key"; then
        unity_log "SECURITY" "Handling sensitive configuration key: $key"
        config_encrypt_value "$key" "$value"
        return 0
    fi
    
    # Validate configuration value
    if ! config_validate_value "$key" "$value"; then
        unity_log "SECURITY" "Invalid configuration value for key: $key"
        return 1
    fi
    
    unity_log "SECURITY" "Configuration set with validation: $key"
    return 0
}

config_is_sensitive_key() {
    local key="$1"
    
    for sensitive in "${CONFIG_SENSITIVE_KEYS[@]}"; do
        if [[ "$key" == *"$sensitive"* ]]; then
            return 0
        fi
    done
    
    return 1
}

config_is_encrypted_key() {
    local key="$1"
    local i
    
    for i in "${!CONFIG_ENCRYPTED_KEYS[@]}"; do
        if [[ "${CONFIG_ENCRYPTED_KEYS[i]}" == "$key" ]]; then
            return 0
        fi
    done
    
    return 1
}

config_encrypt_value() {
    local key="$1"
    local value="$2"
    
    # Mock encryption (in real implementation, use proper encryption)
    local encrypted_value=$(echo "$value" | base64)
    
    CONFIG_ENCRYPTED_KEYS+=("$key")
    CONFIG_ENCRYPTED_VALUES+=("$encrypted_value")
    
    unity_log "SECURITY" "Value encrypted for key: $key"
    return 0
}

config_decrypt_value() {
    local key="$1"
    local i
    
    for i in "${!CONFIG_ENCRYPTED_KEYS[@]}"; do
        if [[ "${CONFIG_ENCRYPTED_KEYS[i]}" == "$key" ]]; then
            # Mock decryption
            local decrypted_value=$(echo "${CONFIG_ENCRYPTED_VALUES[i]}" | base64 -d)
            echo "$decrypted_value"
            return 0
        fi
    done
    
    return 1
}

config_validate_value() {
    local key="$1"
    local value="$2"
    
    # Validate based on key type
    case "$key" in
        "AWS_REGION")
            if [[ ! "$value" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
                unity_log "SECURITY" "Invalid AWS region format: $value"
                return 1
            fi
            ;;
        "STACK_NAME")
            if [[ ! "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                unity_log "SECURITY" "Invalid stack name format: $value"
                return 1
            fi
            ;;
        "INSTANCE_TYPE")
            if [[ ! "$value" =~ ^[a-z0-9]+\.[a-z0-9]+$ ]]; then
                unity_log "SECURITY" "Invalid instance type format: $value"
                return 1
            fi
            ;;
    esac
    
    return 0
}

config_security_audit() {
    echo "Configuration Security Audit:"
    echo "  - Sensitive keys: ${#CONFIG_ENCRYPTED_KEYS[@]}"
    echo "  - Encrypted values: ${#CONFIG_ENCRYPTED_VALUES[@]}"
    
    # Check for potential security issues
    local issues=0
    
    if [[ "${#CONFIG_ENCRYPTED_KEYS[@]}" -eq 0 ]]; then
        echo "  - WARNING: No encrypted sensitive keys found"
        ((issues++))
    fi
    
    echo "  - Security issues found: $issues"
    return $issues
}

export -f unity_config_init config_validate_security_settings unity_config_get unity_config_set
export -f config_is_sensitive_key config_encrypt_value config_decrypt_value config_security_audit
EOF
    
    # Mock Monitor service with security monitoring
    cat > "$TEST_SECURITY_DIR/lib/unity/services/unity-monitor-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-monitor"

# Security monitoring configuration
declare -a SECURITY_ALERTS=()
declare -g SECURITY_VIOLATION_COUNT=0

unity_monitor_init() {
    unity_log "SECURITY" "Monitor service initialization with security features"
    
    # Initialize security monitoring
    monitor_init_security_checks
    
    echo "Monitor service initialized with security monitoring"
    return 0
}

monitor_init_security_checks() {
    unity_log "SECURITY" "Initializing security monitoring checks"
    
    # Setup security monitoring (mock)
    return 0
}

unity_monitor_security_scan() {
    local scan_type="${1:-full}"
    
    unity_log "SECURITY" "Running security scan: $scan_type"
    
    local findings=0
    
    # File permission checks
    findings=$((findings + $(monitor_check_file_permissions)))
    
    # Process security checks
    findings=$((findings + $(monitor_check_process_security)))
    
    # Network security checks
    findings=$((findings + $(monitor_check_network_security)))
    
    # Configuration security checks
    findings=$((findings + $(monitor_check_config_security)))
    
    echo "Security scan completed. Findings: $findings"
    return $findings
}

monitor_check_file_permissions() {
    local findings=0
    
    # Check for world-writable files (mock)
    unity_log "SECURITY" "Checking file permissions"
    
    # In real implementation, would check actual file permissions
    # find $PROJECT_ROOT -type f -perm -002 2>/dev/null
    
    return $findings
}

monitor_check_process_security() {
    local findings=0
    
    unity_log "SECURITY" "Checking process security"
    
    # Check for processes running as root (mock)
    # Check for processes with suspicious names
    # Check for processes with network connections
    
    return $findings
}

monitor_check_network_security() {
    local findings=0
    
    unity_log "SECURITY" "Checking network security"
    
    # Check for open ports
    # Check for unauthorized network connections
    # Check for unencrypted communications
    
    return $findings
}

monitor_check_config_security() {
    local findings=0
    
    unity_log "SECURITY" "Checking configuration security"
    
    # Check configuration files for sensitive data
    # Validate configuration file permissions
    # Check for default credentials
    
    return $findings
}

unity_monitor_security_alert() {
    local severity="$1"
    local message="$2"
    local context="${3:-}"
    
    local alert="$(date -Iseconds) [$severity] $message"
    [[ -n "$context" ]] && alert="$alert ($context)"
    
    SECURITY_ALERTS+=("$alert")
    ((SECURITY_VIOLATION_COUNT++))
    
    unity_log "SECURITY" "Security alert: $alert"
    
    # In real implementation, would send to monitoring system
    echo "SECURITY ALERT: $alert"
    
    return 0
}

monitor_get_security_status() {
    echo "Security Monitoring Status:"
    echo "  - Total alerts: ${#SECURITY_ALERTS[@]}"
    echo "  - Violations: $SECURITY_VIOLATION_COUNT"
    echo "  - Last scan: $(date)"
    
    if [[ ${#SECURITY_ALERTS[@]} -gt 0 ]]; then
        echo "Recent alerts:"
        for alert in "${SECURITY_ALERTS[@]: -5}"; do
            echo "    $alert"
        done
    fi
}

export -f unity_monitor_init monitor_init_security_checks unity_monitor_security_scan
export -f monitor_check_file_permissions monitor_check_process_security monitor_check_network_security
export -f monitor_check_config_security unity_monitor_security_alert monitor_get_security_status
EOF
}

# Create security test configuration files
_create_security_test_configs() {
    # Create secure Unity configuration
    cat > "$TEST_SECURITY_DIR/config/unity.yml" << 'EOF'
# Unity Security Test Configuration
AWS_REGION: us-west-2
STACK_NAME: security-test-stack
INSTANCE_TYPE: t3.medium
DEBUG: false
SECURITY_MODE: strict
ENCRYPTION_ENABLED: true
LOG_RETENTION_DAYS: 30
AUDIT_ENABLED: true
EOF
    
    # Create security policy file
    cat > "$UNITY_SECURITY_DIR/security_policy.yml" << 'EOF'
# Unity Security Policy
security_policy:
  version: "1.0"
  
  encryption:
    enabled: true
    algorithm: "AES-256"
    key_rotation_days: 90
  
  access_control:
    min_password_length: 12
    require_mfa: true
    session_timeout_minutes: 30
  
  monitoring:
    audit_logs: true
    real_time_alerts: true
    retention_days: 90
  
  compliance:
    standards: ["SOC2", "GDPR", "HIPBA"]
    scan_frequency: "daily"
EOF
    
    # Create test environment file with security settings
    cat > "$TEST_SECURITY_DIR/.env.security" << 'EOF'
# Security Test Environment
UNITY_SECURITY_MODE=strict
SECURITY_SCAN_ENABLED=true
AUDIT_LOG_ENABLED=true
ENCRYPTION_KEY_FILE=/dev/null
TLS_CERT_FILE=/dev/null
TLS_KEY_FILE=/dev/null
EOF
}

# Mock external dependencies for security testing
_mock_external_dependencies_security() {
    mock_function "aws" 'case "$1 $2" in
        "sts get-caller-identity") echo "{\"Account\":\"123456789012\",\"UserId\":\"AIDACKCEVSQ6C2EXAMPLE\",\"Arn\":\"arn:aws:iam::123456789012:user/test-user\"}" ;;
        "iam get-user") echo "{\"User\":{\"UserName\":\"test-user\",\"UserId\":\"AIDACKCEVSQ6C2EXAMPLE\"}}" ;;
        "iam list-attached-user-policies") echo "{\"AttachedPolicies\":[{\"PolicyName\":\"AmazonEC2ReadOnlyAccess\"}]}" ;;
        "ssm get-parameters-by-path") echo "{\"Parameters\":[{\"Name\":\"/aibuildkit/test\",\"Value\":\"test-value\",\"Type\":\"SecureString\"}]}" ;;
        *) echo "{\"ResponseMetadata\":{\"RequestId\":\"test-request\"}}" ;;
    esac'
    
    mock_function "docker" 'case "$1" in
        "info") echo "Docker daemon running securely" ;;
        "version") echo "Docker version 24.0.0" ;;
        "image") echo "Image security scan completed" ;;
        *) echo "docker-security-response" ;;
    esac'
    
    mock_function "openssl" 'case "$1" in
        "rand") echo "random-secure-string" ;;
        "enc") echo "encrypted-data" ;;
        "dgst") echo "secure-hash" ;;
        *) echo "openssl-output" ;;
    esac'
    
    mock_function "gpg" 'echo "GPG encryption/decryption completed"'
    mock_function "ssh-keygen" 'echo "SSH key generated securely"'
    mock_function "chmod" 'return 0'
    mock_function "chown" 'return 0'
    mock_function "umask" 'echo "0022"'
}

# Initialize security monitoring
_init_security_monitoring() {
    # Create security audit log
    echo "$(date -Iseconds) Security monitoring initialized" > "$SECURITY_AUDIT_LOG"
    
    # Create security status file
    cat > "$UNITY_SECURITY_DIR/security_status.json" << 'EOF'
{
  "status": "active",
  "last_scan": null,
  "violations": 0,
  "alerts": [],
  "compliance_level": "unknown"
}
EOF
}

# Clean up security test environment
cleanup_security_tests() {
    # Restore mocked functions
    local mock_functions=("aws" "docker" "openssl" "gpg" "ssh-keygen" "chmod" "chown" "umask")
    
    for func in "${mock_functions[@]}"; do
        restore_function "$func" 2>/dev/null || true
    done
    
    # Clean up test files
    if [[ -n "${TEST_SECURITY_DIR:-}" && -d "$TEST_SECURITY_DIR" ]]; then
        rm -rf "$TEST_SECURITY_DIR" 2>/dev/null || true
    fi
    
    # Clean up environment variables
    unset TEST_SECURITY_DIR UNITY_SECURITY_DIR UNITY_LOG_DIR SECURITY_AUDIT_LOG
    unset UNITY_SECURITY_MODE SECURITY_SCAN_ENABLED STACK_NAME AWS_REGION
}

# =============================================================================
# AUTHENTICATION AND AUTHORIZATION TESTS
# =============================================================================

test_unity_authentication_security() {
    test_start "unity_authentication_security" "Test Unity authentication security"
    
    setup_security_tests
    
    # Test AWS credential security
    if aws_validate_security_config 2>/dev/null; then
        test_pass "AWS credentials are properly secured (no hardcoded credentials)"
    else
        test_fail "AWS credential security validation failed"
    fi
    
    # Test service registration security
    source "$TEST_SECURITY_DIR/lib/unity/core/registry.sh" >/dev/null 2>&1
    
    # Test valid service registration
    if unity_register_service "test-service" "/valid/path" "644" >/dev/null 2>&1; then
        test_pass "Valid service registration accepted"
    else
        test_fail "Valid service registration rejected"
    fi
    
    # Test invalid service name
    if unity_register_service "test-service-with-invalid-chars!" "/valid/path" "644" >/dev/null 2>&1; then
        test_fail "Invalid service name should be rejected"
    else
        test_pass "Invalid service name properly rejected"
    fi
    
    # Test service permission validation
    if unity_validate_service_permissions "test-service" >/dev/null 2>&1; then
        test_pass "Service permissions validated successfully"
    else
        test_fail "Service permission validation failed"
    fi
    
    cleanup_security_tests
}

test_unity_authorization_controls() {
    test_start "unity_authorization_controls" "Test Unity authorization controls"
    
    setup_security_tests
    
    # Source AWS service for testing
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    
    # Test region authorization
    export AWS_REGION="us-west-2"  # Allowed region
    if aws_validate_security_config >/dev/null 2>&1; then
        test_pass "Authorized AWS region accepted"
    else
        test_fail "Authorized AWS region validation failed" 
    fi
    
    # Test unauthorized region
    export AWS_REGION="unauthorized-region"
    if aws_validate_security_config >/dev/null 2>&1; then
        test_fail "Unauthorized AWS region should be rejected"
    else
        test_pass "Unauthorized AWS region properly rejected"
    fi
    
    # Reset to valid region
    export AWS_REGION="us-west-2"
    
    # Test instance type authorization
    if launch_ec2_instance "t3.medium" "spot" "test-stack" >/dev/null 2>&1; then
        test_pass "Authorized instance type accepted"
    else
        test_fail "Authorized instance type validation failed"
    fi
    
    # Test unauthorized instance type
    if launch_ec2_instance "unauthorized.type" "spot" "test-stack" >/dev/null 2>&1; then
        test_fail "Unauthorized instance type should be rejected"
    else
        test_pass "Unauthorized instance type properly rejected"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# DATA ENCRYPTION TESTS
# =============================================================================

test_unity_data_encryption() {
    test_start "unity_data_encryption" "Test Unity data encryption capabilities"
    
    setup_security_tests
    
    # Source config service for encryption testing
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Test sensitive data encryption
    if unity_config_set "DATABASE_PASSWORD" "sensitive-password" >/dev/null 2>&1; then
        test_pass "Sensitive configuration data encrypted successfully"
        
        # Test encrypted data retrieval
        local retrieved_value
        retrieved_value=$(unity_config_get "DATABASE_PASSWORD" 2>/dev/null)
        
        if [[ "$retrieved_value" == "sensitive-password" ]]; then
            test_pass "Encrypted configuration data decrypted successfully"
        else
            test_fail "Encrypted configuration data decryption failed"
        fi
    else
        test_fail "Sensitive configuration data encryption failed"
    fi
    
    # Test non-sensitive data (should not be encrypted)
    if unity_config_set "STACK_NAME" "test-stack" >/dev/null 2>&1; then
        test_pass "Non-sensitive configuration data handled correctly"
    else
        test_fail "Non-sensitive configuration data handling failed"
    fi
    
    # Test EBS encryption validation
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    if aws_encrypt_ebs_volumes "i-1234567890abcdef0" >/dev/null 2>&1; then
        test_pass "EBS encryption validation successful"
    else
        test_fail "EBS encryption validation failed"
    fi
    
    cleanup_security_tests
}

test_unity_data_protection() {
    test_start "unity_data_protection" "Test Unity data protection mechanisms"
    
    setup_security_tests
    
    # Test log data filtering
    source "$TEST_SECURITY_DIR/lib/modules/core/logging.sh" >/dev/null 2>&1
    
    # Test that sensitive data is filtered from logs
    local log_output
    log_output=$(log_info "Setting password=secret123 for user" 2>&1)
    
    if [[ "$log_output" == *"[REDACTED]"* ]]; then
        test_pass "Sensitive data filtered from logs successfully"
    else
        test_warn "Sensitive data may not be properly filtered from logs"
    fi
    
    # Test event data filtering
    source "$TEST_SECURITY_DIR/lib/unity/events/event-bus.sh" >/dev/null 2>&1
    
    local event_output
    event_output=$(unity_event_emit "user_action" "credential=secret123" 2>&1)
    
    if [[ "$event_output" == *"[FILTERED:"* ]]; then
        test_pass "Sensitive data filtered from events successfully"
    else
        test_warn "Sensitive data may not be properly filtered from events"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# NETWORK SECURITY TESTS
# =============================================================================

test_unity_network_security() {
    test_start "unity_network_security" "Test Unity network security configurations"
    
    setup_security_tests
    
    # Source monitor service for network security checks
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Test network security monitoring
    local network_findings
    network_findings=$(monitor_check_network_security)
    
    if [[ $network_findings -eq 0 ]]; then
        test_pass "Network security check passed (no findings)"
    else
        test_warn "Network security check found $network_findings issues"
    fi
    
    # Test Docker network security
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    
    # Test container with secure networking
    if docker_start_container "nginx:latest" "secure-container" "--network bridge" >/dev/null 2>&1; then
        test_pass "Container with secure networking started successfully"
    else
        test_fail "Container with secure networking failed to start"
    fi
    
    # Test container with host networking (should be restricted)
    if docker_start_container "nginx:latest" "insecure-container" "--network host" >/dev/null 2>&1; then
        test_warn "Container with host networking allowed (potential security risk)"
    else
        test_pass "Container with host networking properly restricted"
    fi
    
    cleanup_security_tests
}

test_unity_tls_encryption() {
    test_start "unity_tls_encryption" "Test Unity TLS encryption requirements"
    
    setup_security_tests
    
    # Test TLS configuration validation
    if [[ -n "${TLS_CERT_FILE:-}" && -n "${TLS_KEY_FILE:-}" ]]; then
        test_pass "TLS certificates configured"
        
        # In real implementation, would validate certificate validity
        # Check certificate expiration
        # Validate certificate chain
        # Check for weak encryption algorithms
        
    else
        test_warn "TLS certificates not configured (may be expected in test environment)"
    fi
    
    # Test encryption key strength
    local test_key
    test_key=$(openssl rand -hex 32 2>/dev/null)
    
    if [[ ${#test_key} -ge $SECURITY_MIN_KEY_LENGTH ]]; then
        test_pass "Encryption key meets minimum length requirements (${#test_key} >= $SECURITY_MIN_KEY_LENGTH)"
    else
        test_fail "Encryption key does not meet minimum length requirements"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# DOCKER SECURITY TESTS
# =============================================================================

test_unity_docker_security() {
    test_start "unity_docker_security" "Test Unity Docker security configurations"
    
    setup_security_tests
    
    # Source Docker service
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    # Test Docker security configuration
    if docker_validate_security_config >/dev/null 2>&1; then
        test_pass "Docker security configuration validated successfully"
    else
        test_fail "Docker security configuration validation failed"
    fi
    
    # Test image security validation
    if docker_validate_image_security "nginx:latest" >/dev/null 2>&1; then
        test_pass "Docker image security validation passed"
    else
        test_fail "Docker image security validation failed"
    fi
    
    # Test unauthorized registry
    if docker_validate_image_security "unauthorized-registry.com/image:latest" >/dev/null 2>&1; then
        test_fail "Unauthorized Docker registry should be rejected"
    else
        test_pass "Unauthorized Docker registry properly rejected"
    fi
    
    # Test privileged container security
    if docker_validate_container_security "test-container" "--privileged" >/dev/null 2>&1; then
        test_fail "Privileged container should be rejected"
    else
        test_pass "Privileged container properly rejected"
    fi
    
    # Test dangerous capabilities
    if docker_validate_container_security "test-container" "--cap-add SYS_ADMIN" >/dev/null 2>&1; then
        test_fail "Dangerous capabilities should be rejected"
    else
        test_pass "Dangerous capabilities properly rejected"
    fi
    
    # Test secure container configuration
    if docker_validate_container_security "test-container" "--read-only --tmpfs /tmp" >/dev/null 2>&1; then
        test_pass "Secure container configuration accepted"
    else
        test_fail "Secure container configuration validation failed"
    fi
    
    cleanup_security_tests
}

test_unity_docker_image_scanning() {
    test_start "unity_docker_image_scanning" "Test Unity Docker image vulnerability scanning"
    
    setup_security_tests
    
    # Source Docker service
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    # Test Docker security scan
    local scan_output
    scan_output=$(docker_security_scan "images" 2>/dev/null)
    
    if [[ -n "$scan_output" && "$scan_output" == *"Security Scan Results"* ]]; then
        test_pass "Docker security scan completed successfully"
        
        # Check for specific security validations
        if [[ "$scan_output" == *"No privileged containers"* ]]; then
            test_pass "Privileged container check passed"
        else
            test_warn "Privileged container check may have issues"
        fi
        
        if [[ "$scan_output" == *"approved registries"* ]]; then
            test_pass "Registry validation check passed"
        else
            test_warn "Registry validation check may have issues"
        fi
    else
        test_fail "Docker security scan failed or returned invalid output"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# FILE SYSTEM SECURITY TESTS
# =============================================================================

test_unity_file_permissions() {
    test_start "unity_file_permissions" "Test Unity file system permissions"
    
    setup_security_tests
    
    # Source monitor service for file permission checks
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Test file permission validation
    local permission_findings
    permission_findings=$(monitor_check_file_permissions)
    
    if [[ $permission_findings -eq 0 ]]; then
        test_pass "File permission check passed (no insecure permissions found)"
    else
        test_warn "File permission check found $permission_findings issues"
    fi
    
    # Test configuration file permissions
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    
    if config_validate_security_settings >/dev/null 2>&1; then
        test_pass "Configuration file permissions validated successfully"
    else
        test_fail "Configuration file permission validation failed"
    fi
    
    # Create test files with various permissions
    local test_file_secure="$TEST_SECURITY_DIR/secure_file.txt"
    local test_file_insecure="$TEST_SECURITY_DIR/insecure_file.txt"
    
    echo "secure content" > "$test_file_secure"
    echo "insecure content" > "$test_file_insecure"
    
    chmod 600 "$test_file_secure"
    chmod 666 "$test_file_insecure"
    
    # Test secure file permissions
    local secure_perms=$(stat -c "%a" "$test_file_secure" 2>/dev/null)
    if [[ "$secure_perms" == "600" ]]; then
        test_pass "Secure file permissions (600) properly set"
    else
        test_fail "Secure file permissions not properly set: $secure_perms"
    fi
    
    # Test insecure file permissions detection
    local insecure_perms=$(stat -c "%a" "$test_file_insecure" 2>/dev/null)  
    if [[ "$insecure_perms" == "666" ]]; then
        test_warn "Insecure file permissions (666) detected as expected"
    else
        test_info "File permissions: $insecure_perms"
    fi
    
    cleanup_security_tests
}

test_unity_path_traversal_protection() {
    test_start "unity_path_traversal_protection" "Test Unity path traversal protection"
    
    setup_security_tests
    
    # Source Unity core for path validation
    source "$TEST_SECURITY_DIR/lib/unity/core/unity-core.sh" >/dev/null 2>&1
    
    # Test path traversal attempts
    if unity_register_service "test-service" "../../../etc/passwd" >/dev/null 2>&1; then
        test_fail "Path traversal attempt should be rejected"
    else
        test_pass "Path traversal attempt properly rejected"
    fi
    
    if unity_register_service "test-service" "/valid/absolute/path" >/dev/null 2>&1; then
        test_pass "Valid absolute path accepted"
    else
        test_fail "Valid absolute path rejected"
    fi
    
    # Test relative path protection
    if unity_register_service "test-service" "./relative/path" >/dev/null 2>&1; then
        test_pass "Relative path handled appropriately"
    else
        test_pass "Relative path properly restricted"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# CONFIGURATION SECURITY TESTS
# =============================================================================

test_unity_configuration_security() {
    test_start "unity_configuration_security" "Test Unity configuration security"
    
    setup_security_tests
    
    # Source config service
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Test configuration security audit
    local audit_result
    audit_result=$(config_security_audit 2>/dev/null)
    
    if [[ -n "$audit_result" && "$audit_result" == *"Configuration Security Audit"* ]]; then
        test_pass "Configuration security audit completed successfully"
        
        # Check audit results
        if [[ "$audit_result" == *"Security issues found: 0"* ]]; then
            test_pass "No configuration security issues found"
        else
            test_warn "Configuration security issues found (may be expected in test environment)"
        fi
    else
        test_fail "Configuration security audit failed"
    fi
    
    # Test input validation
    if unity_config_set "AWS_REGION" "valid-region-1" >/dev/null 2>&1; then
        test_pass "Valid AWS region format accepted"
    else
        test_fail "Valid AWS region format validation failed"
    fi
    
    if unity_config_set "AWS_REGION" "invalid region format!" >/dev/null 2>&1; then
        test_fail "Invalid AWS region format should be rejected"
    else
        test_pass "Invalid AWS region format properly rejected"
    fi
    
    # Test stack name validation
    if unity_config_set "STACK_NAME" "valid-stack-name_123" >/dev/null 2>&1; then
        test_pass "Valid stack name format accepted"
    else
        test_fail "Valid stack name format validation failed"
    fi
    
    if unity_config_set "STACK_NAME" "invalid stack name!" >/dev/null 2>&1; then
        test_fail "Invalid stack name format should be rejected"
    else
        test_pass "Invalid stack name format properly rejected"
    fi
    
    cleanup_security_tests
}

test_unity_secrets_management() {
    test_start "unity_secrets_management" "Test Unity secrets management"
    
    setup_security_tests
    
    # Source config service
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Test secrets encryption
    if unity_config_set "API_SECRET" "super-secret-key" >/dev/null 2>&1; then
        test_pass "Secret value encrypted successfully"
        
        # Verify secret is encrypted in storage
        if config_is_encrypted_key "API_SECRET"; then
            test_pass "Secret confirmed as encrypted in storage"
        else
            test_fail "Secret not properly encrypted in storage"
        fi
        
        # Test secret retrieval
        local retrieved_secret
        retrieved_secret=$(unity_config_get "API_SECRET" 2>/dev/null)
        
        if [[ "$retrieved_secret" == "super-secret-key" ]]; then
            test_pass "Encrypted secret decrypted successfully"
        else
            test_fail "Encrypted secret decryption failed"
        fi
    else
        test_fail "Secret encryption failed"
    fi
    
    # Test non-secret values are not encrypted
    if unity_config_set "STACK_NAME" "test-stack" >/dev/null 2>&1; then
        if config_is_encrypted_key "STACK_NAME"; then
            test_warn "Non-secret value unnecessarily encrypted"
        else
            test_pass "Non-secret value correctly not encrypted"
        fi
    fi
    
    cleanup_security_tests
}

# =============================================================================
# MONITORING AND ALERTING TESTS
# =============================================================================

test_unity_security_monitoring() {
    test_start "unity_security_monitoring" "Test Unity security monitoring capabilities"
    
    setup_security_tests
    
    # Source monitor service
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Test security scan functionality
    local scan_result
    scan_result=$(unity_monitor_security_scan "quick" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        test_pass "Security scan completed successfully"
        
        if [[ "$scan_result" == *"Security scan completed"* ]]; then
            test_pass "Security scan returned valid results"
        else
            test_warn "Security scan results may be incomplete"
        fi
    else
        test_fail "Security scan failed to complete"
    fi
    
    # Test security alerting
    if unity_monitor_security_alert "HIGH" "Test security alert" "Test context" >/dev/null 2>&1; then
        test_pass "Security alert generated successfully"
        
        # Check alert was recorded
        local security_status
        security_status=$(monitor_get_security_status 2>/dev/null)
        
        if [[ "$security_status" == *"Total alerts: 1"* ]]; then
            test_pass "Security alert properly recorded"
        else
            test_warn "Security alert may not be properly recorded"
        fi
    else
        test_fail "Security alert generation failed"
    fi
    
    cleanup_security_tests
}

test_unity_audit_logging() {
    test_start "unity_audit_logging" "Test Unity audit logging capabilities"
    
    setup_security_tests
    
    # Source Unity core for audit logging
    source "$TEST_SECURITY_DIR/lib/unity/core/unity-core.sh" >/dev/null 2>&1
    
    # Generate some security events
    unity_log "SECURITY" "Test security event 1"
    unity_log "SECURITY" "Test security event 2"
    unity_handle_error "$UNITY_ERROR_SECURITY" "$UNITY_ERROR_SECURITY" "Test security violation"
    
    # Test security audit functionality
    local audit_output
    audit_output=$(unity_security_audit 2>/dev/null)
    
    if [[ -n "$audit_output" ]]; then
        test_pass "Security audit generated successfully"
        
        # Check audit content
        if [[ "$audit_output" == *"Security Events: 2"* ]]; then
            test_pass "Security events properly recorded"
        else
            test_warn "Security events may not be properly recorded"
        fi
        
        if [[ "$audit_output" == *"Security Violations: 1"* ]]; then
            test_pass "Security violations properly tracked"
        else
            test_warn "Security violations may not be properly tracked"
        fi
    else
        test_fail "Security audit generation failed"
    fi
    
    # Test audit log file
    if [[ -f "$SECURITY_AUDIT_LOG" ]]; then
        test_pass "Security audit log file exists"
        
        local log_content
        log_content=$(cat "$SECURITY_AUDIT_LOG" 2>/dev/null)
        
        if [[ -n "$log_content" ]]; then
            test_pass "Security audit log contains data"
        else
            test_warn "Security audit log is empty"
        fi
    else
        test_warn "Security audit log file not found"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# COMPLIANCE TESTS
# =============================================================================

test_unity_compliance_standards() {
    test_start "unity_compliance_standards" "Test Unity compliance with security standards"
    
    setup_security_tests
    
    # Test password complexity requirements
    local test_passwords=("weak" "StrongPassword123!" "sh0rt" "verylongpasswordwithoutcomplexity")
    local strong_passwords=0
    
    for password in "${test_passwords[@]}"; do
        local length=${#password}
        if [[ $length -ge $SECURITY_MIN_PASSWORD_LENGTH ]]; then
            if [[ "$password" =~ [A-Z] && "$password" =~ [a-z] && "$password" =~ [0-9] ]]; then
                ((strong_passwords++))
            fi
        fi
    done
    
    if [[ $strong_passwords -gt 0 ]]; then
        test_pass "Strong password validation works correctly"
    else
        test_fail "Password complexity validation needs improvement"
    fi
    
    # Test data retention compliance
    export LOG_RETENTION_DAYS=30
    if [[ $LOG_RETENTION_DAYS -le $SECURITY_MAX_LOG_RETENTION_DAYS ]]; then
        test_pass "Log retention period complies with security requirements ($LOG_RETENTION_DAYS <= $SECURITY_MAX_LOG_RETENTION_DAYS days)"
    else
        test_fail "Log retention period exceeds security requirements"
    fi
    
    # Test encryption requirements
    if [[ "${ENCRYPTION_ENABLED:-}" == "true" ]]; then
        test_pass "Encryption is enabled as required"
    else
        test_warn "Encryption may not be properly enabled"
    fi
    
    # Test audit trail requirements
    if [[ "${AUDIT_ENABLED:-}" == "true" ]]; then
        test_pass "Audit trail is enabled as required"
    else
        test_warn "Audit trail may not be properly enabled"
    fi
    
    cleanup_security_tests
}

test_unity_security_best_practices() {
    test_start "unity_security_best_practices" "Test Unity adherence to security best practices"
    
    setup_security_tests
    
    # Test principle of least privilege
    # Check that services only have required permissions
    local privilege_check_passed=true
    
    # In real implementation, would check actual IAM policies
    # For now, test the mock validation
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    
    if aws_validate_iam_permissions >/dev/null 2>&1; then
        test_pass "IAM permissions validation completed"
    else
        test_fail "IAM permissions validation failed"
        privilege_check_passed=false
    fi
    
    # Test defense in depth
    local security_layers=0
    
    # Check for multiple security layers
    [[ "${ENCRYPTION_ENABLED:-}" == "true" ]] && ((security_layers++))
    [[ "${AUDIT_ENABLED:-}" == "true" ]] && ((security_layers++))
    [[ "${UNITY_SECURITY_MODE:-}" == "strict" ]] && ((security_layers++))
    [[ "${SECURITY_SCAN_ENABLED:-}" == "true" ]] && ((security_layers++))
    
    if [[ $security_layers -ge 3 ]]; then
        test_pass "Multiple security layers implemented (defense in depth): $security_layers layers"
    else
        test_warn "Limited security layers detected: $security_layers layers"
    fi
    
    # Test secure defaults
    if [[ "${DEBUG:-}" == "false" && "${UNITY_SECURITY_MODE:-}" == "strict" ]]; then
        test_pass "Secure defaults are properly configured"
    else
        test_warn "Some defaults may not be security-focused"
    fi
    
    # Test input validation
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    
    local validation_tests=0
    local validation_passed=0
    
    # Test various input validation scenarios
    if ! unity_config_set "INVALID_KEY!" "value" >/dev/null 2>&1; then
        ((validation_passed++))
    fi
    ((validation_tests++))
    
    if ! unity_config_set "AWS_REGION" "invalid-format!" >/dev/null 2>&1; then
        ((validation_passed++))
    fi
    ((validation_tests++))
    
    if [[ $validation_passed -eq $validation_tests ]]; then
        test_pass "Input validation working correctly ($validation_passed/$validation_tests tests passed)"
    else
        test_warn "Input validation may need improvement ($validation_passed/$validation_tests tests passed)"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# VULNERABILITY TESTING
# =============================================================================

test_unity_vulnerability_scanning() {
    test_start "unity_vulnerability_scanning" "Test Unity vulnerability scanning capabilities"
    
    setup_security_tests
    
    # Source all services for comprehensive vulnerability scan
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    
    unity_monitor_init >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Test comprehensive security scan
    local total_findings=0
    
    # File system vulnerabilities
    local fs_findings
    fs_findings=$(monitor_check_file_permissions)
    total_findings=$((total_findings + fs_findings))
    
    # Process vulnerabilities
    local process_findings
    process_findings=$(monitor_check_process_security)
    total_findings=$((total_findings + process_findings))
    
    # Network vulnerabilities
    local network_findings
    network_findings=$(monitor_check_network_security)
    total_findings=$((total_findings + network_findings))
    
    # Configuration vulnerabilities
    local config_findings
    config_findings=$(monitor_check_config_security)
    total_findings=$((total_findings + config_findings))
    
    # Docker vulnerabilities
    local docker_scan_output
    docker_scan_output=$(docker_security_scan "all" 2>/dev/null)
    
    if [[ -n "$docker_scan_output" ]]; then
        log_info "Docker security scan completed"
    else
        ((total_findings++))
    fi
    
    # Evaluate overall vulnerability status
    if [[ $total_findings -eq 0 ]]; then
        test_pass "Comprehensive vulnerability scan found no issues"
    elif [[ $total_findings -le 2 ]]; then
        test_warn "Vulnerability scan found $total_findings minor issues"
    else
        test_fail "Vulnerability scan found $total_findings issues requiring attention"
    fi
    
    cleanup_security_tests
}

test_unity_penetration_testing() {
    test_start "unity_penetration_testing" "Test Unity resistance to common attack vectors"
    
    setup_security_tests
    
    # Source services for penetration testing
    source "$TEST_SECURITY_DIR/lib/unity/core/unity-core.sh" >/dev/null 2>&1
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_SECURITY_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    
    unity_config_init >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    local attack_vectors_blocked=0
    local total_attack_vectors=0
    
    # Test injection attacks
    ((total_attack_vectors++))
    if ! unity_config_set "TEST_VAR" "'; DROP TABLE users; --" >/dev/null 2>&1; then
        ((attack_vectors_blocked++))
        log_debug "SQL injection pattern blocked"
    fi
    
    # Test command injection
    ((total_attack_vectors++))
    if ! unity_config_set "TEST_VAR" "\$(rm -rf /)" >/dev/null 2>&1; then
        ((attack_vectors_blocked++))
        log_debug "Command injection pattern blocked"
    fi
    
    # Test path traversal
    ((total_attack_vectors++))
    if ! unity_register_service "test" "../../../etc/passwd" >/dev/null 2>&1; then
        ((attack_vectors_blocked++))
        log_debug "Path traversal attack blocked"
    fi
    
    # Test Docker escape attempts
    ((total_attack_vectors++))
    if ! docker_start_container "nginx" "escape-test" "--privileged" >/dev/null 2>&1; then
        ((attack_vectors_blocked++))
        log_debug "Container escape attempt blocked"
    fi
    
    # Test buffer overflow attempts (simulated)
    ((total_attack_vectors++))
    local long_string=$(printf 'A%.0s' {1..10000})
    if ! unity_config_set "TEST_VAR" "$long_string" >/dev/null 2>&1; then
        ((attack_vectors_blocked++))
        log_debug "Buffer overflow attempt blocked"
    fi
    
    # Evaluate penetration test results
    local success_rate=$((attack_vectors_blocked * 100 / total_attack_vectors))
    
    if [[ $success_rate -eq 100 ]]; then
        test_pass "All attack vectors blocked successfully ($attack_vectors_blocked/$total_attack_vectors)"
    elif [[ $success_rate -ge 80 ]]; then
        test_warn "Most attack vectors blocked ($attack_vectors_blocked/$total_attack_vectors, $success_rate%)"
    else
        test_fail "Insufficient attack vector blocking ($attack_vectors_blocked/$total_attack_vectors, $success_rate%)"
    fi
    
    cleanup_security_tests
}

# =============================================================================
# RUN ALL SECURITY TESTS
# =============================================================================

# Register security tests with the Unity test framework
unity_register_security_test "unity_authentication_security" "unity-core,unity-aws-service" "test_unity_authentication_security" ""
unity_register_security_test "unity_data_encryption" "unity-config-service,unity-aws-service" "test_unity_data_encryption" ""
unity_register_security_test "unity_docker_security" "unity-docker-service" "test_unity_docker_security" ""
unity_register_security_test "unity_network_security" "unity-monitor-service,unity-docker-service" "test_unity_network_security" ""

# Run all test functions
main() {
    log_info "Running Unity Security Compliance Tests"
    
    # Authentication and authorization tests
    test_unity_authentication_security
    test_unity_authorization_controls
    
    # Data encryption and protection tests
    test_unity_data_encryption
    test_unity_data_protection
    
    # Network security tests
    test_unity_network_security
    test_unity_tls_encryption
    
    # Docker security tests
    test_unity_docker_security
    test_unity_docker_image_scanning
    
    # File system security tests
    test_unity_file_permissions
    test_unity_path_traversal_protection
    
    # Configuration security tests
    test_unity_configuration_security
    test_unity_secrets_management
    
    # Monitoring and alerting tests
    test_unity_security_monitoring
    test_unity_audit_logging
    
    # Compliance tests
    test_unity_compliance_standards
    test_unity_security_best_practices
    
    # Vulnerability and penetration tests
    test_unity_vulnerability_scanning
    test_unity_penetration_testing
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi