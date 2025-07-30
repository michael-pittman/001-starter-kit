# Module Architecture Documentation

## Overview

The GeuseMaker project employs a sophisticated modular architecture designed for enterprise-scale AWS deployments. This document serves as the definitive guide for understanding, developing, and maintaining modules within the system.

## Module Organization Patterns

### Directory Structure

```
/lib/modules/
├── core/              # Foundation modules - loaded first
│   ├── errors.sh      # Error handling and recovery
│   ├── logging.sh     # Structured logging
│   ├── registry.sh    # Resource tracking
│   ├── validation.sh  # Input validation
│   └── variables.sh   # Variable management
├── infrastructure/    # AWS infrastructure modules
│   ├── alb.sh         # Application Load Balancer
│   ├── cloudfront.sh  # CDN configuration
│   ├── compute.sh     # Generic compute resources
│   ├── ec2.sh         # EC2 instance management
│   └── vpc.sh         # VPC and networking
├── application/       # Application-layer modules
│   └── service_config.sh  # Service configuration
├── deployment/        # Deployment orchestration
│   ├── orchestrator.sh    # Deployment coordination
│   ├── rollback.sh        # Rollback mechanisms
│   └── state.sh           # State management
├── monitoring/        # Observability modules
│   └── metrics.sh     # Metrics collection
├── compatibility/     # Legacy support modules
└── cleanup/          # Resource cleanup modules
```

### Module Categories

1. **Core Modules**: Foundation functionality required by all other modules
2. **Infrastructure Modules**: AWS resource provisioning and management
3. **Application Modules**: Service configuration and application logic
4. **Deployment Modules**: Orchestration and state management
5. **Monitoring Modules**: Observability and metrics
6. **Utility Modules**: Helper functions and compatibility layers

## Module Naming Conventions

### File Naming Standards

```bash
# Pattern: <category>_<functionality>.sh
core/errors.sh          # Core error handling
infrastructure/alb.sh   # Infrastructure ALB management
deployment/state.sh     # Deployment state tracking

# Multi-word names use underscores
service_config.sh       # Service configuration
error_handling.sh       # Error handling utilities
```

### Function Naming Patterns

```bash
# Module-specific functions: <module>_<action>_<target>
vpc_create_subnet()
ec2_launch_instance()
alb_configure_target_group()

# Public API functions: <action>_<target>
create_vpc()
launch_instance()
configure_alb()

# Internal functions: _<module>_<function>
_vpc_validate_cidr()
_ec2_check_capacity()
```

### Variable Naming Conventions

```bash
# Global module variables: <MODULE>_<VARIABLE>
VPC_ID
EC2_INSTANCE_TYPE
ALB_TARGET_GROUP_ARN

# Module constants: <MODULE>_<CONSTANT>_<NAME>
EC2_DEFAULT_TIMEOUT=300
VPC_DEFAULT_CIDR="10.0.0.0/16"
ALB_HEALTH_CHECK_INTERVAL=30

# Associative arrays: <MODULE>_<PURPOSE>_MAP
declare -A EC2_INSTANCE_CACHE
declare -A VPC_SUBNET_MAP
declare -A ALB_LISTENER_CONFIG
```

## Module Dependencies

### Dependency Hierarchy

```
Level 0: Base Prerequisites
├── bash 3.x+ (compatible)
└── AWS CLI v2

Level 1: Core Foundation
├── core/variables.sh    # Variable sanitization
├── core/errors.sh       # Error definitions
└── core/logging.sh      # Logging framework

Level 2: Core Services  
├── core/registry.sh     # Depends on: logging, variables
└── core/validation.sh   # Depends on: errors, logging

Level 3: Infrastructure
├── infrastructure/vpc.sh      # Depends on: core/*
├── infrastructure/ec2.sh      # Depends on: core/*, vpc
└── infrastructure/alb.sh      # Depends on: core/*, vpc, ec2

Level 4: Application
└── application/service_config.sh  # Depends on: core/*, infrastructure/*

Level 5: Deployment
├── deployment/state.sh        # Depends on: all lower levels
└── deployment/orchestrator.sh # Depends on: all modules
```

### Dependency Declaration

Each module must declare its dependencies at the top:

```bash
#!/bin/bash
# Module: infrastructure/ec2.sh
# Dependencies: core/variables.sh, core/errors.sh, infrastructure/vpc.sh
# Description: EC2 instance management and provisioning

# Dependency checks
[[ -z "${VARIABLES_LOADED}" ]] && source "${LIB_DIR}/modules/core/variables.sh"
[[ -z "${ERRORS_LOADED}" ]] && source "${LIB_DIR}/modules/core/errors.sh"
[[ -z "${VPC_MODULE_LOADED}" ]] && source "${LIB_DIR}/modules/infrastructure/vpc.sh"

# Module guard
[[ -n "${EC2_MODULE_LOADED}" ]] && return 0
declare -g EC2_MODULE_LOADED=true
```

