# GeuseMaker Coding Standards

This document defines the comprehensive coding standards for the GeuseMaker project, serving as the single source of truth for all development practices, conventions, and requirements.

## Table of Contents

1. [Naming Conventions](#naming-conventions)
   - [Function Naming](#function-naming)
   - [Variable Naming](#variable-naming)
   - [File Naming](#file-naming)
2. [Error Handling](#error-handling)
   - [Error Code Hierarchy](#error-code-hierarchy)
   - [Error Patterns](#error-patterns)
3. [Logging Standards](#logging-standards)
4. [Documentation Requirements](#documentation-requirements)
5. [Language-Specific Guidelines](#language-specific-guidelines)
   - [Bash Standards](#bash-standards)
6. [Critical Implementation Rules](#critical-implementation-rules)
7. [Testing Standards](#testing-standards)
8. [Technology Stack](#technology-stack)
9. [Code Organization](#code-organization)

## Naming Conventions

### Function Naming

Functions follow the pattern: `[action]_[resource]_[specific_action]`

**Pattern**: `verb_noun_details`

**Common Verbs**:
- `create_` - Create new resources
- `validate_` - Validate configurations or states
- `get_` - Retrieve information
- `set_` - Set or update values
- `check_` - Check conditions
- `deploy_` - Deploy resources
- `configure_` - Configure settings
- `cleanup_` - Remove resources
- `handle_` - Handle events or errors
- `process_` - Process data or workflows

**Examples**:
```bash
# Infrastructure functions
create_vpc_with_subnets()
validate_vpc_configuration()
get_subnet_availability_zones()
cleanup_vpc_resources()

# EC2 functions
launch_ec2_instance()
check_ec2_instance_status()
terminate_ec2_instances()
get_ec2_spot_price()

# Application functions
deploy_docker_stack()
configure_n8n_workflow()
validate_service_health()
handle_deployment_failure()

# Configuration functions
load_config_from_file()
validate_config_parameters()
merge_config_overrides()
export_config_to_json()
```

### Variable Naming

Variables follow the pattern: `[MODULE]_[RESOURCE]_[PROPERTY]`

**Global Variables**: UPPERCASE with underscores
```bash
# Module-specific globals
VPC_SUBNET_COUNT=4
EC2_INSTANCE_TYPE="g4dn.xlarge"
DEPLOYMENT_REGION="us-east-1"
SPOT_PRICE_CACHE_TTL=3600

# Configuration globals
CONFIG_FILE_PATH="/etc/geuse/config.yaml"
LOG_LEVEL="INFO"
DEBUG_MODE=false
```

**Local Variables**: lowercase with underscores
```bash
# Function-local variables
local instance_id="i-1234567890abcdef0"
local subnet_cidr="10.0.1.0/24"
local deployment_status="in_progress"
local error_count=0
```

**Associative Arrays**: Descriptive names with `_map` or `_cache` suffix
```bash
# Associative arrays
declare -A spot_price_cache
declare -A instance_capability_map
declare -A deployment_state_map
declare -A config_override_map
```

**Loop Variables**: Descriptive names
```bash
# Good
for region in "${regions[@]}"; do
for instance_type in "${gpu_instance_types[@]}"; do
for config_key in "${!config_map[@]}"; do

# Avoid
for i in "${arr[@]}"; do  # Too generic
```

### File Naming

**Shell Scripts**: lowercase with hyphens
```bash
aws-deployment-modular.sh
spot-instance-optimizer.sh
test-runner.sh
cleanup-resources.sh
```

**Library Files**: lowercase with hyphens, descriptive names
```bash
lib/error-handling.sh
lib/spot-instance.sh
lib/modules/core/variables.sh
lib/modules/infrastructure/vpc.sh
```

**Configuration Files**: lowercase with appropriate extension
```bash
config/development.yaml
config/production.yaml
config/spot-instances.json
```

## Error Handling

### Error Code Hierarchy

Error codes follow a hierarchical numbering system:

```bash
# Error code ranges
1-99:     General errors
100-199:  Configuration errors
200-299:  Infrastructure errors
300-399:  Deployment errors
400-499:  Service errors
500-599:  Validation errors
600-699:  Resource errors
700-799:  Network errors
800-899:  Security errors
900-999:  Critical system errors
```

**Detailed Error Codes**:
```bash
# General (1-99)
1:   Unknown error
2:   Invalid argument
3:   Missing required parameter
10:  Command not found
11:  Permission denied
20:  Timeout exceeded
21:  Operation cancelled

# Configuration (100-199)
100: Configuration file not found
101: Invalid configuration format
102: Missing required configuration
103: Configuration validation failed
110: Environment variable not set
111: Invalid environment specified

# Infrastructure (200-299)
200: VPC creation failed
201: Subnet allocation failed
202: Security group error
210: EC2 launch failed
211: Insufficient capacity
212: Spot request failed
220: EFS mount failed
221: Volume attachment error

# Deployment (300-399)
300: Stack creation failed
301: Service startup failed
302: Health check failed
310: Rollback failed
311: Cleanup failed
320: Docker error
321: Container startup failed

# Service (400-499)
400: n8n service error
401: Ollama service error
402: Qdrant service error
403: PostgreSQL error
410: Service unavailable
411: Service timeout

# Validation (500-599)
500: Validation failed
501: Schema validation error
502: Type mismatch
510: Constraint violation
511: Required field missing

# Resource (600-699)
600: Resource not found
601: Resource already exists
602: Resource limit exceeded
610: Quota exceeded
611: Insufficient permissions

# Network (700-799)
700: Network unreachable
701: Connection refused
702: DNS resolution failed
710: Load balancer error
711: CDN configuration error

# Security (800-899)
800: Authentication failed
801: Authorization denied
802: Certificate error
810: IAM policy error
811: Security group violation

# Critical (900-999)
900: System failure
901: Unrecoverable error
999: Emergency shutdown
```

### Error Patterns

**Standard Error Handling**:
```bash
# Function with comprehensive error handling
function deploy_service() {
    local service_name="$1"
    local -i error_code=0
    
    # Input validation
    if [[ -z "$service_name" ]]; then
        log_error "Service name required" "DEPLOY" 3
        return 3
    fi
    
    # Try operation with error capture
    if ! docker-compose up -d "$service_name" 2>&1 | tee -a "$LOG_FILE"; then
        error_code=320
        log_error "Docker deployment failed for $service_name" "DEPLOY" $error_code
        
        # Attempt recovery
        if ! handle_deployment_recovery "$service_name"; then
            error_code=310
            log_critical "Recovery failed for $service_name" "DEPLOY" $error_code
        fi
        
        return $error_code
    fi
    
    log_info "Service $service_name deployed successfully" "DEPLOY"
    return 0
}
```

**Error Recovery Pattern**:
```bash
# Implement retry with exponential backoff
function retry_with_backoff() {
    local -r command="$1"
    local -r max_attempts="${2:-3}"
    local -r initial_delay="${3:-2}"
    
    local attempt=1
    local delay=$initial_delay
    
    while (( attempt <= max_attempts )); do
        log_debug "Attempt $attempt of $max_attempts: $command" "RETRY"
        
        if eval "$command"; then
            return 0
        fi
        
        if (( attempt < max_attempts )); then
            log_warn "Command failed, retrying in ${delay}s..." "RETRY"
            sleep "$delay"
            delay=$((delay * 2))
        fi
        
        ((attempt++))
    done
    
    log_error "All retry attempts exhausted" "RETRY" 20
    return 20
}
```

## Logging Standards

### Log Format

All logs must use JSON format with the following structure:

```json
{
    "timestamp": "2024-01-20T10:30:45.123Z",
    "level": "INFO",
    "module": "EC2",
    "service": "geuse-maker",
    "correlation_id": "abc123-def456",
    "message": "Instance launched successfully",
    "context": {
        "instance_id": "i-1234567890",
        "instance_type": "g4dn.xlarge",
        "region": "us-east-1"
    }
}
```

### Log Levels

```bash
# Log level hierarchy
TRACE=0   # Detailed debugging information
DEBUG=1   # Debugging information
INFO=2    # Informational messages
WARN=3    # Warning messages
ERROR=4   # Error messages
CRITICAL=5 # Critical failures
```

### Logging Implementation

```bash
# Core logging function
function log_message() {
    local level="$1"
    local message="$2"
    local module="${3:-GENERAL}"
    local error_code="${4:-0}"
    local -A context="$5"
    
    # Generate correlation ID if not set
    local correlation_id="${CORRELATION_ID:-$(uuidgen)}"
    
    # Build JSON log entry
    local log_json=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        --arg level "$level" \
        --arg module "$module" \
        --arg service "geuse-maker" \
        --arg correlation_id "$correlation_id" \
        --arg message "$message" \
        --arg error_code "$error_code" \
        --argjson context "$(declare -p context | sed 's/^declare -A context=//' | jq -R 'fromjson? // {}')" \
        '{
            timestamp: $timestamp,
            level: $level,
            module: $module,
            service: $service,
            correlation_id: $correlation_id,
            message: $message,
            error_code: $error_code | tonumber,
            context: $context
        }')
    
    echo "$log_json" >> "$LOG_FILE"
    
    # Also output to console in development
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$log_json" | jq -r '"[\(.timestamp)] [\(.level)] [\(.module)] \(.message)"' >&2
    fi
}

# Convenience functions
function log_debug() { log_message "DEBUG" "$@"; }
function log_info() { log_message "INFO" "$@"; }
function log_warn() { log_message "WARN" "$@"; }
function log_error() { log_message "ERROR" "$@"; }
function log_critical() { log_message "CRITICAL" "$@"; }
```

## Documentation Requirements

### Function Documentation

Every function must include:

```bash
# Function: deploy_spot_instance
# Description: Deploys an EC2 spot instance with intelligent fallback
# Arguments:
#   $1 - instance_type: EC2 instance type (required)
#   $2 - region: AWS region (optional, defaults to us-east-1)
#   $3 - max_price: Maximum spot price (optional)
# Returns:
#   0 - Success
#   211 - Insufficient capacity
#   212 - Spot request failed
# Example:
#   deploy_spot_instance "g4dn.xlarge" "us-west-2" "0.30"
function deploy_spot_instance() {
    local instance_type="$1"
    local region="${2:-us-east-1}"
    local max_price="$3"
    
    # Function implementation...
}
```

### Inline Comments

```bash
# Use inline comments for complex logic
if [[ -z "${spot_price_cache[$cache_key]}" ]] || \
   (( $(date +%s) - cache_timestamp > SPOT_PRICE_CACHE_TTL )); then
    # Cache miss or expired - fetch fresh data
    fetch_spot_prices "$region"
fi

# Document non-obvious decisions
# Using g5.xlarge as fallback due to better availability
local fallback_instance="g5.xlarge"

# Explain regex patterns
# Match semantic version: X.Y.Z or X.Y.Z-suffix
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
```

### Module Headers

```bash
#!/usr/bin/env bash
# Module: infrastructure/vpc.sh
# Description: VPC and network infrastructure management
# Dependencies:
#   - aws-cli v2.x
#   - jq 1.6+
#   - lib/modules/core/variables.sh
# Required Environment:
#   - AWS_REGION
#   - DEPLOYMENT_ENV
# Author: GeuseMaker Team
# Version: 2.0.0
```

## Language-Specific Guidelines

### Bash Standards

**Required Features**:
```bash
#!/usr/bin/env bash
# Works with any bash version
```

**Shell Options**:
```bash
# Standard shell options for all scripts
set -euo pipefail  # Exit on error, undefined vars, pipe failures
set -E             # Inherit ERR trap
shopt -s nullglob  # Empty globs return empty
shopt -s globstar  # Enable ** recursive glob
```

**Associative Arrays**:
```bash
# Always declare type explicitly
declare -A config_map
declare -a instance_list
declare -i retry_count=0
declare -r CONSTANT_VALUE="immutable"

# Use nameref for indirect references
declare -n config_ref="config_map"
config_ref["key"]="value"
```

**String Manipulation**:
```bash
# Use parameter expansion over external commands
filename="${path##*/}"           # basename
directory="${path%/*}"           # dirname
extension="${filename##*.}"      # file extension
name_only="${filename%.*}"       # filename without extension

# Use built-in string operations
if [[ "${var,,}" == "true" ]]; then  # lowercase comparison
if [[ "${var^^}" == "YES" ]]; then   # uppercase comparison
```

**Array Operations**:
```bash
# Safe array iteration
for element in "${array[@]:-}"; do
    process_element "$element"
done

# Array manipulation
array+=("new_element")           # Append
unset 'array[index]'            # Remove element
array=("${array[@]:1}")         # Remove first element
array_length="${#array[@]}"     # Get length
```

## Critical Implementation Rules

### 1. Error Handling is Mandatory

```bash
# NEVER ignore errors
# Bad
command || true

# Good
if ! command; then
    log_error "Command failed" "MODULE" $?
    handle_error_recovery
    return 1
fi
```

### 2. Always Use Library Functions

```bash
# NEVER implement duplicate functionality
# Bad
my_custom_logging() { echo "$1" >> log.txt; }

# Good
source "$LIB_DIR/modules/core/logging.sh"
log_info "Using standard logging" "MODULE"
```

### 3. Progress Tracking for Long Operations

```bash
# Track progress for operations > 5 seconds
function deploy_stack() {
    local -i total_steps=5
    local -i current_step=0
    
    update_progress "Creating VPC" $((++current_step)) $total_steps
    create_vpc_with_subnets
    
    update_progress "Launching instances" $((++current_step)) $total_steps
    launch_ec2_instances
    
    # Continue with remaining steps...
}
```

### 4. State Management

```bash
# Always track state for recoverable operations
declare -A deployment_state=(
    ["status"]="initializing"
    ["phase"]="pre-deployment"
    ["start_time"]="$(date -u +%s)"
    ["resources"]=""
)

# Update state at each phase
deployment_state["phase"]="infrastructure"
deployment_state["status"]="in_progress"
save_deployment_state
```

### 5. Input Validation

```bash
# Validate all inputs
function process_request() {
    local request_type="$1"
    local request_data="$2"
    
    # Type validation
    if [[ ! "$request_type" =~ ^(create|update|delete)$ ]]; then
        log_error "Invalid request type: $request_type" "VALIDATE" 502
        return 502
    fi
    
    # Data validation
    if ! validate_json "$request_data"; then
        log_error "Invalid JSON data" "VALIDATE" 101
        return 101
    fi
    
    # Proceed with validated inputs
}
```

### 6. Resource Cleanup

```bash
# Always implement cleanup
trap cleanup_resources EXIT ERR

function cleanup_resources() {
    local exit_code=$?
    log_info "Cleaning up resources" "CLEANUP"
    
    # Cleanup in reverse order of creation
    [[ -n "${instance_id:-}" ]] && terminate_instance "$instance_id"
    [[ -n "${vpc_id:-}" ]] && delete_vpc "$vpc_id"
    
    return $exit_code
}
```

### 7. Configuration Management

```bash
# Use structured configuration
source "$LIB_DIR/config-management.sh"

# Load with validation
load_config_with_validation "$CONFIG_FILE" "production"

# Access via functions
local instance_type=$(get_config_value "compute.instance_type")
local spot_enabled=$(get_config_bool "compute.spot.enabled")
```

## Testing Standards

### Test Organization

```
tests/
├── unit/              # Module-level tests
├── integration/       # Component integration tests
├── security/         # Security validation tests
├── performance/      # Load and benchmark tests
├── deployment/       # Deployment script tests
├── smoke/           # Quick validation tests
└── fixtures/        # Test data and mocks
```

### Test Naming

```bash
# Test files: test-[module-name].sh
test-vpc-module.sh
test-spot-instance.sh
test-error-handling.sh

# Test functions: test_[function_name]_[scenario]
test_create_vpc_success()
test_create_vpc_invalid_cidr()
test_spot_price_cache_expiry()
```

### Test Structure

```bash
#!/usr/bin/env bash
# Test: VPC Module
# Description: Unit tests for VPC creation and management

source "$PROJECT_ROOT/lib/modules/infrastructure/vpc.sh"
source "$PROJECT_ROOT/lib/test-helpers.sh"

# Setup
function setup() {
    export AWS_REGION="us-east-1"
    export DEPLOYMENT_ENV="test"
    mock_aws_cli
}

# Teardown
function teardown() {
    unmock_aws_cli
    unset AWS_REGION DEPLOYMENT_ENV
}

# Test: VPC creation with valid CIDR
function test_create_vpc_success() {
    local vpc_cidr="10.0.0.0/16"
    
    # Arrange
    mock_aws_response "create-vpc" '{"Vpc": {"VpcId": "vpc-12345"}}'
    
    # Act
    local result=$(create_vpc "$vpc_cidr")
    
    # Assert
    assert_equals "vpc-12345" "$result"
    assert_mock_called "aws ec2 create-vpc"
}

# Run tests
run_test_suite "VPC Module Tests"
```

### Assertion Functions

```bash
# Basic assertions
assert_equals "expected" "$actual"
assert_not_equals "unexpected" "$actual"
assert_true "$condition"
assert_false "$condition"
assert_null "$variable"
assert_not_null "$variable"

# Numeric assertions
assert_greater_than 10 "$value"
assert_less_than 100 "$value"
assert_in_range 10 100 "$value"

# String assertions
assert_contains "substring" "$string"
assert_matches "pattern.*" "$string"
assert_empty "$string"
assert_not_empty "$string"

# Array assertions
assert_array_contains "element" "${array[@]}"
assert_array_length 5 "${array[@]}"

# File assertions
assert_file_exists "/path/to/file"
assert_file_not_exists "/path/to/file"
assert_file_contains "/path/to/file" "content"
```

### Test Execution

```bash
# Run all tests
make test

# Run specific category
./tools/test-runner.sh unit
./tools/test-runner.sh integration

# Run with coverage
./tools/test-runner.sh --coverage

# Generate reports
./tools/test-runner.sh --report
```

## Technology Stack

### Core Technologies

**Infrastructure**:
- AWS Services: EC2, VPC, EFS, ALB, CloudFront, IAM, SSM
- Instance Types: g4dn.xlarge (GPU), g5.xlarge, t3.large
- Networking: Multi-AZ, Private subnets, NAT Gateway

**AI/ML Stack**:
- n8n: Workflow automation (port 5678)
- Ollama: LLM inference - DeepSeek-R1:8B, Qwen2.5-VL:7B (port 11434)
- Qdrant: Vector database (port 6333)
- Crawl4AI: Web scraping (port 11235)
- PostgreSQL: Persistence (port 5432)

**Development Tools**:
- Bash: Primary scripting language
- Docker & Docker Compose: Container orchestration
- AWS CLI v2: Cloud management
- jq: JSON processing
- ShellCheck: Script validation

### Version Requirements

```bash
# Minimum versions
bash: any version (works with system bash)
aws-cli >= 2.15.0
docker >= 24.0.0
docker-compose >= 2.23.0
jq >= 1.6
shellcheck >= 0.9.0
```

## Code Organization

### Directory Structure

```
GeuseMaker/
├── lib/
│   ├── modules/
│   │   ├── core/           # Base functionality
│   │   ├── infrastructure/ # AWS resources
│   │   ├── compute/        # EC2 and spot
│   │   ├── application/    # Services
│   │   └── deployment/     # Orchestration
│   └── *.sh               # Standalone libraries
├── scripts/               # Executable scripts
├── tests/                # Test suites
├── config/              # Configuration files
├── tools/               # Development utilities
└── docs/               # Documentation
```

### Module Dependencies

```bash
# Dependency order (most dependent last)
1. core/variables.sh      # No dependencies
2. core/logging.sh        # Depends on variables
3. core/errors.sh         # Depends on logging
4. infrastructure/*.sh    # Depends on core
5. compute/*.sh          # Depends on infrastructure
6. application/*.sh      # Depends on compute
7. deployment/*.sh       # Depends on all above
```

### Import Order

```bash
#!/usr/bin/env bash
# Standard import order

# 1. Script setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 2. Core libraries (order matters)
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/error-handling.sh"

# 3. Bash libraries (3.x+ compatible)
source "$PROJECT_ROOT/lib/associative-arrays.sh"
source "$PROJECT_ROOT/lib/aws-cli-v2.sh"

# 4. Feature libraries (as needed)
source "$PROJECT_ROOT/lib/config-management.sh"
source "$PROJECT_ROOT/lib/spot-instance.sh"
source "$PROJECT_ROOT/lib/deployment-state-manager.sh"

# 5. Module imports
source "$PROJECT_ROOT/lib/modules/core/variables.sh"
source "$PROJECT_ROOT/lib/modules/infrastructure/vpc.sh"
```

## Compliance and Enforcement

### Pre-commit Checks

All code must pass:
1. ShellCheck validation
2. Unit tests for modified modules
3. Security scan
4. Documentation check

### Code Review Checklist

- [ ] Follows naming conventions
- [ ] Includes proper error handling
- [ ] Has comprehensive logging
- [ ] Includes function documentation
- [ ] Validates all inputs
- [ ] Implements cleanup on failure
- [ ] Uses library functions (no duplication)
- [ ] Includes appropriate tests
- [ ] Handles edge cases
- [ ] Works with any bash version

### Continuous Improvement

This document is version-controlled and should be updated when:
- New patterns emerge
- Better practices are discovered
- Technology stack changes
- Lessons learned from incidents

Version: 2.0.0
Last Updated: 2024-01-20