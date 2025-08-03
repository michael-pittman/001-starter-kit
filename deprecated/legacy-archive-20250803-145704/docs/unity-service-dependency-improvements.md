# Unity Service Dependency and Initialization Improvements

## Overview

This document describes the improvements made to the Unity service dependency and initialization system to address issues with service loading order, circular dependencies, and error recovery.

## Key Improvements

### 1. Service Dependency Resolver (`lib/unity/core/service-dependency-resolver.sh`)

Implements a robust dependency resolution system using **topological sorting** (Kahn's algorithm) to ensure services are initialized in the correct order.

**Features:**
- **Topological Sort**: Automatically determines the correct initialization order based on dependencies
- **Cycle Detection**: Detects and reports circular dependencies using depth-first search
- **Bash 3/4 Compatibility**: Works with both associative arrays (bash 4+) and variable naming (bash 3)
- **Dependency Validation**: Validates all dependencies before initialization

**Key Functions:**
- `register_service_dependencies()` - Register service dependencies
- `topological_sort_services()` - Determine initialization order
- `validate_service_dependencies()` - Check for circular dependencies
- `get_service_initialization_order()` - Get ordered list of services to initialize

### 2. Enhanced Unity Core (`lib/unity/core/unity-core.sh`)

Updated to integrate the dependency resolver and improve service initialization.

**Improvements:**
- **Dependency-aware initialization**: Services are initialized in dependency order
- **Better error handling**: Improved error messages and recovery options
- **Batch initialization**: `unity_initialize_all_services()` initializes all registered services
- **Fallback mechanisms**: Works even if dependency resolver is not available

### 3. Service Recovery System (`lib/unity/core/service-recovery.sh`)

Implements comprehensive error recovery and rollback mechanisms.

**Recovery Strategies:**
- **Retry**: Retry with exponential backoff and jitter
- **Restart**: Stop and restart the service
- **Failover**: Switch to backup service
- **Rollback**: Revert to previous state

**Features:**
- **Health Monitoring**: Continuous health checks with automatic recovery
- **Recovery Checkpoints**: Save and restore service states
- **Batch Recovery**: Recover multiple failed services
- **Configurable Limits**: Max retries, timeouts, and delays

## Unity Service Dependencies

The standard Unity services have the following dependency graph:

```
unity-events (no dependencies)
unity-config (no dependencies)
    ├── unity-performance
    ├── unity-docker
    └── unity-aws
         └── unity-performance
unity-monitor (depends on: config, aws, docker, events)
unity-deployment (depends on: all infrastructure services)
```

Initialization order: `unity-events`, `unity-config`, `unity-performance`, `unity-docker`, `unity-aws`, `unity-monitor`, `unity-deployment`

## Usage Examples

### Basic Service Registration

```bash
# Source Unity core
source lib/unity/core/unity-core.sh

# Initialize Unity
unity_init

# Register services with dependencies
unity_register_service "my-service" "/path/to/service.sh" "custom" "unity-config,unity-aws"

# Initialize service (dependencies will be initialized automatically)
unity_initialize_service "my-service"
```

### Using Dependency Resolver

```bash
# Source dependency resolver
source lib/unity/core/service-dependency-resolver.sh

# Initialize resolver
init_dependency_resolver

# Register dependencies
register_service_dependencies "service-a" "service-b" "service-c"
register_service_dependencies "service-b" "service-d"
register_service_dependencies "service-c" "service-d"
register_service_dependencies "service-d"

# Validate (checks for cycles)
validate_service_dependencies || echo "Circular dependency detected!"

# Get initialization order
order=$(get_service_initialization_order)
echo "Initialize in order: $order"
```

### Error Recovery

```bash
# Source recovery system
source lib/unity/core/service-recovery.sh

# Initialize recovery
init_recovery_system

# Register recovery strategy
register_recovery_strategy "my-service" "retry" 5

# Register rollback handler
register_rollback_handler "my-service" "my_rollback_function"

# Attempt recovery on failure
attempt_service_recovery "my-service" 1 "initialization_failed"

# Monitor with automatic recovery
monitor_services_with_recovery 30  # Check every 30 seconds
```

## Testing

### Unit Tests
- `tests/unity/test-service-dependencies.sh` - Tests dependency resolver functionality

### Integration Tests
- `tests/unity/integration/test-unity-service-integration-improved.sh` - Comprehensive integration tests

## Best Practices

1. **Always declare dependencies**: When registering a service, specify all direct dependencies
2. **Avoid circular dependencies**: Design services with clear hierarchical dependencies
3. **Implement health checks**: Add `health_<service>_service()` functions for monitoring
4. **Handle initialization failures**: Return non-zero from init functions on failure
5. **Use recovery strategies**: Register appropriate recovery strategies for critical services

## Migration Guide

To migrate existing Unity services:

1. **Add dependency declarations** when registering services:
   ```bash
   # Old
   unity_register_service "my-service" "/path/to/service.sh"
   
   # New
   unity_register_service "my-service" "/path/to/service.sh" "custom" "unity-config,unity-aws"
   ```

2. **Ensure init functions return proper status**:
   ```bash
   init_my_service() {
       # Initialization logic
       if [[ $? -ne 0 ]]; then
           return 1  # Signal failure
       fi
       return 0  # Signal success
   }
   ```

3. **Add health check functions** (optional but recommended):
   ```bash
   health_my_service() {
       # Check service health
       if service_is_healthy; then
           return 0
       else
           return 1
       fi
   }
   ```

## Benefits

1. **Correct Initialization Order**: Services always initialize with their dependencies available
2. **No Circular Dependencies**: System detects and prevents circular dependency issues
3. **Automatic Recovery**: Failed services can recover automatically
4. **Better Error Messages**: Clear indication of what failed and why
5. **Bash 3/4 Compatibility**: Works on older systems (macOS default bash 3.2)
6. **Production Ready**: Comprehensive error handling and recovery mechanisms