## Module Template Structure

### Standard Module Template

```bash
#!/bin/bash
#------------------------------------------------------------------------------
# Module: <category>/<module_name>.sh
# Description: Brief description of module purpose
# Dependencies: List all required modules
# Public Functions:
#   - function_name(): Brief description
#   - another_function(): Brief description
# Version: 1.0.0
# Last Updated: YYYY-MM-DD
#------------------------------------------------------------------------------

# Dependency imports
[[ -z "${CORE_LOADED}" ]] && source "${LIB_DIR}/modules/core/core.sh"

# Module guard to prevent multiple loads
[[ -n "${MODULE_NAME_LOADED}" ]] && return 0
declare -g MODULE_NAME_LOADED=true

#------------------------------------------------------------------------------
# Module Constants
#------------------------------------------------------------------------------
declare -r MODULE_DEFAULT_TIMEOUT=300
declare -r MODULE_MAX_RETRIES=3

#------------------------------------------------------------------------------
# Module Variables
#------------------------------------------------------------------------------
declare -g MODULE_STATE=""
declare -A MODULE_CACHE=()

#------------------------------------------------------------------------------
# Private Functions (prefix with _)
#------------------------------------------------------------------------------
_module_validate_input() {
    local input="$1"
    [[ -z "$input" ]] && error_invalid_parameter "input" "cannot be empty"
    return 0
}

#------------------------------------------------------------------------------
# Public Functions
#------------------------------------------------------------------------------

# Function: module_initialize
# Description: Initialize module with configuration
# Parameters:
#   $1 - Configuration parameter
# Returns:
#   0 - Success
#   1 - Failure
module_initialize() {
    local config="$1"
    
    log_info "Initializing module with config: $config"
    _module_validate_input "$config" || return 1
    
    MODULE_STATE="initialized"
    return 0
}

# Function: module_execute
# Description: Execute primary module functionality
# Parameters:
#   $1 - Action parameter
# Returns:
#   0 - Success
#   1 - Failure
module_execute() {
    local action="$1"
    
    [[ "$MODULE_STATE" != "initialized" ]] && {
        error_module_not_initialized "MODULE_NAME"
        return 1
    }
    
    case "$action" in
        "start") _module_start ;;
        "stop")  _module_stop ;;
        *)       error_invalid_parameter "action" "$action" ;;
    esac
}

#------------------------------------------------------------------------------
# Module Initialization
#------------------------------------------------------------------------------
log_debug "Module MODULE_NAME loaded successfully"
```

## Module Loading Order

### Standard Loading Sequence

```bash
# 1. Prerequisites and environment setup
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"    # Base logging
source "$PROJECT_ROOT/lib/error-handling.sh"           # Error framework

# 2. Core modules (order matters)
source "$LIB_DIR/modules/core/variables.sh"            # Variable management
source "$LIB_DIR/modules/core/errors.sh"               # Error types
source "$LIB_DIR/modules/core/logging.sh"              # Enhanced logging
source "$LIB_DIR/modules/core/registry.sh"             # Resource tracking
source "$LIB_DIR/modules/core/validation.sh"           # Input validation

# 3. Infrastructure modules (can parallelize some)
source "$LIB_DIR/modules/infrastructure/vpc.sh"        # Network foundation
source "$LIB_DIR/modules/infrastructure/ec2.sh"        # Compute resources
source "$LIB_DIR/modules/infrastructure/alb.sh"        # Load balancing

# 4. Application modules
source "$LIB_DIR/modules/application/service_config.sh" # Service setup

# 5. Deployment modules
source "$LIB_DIR/modules/deployment/state.sh"          # State management
source "$LIB_DIR/modules/deployment/orchestrator.sh"   # Orchestration
```

### Dependency Resolution

The module system uses these mechanisms for dependency resolution:

1. **Explicit Guards**: Each module checks for its dependencies
2. **Lazy Loading**: Modules load dependencies only when needed
3. **Circular Prevention**: Module guards prevent circular dependencies
4. **Version Checking**: Modules can specify minimum versions

Example dependency resolution:

```bash
# Module A depends on Module B
# Module B depends on Module C
# Loading Module A automatically loads C, then B, then A

load_module() {
    local module_path="$1"
    local module_name=$(basename "$module_path" .sh)
    local guard_var="${module_name^^}_MODULE_LOADED"
    
    # Check if already loaded
    [[ -n "${!guard_var}" ]] && return 0
    
    # Load dependencies first
    load_module_dependencies "$module_path"
    
    # Load the module
    source "$module_path"
}
```

## Module Testing Requirements

