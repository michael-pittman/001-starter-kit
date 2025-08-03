# Unity System Architecture

## Overview

The Unity system provides a unified service management framework for the GeuseMaker deployment system. It implements a modular, event-driven architecture with service registry, event bus, and plugin framework capabilities.

## Core Components

### 1. Unity Core (`lib/unity/core/unity-core.sh`)

The foundation of the Unity system providing:

- **Service Registry**: Manages service registration, discovery, and lifecycle
- **Event Bus**: Enables event-driven communication between components
- **Dependency Management**: Handles service dependencies and initialization order
- **Bash Compatibility**: Works with bash 3.x+ (macOS) and bash 4.x+ (Linux)

Key Functions:
- `unity_register_service()`: Register a new service
- `unity_initialize_service()`: Initialize service with dependency resolution
- `unity_list_services()`: List all registered services
- `emit_event()`: Emit events to the event bus
- `on_event()`: Register event handlers

### 2. Event System (`lib/unity/core/unity-events.sh`)

Provides asynchronous event handling:

- Event emission and subscription
- Handler registration and execution
- Event persistence and logging
- Support for multiple handlers per event

Event Types:
- `SERVICE_REGISTERED`, `SERVICE_INITIALIZED`, `SERVICE_STARTED`
- `SERVICE_UNHEALTHY`, `SERVICE_STOPPED`
- `CONFIG_UPDATED`, `CONFIG_CHANGED`
- `CONTAINER_UNHEALTHY`, `QUOTA_WARNING`
- `ALERT_CREATED`, `COST_THRESHOLD_EXCEEDED`

### 3. Core Services

#### AWS Service (`lib/unity/services/aws-service.sh`)
- Unified AWS operations interface
- Resource discovery and management
- Quota monitoring and alerts
- API response caching
- Rate limiting protection

#### Docker Service (`lib/unity/services/docker-service.sh`)
- Container lifecycle management
- Docker Compose orchestration
- Health monitoring
- Log aggregation
- Container restart policies

#### Config Service (`lib/unity/services/config-service.sh`)
- Unified configuration management
- Multiple source support (YAML, env, Parameter Store)
- Configuration validation
- Hot-reload capabilities
- Type-safe access

#### Monitor Service (`lib/unity/services/monitor-service.sh`)
- System metrics collection
- Health monitoring
- Alert management
- Threshold-based alerting
- Multiple notification channels

## Service Interface Contract

All Unity services must implement:

```bash
# Initialize the service
init_<service>_service()

# Start the service
start_<service>_service()

# Stop the service
stop_<service>_service()

# Check service health
health_<service>_service()

# Get/set service configuration
config_<service>_service()
```

## Configuration Schema

Unity configuration is defined in `config/unity.yml`:

```yaml
unity:
  version: "1.0.0"
  log_level: "INFO"
  
  core:
    state_directory: ".unity/state"
    events_directory: ".unity/events"
    
  services:
    aws:
      enabled: true
      type: "core"
      dependencies: ["config"]
      
  plugins:
    enabled: true
    active: ["spot-optimizer", "cost-analyzer"]
```

## Event Flow

1. Service A performs an action
2. Service A emits an event: `emit_event "ACTION_COMPLETED" "serviceA" "details"`
3. Event system notifies all registered handlers
4. Service B's handler processes the event
5. Service B may emit follow-up events

## Plugin Architecture

Plugins extend Unity functionality:

- Auto-discovery from plugin directory
- Priority-based loading
- Standard plugin interface
- Configuration through unity.yml

## Deployment Integration

Unity integrates with existing deployment scripts:

```bash
# Source Unity core
source lib/unity/core/unity-core.sh

# Register deployment service
unity_register_service "deployment" "$SCRIPT_DIR/deployment-service.sh" "core" "aws,docker,config"

# Initialize service
unity_initialize_service "deployment"

# Start deployment
unity_emit_event "DEPLOYMENT_STARTED" "deployment" "$STACK_NAME"
```

## Directory Structure

```
lib/unity/
├── core/
│   ├── unity-core.sh      # Core functionality
│   ├── unity-events.sh    # Event system
│   └── unity-plugins.sh   # Plugin framework
├── services/
│   ├── aws-service.sh     # AWS operations
│   ├── docker-service.sh  # Container management
│   ├── config-service.sh  # Configuration
│   └── monitor-service.sh # Monitoring
├── plugins/
│   ├── spot-optimizer/    # Spot instance optimization
│   ├── cost-analyzer/     # Cost analysis
│   ├── security-validator/# Security validation
│   └── performance-tuner/ # Performance optimization
└── templates/
    └── service-template.sh # Service template
```

## Best Practices

1. **Service Design**
   - Keep services focused on single responsibility
   - Implement all interface methods
   - Handle errors gracefully
   - Emit appropriate events

2. **Event Usage**
   - Use descriptive event names
   - Include relevant context data
   - Don't assume synchronous processing
   - Handle event failures gracefully

3. **Configuration**
   - Use config service for all settings
   - Validate configuration on load
   - Support environment overrides
   - Document all configuration options

4. **Error Handling**
   - Use standard error codes
   - Log errors appropriately
   - Emit error events
   - Provide recovery mechanisms

## Future Enhancements

1. **Phase 2**: Plugin framework implementation
2. **Phase 3**: Advanced monitoring and analytics
3. **Phase 4**: Multi-region orchestration
4. **Phase 5**: AI-driven optimization