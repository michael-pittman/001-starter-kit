# Module Architecture

> GeuseMaker's modular system design and Unity architecture overview

## Overview

GeuseMaker has evolved from a collection of individual scripts to a unified, event-driven architecture powered by the Unity system. This document describes the modular architecture that provides maintainability, scalability, and extensibility.

## Architecture Evolution

### Before Unity (Legacy)
- 247+ individual shell scripts
- Complex interdependencies
- Inconsistent error handling
- Difficult to maintain and extend

### After Unity (Current)
- 20 core Unity files
- Event-driven service architecture
- Unified configuration system
- 70% faster initialization
- Consistent patterns and interfaces

## Unity Architecture Overview

```
GeuseMaker Unity Architecture
├── Unity Core System (lib/unity/core/)
├── Unity Services (lib/unity/services/)
├── Unity Events (lib/unity/events/)
├── Unity Plugins (lib/unity/plugins/)
└── Application Layer (AI Services, AWS Infrastructure)
```

## Core Unity Components

### 1. Unity Core System (`lib/unity/core/`)

The foundation of the Unity architecture:

```
lib/unity/core/
├── unity-core.sh              # Service registry and lifecycle management
├── unity-events.sh            # Event bus implementation
├── unity-plugins.sh           # Plugin framework
├── service-dependency-resolver.sh  # Dependency resolution
├── service-recovery.sh        # Service recovery mechanisms
└── unity-preflight.sh         # Pre-deployment validation
```

**Key Responsibilities:**
- Service registration and discovery
- Event system coordination
- Plugin lifecycle management
- Dependency resolution
- Error recovery and rollback

### 2. Unity Services (`lib/unity/services/`)

Specialized services for different operational areas:

```
lib/unity/services/
├── aws-service.sh             # AWS infrastructure operations
├── docker-service.sh          # Container lifecycle management
├── config-service.sh          # Configuration management
├── monitor-service.sh         # System monitoring and health
├── unity-deployment-service.sh # Deployment orchestration
└── unity-performance-service.sh # Performance optimization
```

**Service Interface Contract:**
```bash
# Standard service interface
init_<service>_service()      # Initialize service
start_<service>_service()     # Start service operations
stop_<service>_service()      # Stop service gracefully
health_<service>_service()    # Health check
config_<service>_service()    # Configuration management
```

### 3. Unity Events (`lib/unity/events/`)

Event-driven communication system:

```
lib/unity/events/
├── event-bus.sh              # Event dispatching and routing
├── event-persistence.sh      # Event storage and replay
├── reactive-patterns.sh      # Reactive programming patterns
├── rollback-manager.sh       # Rollback on failure
└── event-handlers.sh         # Standard event handlers
```

**Event Flow Example:**
```
User Command → DEPLOYMENT_REQUESTED → AWS Service
     ↓
AWS Service → VPC_CREATED → Monitor Service
     ↓
Monitor Service → HEALTH_CHECK_PASSED → Deployment Service
     ↓
Deployment Service → DEPLOYMENT_COMPLETED → User Notification
```

### 4. Unity Plugins (`lib/unity/plugins/`)

Extensible plugin system for specialized functionality:

```
lib/unity/plugins/
├── spot-optimizer/           # 70% cost savings via spot instances
├── cost-analyzer/            # Cost tracking and optimization
├── security-validator/       # Security compliance checks
├── performance-tuner/        # Performance optimization
└── plugin-framework.sh       # Plugin development framework
```

## Service Architecture Patterns

### 1. Service Registration Pattern

```bash
# Service registration with dependencies
unity_register_service "aws-service" \
  "$SERVICE_PATH/aws-service.sh" \
  "critical" \
  "config-service"

# Service with plugins
unity_register_service "deployment-service" \
  "$SERVICE_PATH/deployment-service.sh" \
  "critical" \
  "aws-service,docker-service" \
  "spot-optimizer,cost-analyzer"
```

### 2. Event-Driven Communication

```bash
# Emit events for significant actions
unity_emit_event "DEPLOYMENT_STARTED" "deployment-service" "$deployment_data"

# React to events from other services
handle_vpc_created() {
    local event_data="$1"
    # Process VPC creation completion
    unity_emit_event "NETWORKING_READY" "aws-service" "$vpc_info"
}
unity_on_event "VPC_CREATED" handle_vpc_created
```

### 3. Configuration Hierarchy

Unity uses a unified configuration system with clear precedence:

```yaml
# config/unity.yml - Single source of truth
unity:
  deployment:
    types: [spot, alb, cdn, full]
    environments: [dev, staging, prod]
    defaults:
      instance_type: g4dn.xlarge
      region: us-east-1
  services:
    aws:
      enabled: true
      config:
        spot_enabled: true
        multi_az: true
    docker:
      enabled: true
      config:
        gpu_enabled: true
        ai_stack: true
  plugins:
    spot-optimizer:
      enabled: true
      priority: 100
```