### Unit Tests

Each module must have corresponding unit tests:

```bash
# Test file location: tests/modules/<category>/test_<module_name>.sh
tests/modules/core/test_errors.sh
tests/modules/infrastructure/test_vpc.sh
tests/modules/deployment/test_orchestrator.sh
```

### Test Structure

```bash
#!/bin/bash
# Test: <module_name> module functionality

source "$(dirname "$0")/../../../lib/test-helpers.sh"
source "$LIB_DIR/modules/<category>/<module_name>.sh"

test_module_initialization() {
    # Test module loads correctly
    assert_equals "true" "${MODULE_NAME_LOADED}" \
        "Module should be loaded"
}

test_module_basic_functionality() {
    # Test core functions
    local result=$(module_function "input")
    assert_equals "expected" "$result" \
        "Function should return expected value"
}

test_module_error_handling() {
    # Test error conditions
    module_function "" 2>&1 | grep -q "ERROR" || \
        fail "Should handle empty input"
}

# Run tests
run_test_suite "Module Name Tests" \
    test_module_initialization \
    test_module_basic_functionality \
    test_module_error_handling
```

### Validation Requirements

1. **Syntax Validation**: All modules must pass shellcheck
2. **Dependency Validation**: Dependencies must be declared and available
3. **Function Coverage**: All public functions must have tests
4. **Error Scenarios**: Error paths must be tested
5. **Integration Tests**: Module interactions must be validated

### Module Validation Commands

```bash
# Validate individual module
./tools/validate-module.sh infrastructure/vpc.sh

# Validate all modules
make validate-modules

# Run module-specific tests
./tools/test-runner.sh modules

# Generate module dependency graph
./tools/generate-module-graph.sh > docs/module-dependencies.png
```

## Best Practices

### Module Development Guidelines

1. **Single Responsibility**: Each module handles one specific area
2. **Clear Interfaces**: Well-defined public functions with documentation
3. **Error Propagation**: Consistent error handling and reporting
4. **Resource Cleanup**: Always provide cleanup functions
5. **State Management**: Module state should be explicitly managed
6. **Idempotency**: Functions should be safe to call multiple times

### Documentation Standards

Every module must include:
- Purpose and description
- Dependency list
- Public API documentation
- Usage examples
- Error conditions
- Performance considerations

### Performance Considerations

1. **Lazy Loading**: Load modules only when needed
2. **Caching**: Use module-level caches for expensive operations
3. **Batch Operations**: Group AWS API calls when possible
4. **Resource Pooling**: Reuse connections and resources
5. **Async Operations**: Support background tasks where appropriate

## Module Registry

The system maintains a central registry of all loaded modules:

```bash
# Global module registry
declare -A LOADED_MODULES=()
declare -A MODULE_VERSIONS=()
declare -A MODULE_DEPENDENCIES=()

# Registration happens automatically on load
register_module() {
    local module_name="$1"
    local module_version="$2"
    local module_deps="$3"
    
    LOADED_MODULES["$module_name"]=true
    MODULE_VERSIONS["$module_name"]="$module_version"
    MODULE_DEPENDENCIES["$module_name"]="$module_deps"
}

# Query module status
is_module_loaded() {
    local module_name="$1"
    [[ "${LOADED_MODULES[$module_name]}" == "true" ]]
}
```

## Extending the Module System

### Creating New Modules

1. Choose appropriate category directory
2. Use the module template as starting point
3. Define clear public API
4. Implement comprehensive error handling
5. Add unit tests
6. Update module registry
7. Document in this guide

### Module Versioning

Modules follow semantic versioning:
- **Major**: Breaking API changes
- **Minor**: New functionality (backward compatible)
- **Patch**: Bug fixes

Version checks example:
```bash
require_module_version "infrastructure/vpc" "2.0.0"
```

### Module Deprecation

When deprecating module functionality:
1. Add deprecation warnings
2. Provide migration path
3. Support old API for 2 major versions
4. Update documentation
5. Remove in major version release

## Troubleshooting

### Common Issues

1. **Module Not Found**: Check path and file permissions
2. **Circular Dependencies**: Review dependency declarations
3. **Version Conflicts**: Update to latest module versions
4. **Loading Errors**: Verify bash version and syntax
5. **Missing Dependencies**: Run dependency check tool

### Debugging Tools

```bash
# Enable module debug logging
export MODULE_DEBUG=true

# Trace module loading
export MODULE_TRACE=true

# Validate module dependencies
./tools/check-module-deps.sh

# Module profiling
./tools/profile-modules.sh
```

## Conclusion

This modular architecture provides a scalable, maintainable foundation for complex AWS deployments. By following these guidelines, developers can create robust modules that integrate seamlessly with the existing system while maintaining high code quality and reliability standards.