**Configuration Precedence (highest to lowest):**
1. Command-line arguments
2. Environment variables
3. Unity configuration file
4. AWS Parameter Store (for secrets)
5. Service defaults

## Module Dependencies

### Service Dependency Graph

```
config-service (foundation)
    ↓
aws-service (depends on config)
    ↓
docker-service (depends on aws)
    ↓
monitor-service (depends on aws, docker)
    ↓
deployment-service (orchestrates all)
```

### Plugin Dependencies

```
Core Services → Plugins → Enhanced Functionality

aws-service + spot-optimizer → 70% cost savings
aws-service + cost-analyzer → cost optimization
deployment-service + security-validator → compliance
monitor-service + performance-tuner → optimization
```

## Legacy Module Consolidation

### Before Consolidation (Legacy)

The original system had 10+ module categories with complex interdependencies:

```
lib/modules/ (LEGACY - ARCHIVED)
├── core/                     # 7 core utility modules
├── infrastructure/           # 7 AWS infrastructure modules
├── compute/                  # 7 EC2 and spot optimization modules
├── application/              # 5 application deployment modules
├── deployment/               # 4 orchestration modules
├── monitoring/               # 2 health check modules
├── errors/                   # 2 error handling modules
├── config/                   # 2 configuration modules
├── instances/                # 4 instance management modules
└── cleanup/                  # 1 resource cleanup module
```

### After Unity Consolidation (Current)

Consolidated into 20 Unity files with clear separation of concerns:

```
lib/unity/ (CURRENT)
├── core/ (5 files)           # Unity system core
├── services/ (8 files)       # Specialized services
├── events/ (4 files)         # Event system
├── plugins/ (3+ files)       # Extensible plugins
└── templates/ (1 file)       # Development templates
```

**Consolidation Benefits:**
- 90% reduction in file count (247 → 20)
- 70% faster initialization
- Unified patterns and interfaces
- Simplified dependency management
- Enhanced maintainability

## Development Patterns

### 1. Creating New Services

Use the service template for consistency:

```bash
# Create new service from template
cp lib/unity/templates/service-template.sh lib/unity/services/my-service.sh

# Implement standard interface
init_myservice_service() {
    unity_log "INFO" "Initializing my service..."
    # Initialization logic
}

start_myservice_service() {
    unity_log "INFO" "Starting my service..."
    # Service startup logic
}

# Register the service
unity_register_service "myservice" \
  "$SCRIPT_DIR/my-service.sh" \
  "standard" \
  "config-service"
```

### 2. Event-Driven Development

```bash
# Emit events for significant actions
deploy_infrastructure() {
    unity_log "INFO" "Starting infrastructure deployment..."
    
    # Perform deployment
    create_vpc
    create_ec2_instances
    
    # Notify other services
    unity_emit_event "INFRASTRUCTURE_READY" "myservice" "$deployment_info"
}

# React to events from other services
handle_infrastructure_ready() {
    local deployment_info="$1"
    unity_log "INFO" "Infrastructure ready, starting applications..."
    deploy_applications "$deployment_info"
}
unity_on_event "INFRASTRUCTURE_READY" handle_infrastructure_ready
```

### 3. Plugin Development

```bash
# Plugin interface implementation
init_plugin() {
    unity_log "INFO" "Initializing my plugin..."
    # Plugin initialization
}

handle_event() {
    local event_type="$1"
    local event_data="$2"
    
    case "$event_type" in
        "DEPLOYMENT_STARTED")
            optimize_deployment "$event_data"
            ;;
        "COST_ANALYSIS_REQUESTED")
            analyze_costs "$event_data"
            ;;
    esac
}

cleanup() {
    unity_log "INFO" "Cleaning up plugin resources..."
    # Plugin cleanup
}
```

## Performance Architecture

### Initialization Optimization

Unity's optimized initialization process:

```
Traditional Approach (Legacy):
├── Load 247 individual scripts
├── Complex dependency resolution
├── Redundant validations
└── ~15-20 seconds initialization

Unity Approach (Current):
├── Load 20 core Unity files
├── Service-based dependency resolution
├── Lazy loading of components
└── ~3-5 seconds initialization (70% faster)
```

### Event System Performance

```bash
# Asynchronous event processing
unity_emit_event_async() {
    local event="$1"
    local source="$2"
    local data="$3"
    
    # Process in background to avoid blocking
    (
        process_event "$event" "$source" "$data"
    ) &
}

# Event batching for high-frequency events
unity_batch_events() {
    local events=("$@")
    
    # Process multiple events efficiently
    for event in "${events[@]}"; do
        process_event_batch "$event"
    done
}
```

## Testing Architecture

### Unity Testing Hierarchy

```
tests/unity/
├── unit/                     # Individual service tests
│   ├── test-unity-aws-service.sh
│   ├── test-unity-docker-service.sh
│   └── test-unity-config-service.sh
├── integration/              # Service interaction tests
│   ├── test-unity-service-integration.sh
│   └── test-unity-deployment-flow.sh
├── performance/              # Performance benchmarks
│   └── test-unity-performance-benchmarks.sh
└── system/                   # End-to-end tests
    └── test-unity-complete-system.sh
```

### Test Patterns

```bash
# Unit test pattern
test_aws_service_vpc_creation() {
    # Setup
    init_aws_service
    
    # Test
    local result=$(create_vpc "test-vpc")
    
    # Assert
    assert_contains "$result" "vpc-"
    assert_service_healthy "aws-service"
}

# Integration test pattern
test_deployment_flow() {
    # Setup services
    start_unity_services
    
    # Test event flow
    unity_emit_event "DEPLOYMENT_REQUESTED" "test" "$test_data"
    
    # Wait for completion
    wait_for_event "DEPLOYMENT_COMPLETED" 60
    
    # Verify results
    assert_deployment_successful
}
```

## Monitoring Architecture

### Service Health Monitoring

```bash
# Health check interface
health_check_service() {
    local service="$1"
    
    # Check service status
    if ! unity_service_running "$service"; then
        return 1
    fi
    
    # Check service health
    "${service}_health_check"
}

# Automated health monitoring
monitor_services() {
    while true; do
        for service in $(unity_list_services); do
            if ! health_check_service "$service"; then
                unity_emit_event "SERVICE_UNHEALTHY" "monitor" "$service"
            fi
        done
        sleep 30
    done
}
```

### Performance Monitoring

```bash
# Performance metrics collection
collect_performance_metrics() {
    local metrics=$(unity_get_metrics)
    
    # Store metrics
    echo "$metrics" >> "$UNITY_METRICS_FILE"
    
    # Send to CloudWatch
    aws cloudwatch put-metric-data \
        --namespace "GeuseMaker/Unity" \
        --metric-data "$metrics"
}
```

## Security Architecture

### Service Isolation

```bash
# Service isolation patterns
run_service_isolated() {
    local service="$1"
    
    # Run in separate process group
    setsid bash -c "
        # Set service-specific environment
        export UNITY_SERVICE_NAME='$service'
        export UNITY_SERVICE_ISOLATION=true
        
        # Execute service
        execute_service '$service'
    " &
}
```

### Event Validation

```bash
# Event validation and sanitization
validate_event() {
    local event_type="$1"
    local event_data="$2"
    
    # Validate event type
    if ! unity_valid_event_type "$event_type"; then
        unity_log "ERROR" "Invalid event type: $event_type"
        return 1
    fi
    
    # Sanitize event data
    local sanitized_data=$(sanitize_event_data "$event_data")
    
    # Log event for audit
    unity_audit_log "EVENT" "$event_type" "$sanitized_data"
}
```

## Migration Guide

### From Legacy to Unity

For migrating custom scripts to Unity:

1. **Identify Service Category**: Determine which Unity service your script belongs to
2. **Extract Core Logic**: Separate business logic from boilerplate code
3. **Implement Service Interface**: Use standard Unity service patterns
4. **Add Event Support**: Emit and handle relevant events
5. **Update Dependencies**: Use Unity dependency resolution
6. **Add Tests**: Create appropriate unit and integration tests

### Migration Example

```bash
# Legacy script (before)
#!/bin/bash
source lib/modules/core/logging.sh
source lib/modules/infrastructure/vpc.sh
source lib/modules/infrastructure/ec2.sh

deploy_infrastructure() {
    log_info "Starting deployment..."
    create_vpc
    create_ec2_instances
    log_info "Deployment complete"
}

# Unity service (after)
#!/bin/bash
init_infrastructure_service() {
    unity_log "INFO" "Infrastructure service initialized"
}

start_infrastructure_service() {
    unity_on_event "DEPLOYMENT_REQUESTED" handle_deployment_request
}

handle_deployment_request() {
    local deployment_data="$1"
    
    unity_log "INFO" "Starting infrastructure deployment..."
    
    # Create infrastructure
    create_vpc "$deployment_data"
    create_ec2_instances "$deployment_data"
    
    # Notify completion
    unity_emit_event "INFRASTRUCTURE_READY" "infrastructure-service" "$deployment_data"
}
```

## Future Architecture Considerations

### Scalability Enhancements

- **Microservices**: Split large services into smaller, focused services
- **Containerization**: Run Unity services in containers for better isolation
- **Distributed Events**: Extend event system across multiple nodes
- **Load Balancing**: Distribute Unity services across multiple instances

### Technology Integration

- **Kubernetes**: Deploy Unity as Kubernetes operators
- **Terraform**: Generate Terraform from Unity configurations
- **Ansible**: Use Unity for configuration management
- **Prometheus**: Enhanced metrics collection and alerting

---

**Related Documentation:**
- [Unity Architecture Guide](unity/unity-architecture.md)
- [Unity Developer Guide](unity/core/unity-developer-guide.md)
- [Architecture Overview](guides/architecture.md)