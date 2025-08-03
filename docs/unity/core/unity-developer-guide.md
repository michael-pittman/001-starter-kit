# Unity Developer Guide

## Table of Contents

1. [Getting Started](#getting-started)
2. [Core APIs](#core-apis)
3. [Service Development](#service-development)
4. [Event System](#event-system)
5. [Plugin Development](#plugin-development)
6. [Testing & Debugging](#testing--debugging)
7. [Best Practices](#best-practices)
8. [Code Examples](#code-examples)

## Getting Started

### Development Environment Setup

```bash
# Clone repository
git clone https://github.com/your-org/geusemaker.git
cd geusemaker

# Set up development environment
./scripts/setup-dev-environment.sh

# Install development dependencies
make dev-setup

# Run tests to verify setup
make test
```

### Project Structure

```
geusemaker/
├── lib/unity/              # Unity core libraries
│   ├── core/              # Core utilities
│   ├── services/          # Service implementations
│   ├── events/            # Event system
│   └── plugins/           # Plugin framework
├── scripts/               # Executable scripts
├── config/                # Configuration files
├── tests/unity/           # Unity-specific tests
└── examples/unity/        # Example implementations
```

## Core APIs

### Service Registry API

The Service Registry is the central component for service management.

#### Register a Service

```bash
# Function: register_service
# Parameters: service_name, service_path, dependencies
register_service() {
    local service_name="$1"
    local service_path="$2"
    local dependencies="${3:-}"
    
    # Implementation
    unity_registry_add "$service_name" "$service_path" "$dependencies"
}

# Example usage
register_service "my-service" "/path/to/service.sh" "aws,config"
```

#### Service Lifecycle Management

```bash
# Start a service
unity_service_start "my-service"

# Stop a service
unity_service_stop "my-service"

# Restart a service
unity_service_restart "my-service"

# Check service status
unity_service_status "my-service"
```

### Event Bus API

The Event Bus enables asynchronous communication between services.

#### Publishing Events

```bash
# Function: publish_event
# Parameters: event_type, event_data
publish_event() {
    local event_type="$1"
    local event_data="$2"
    
    unity_event_publish "$event_type" "$event_data"
}

# Example: Publish deployment started event
publish_event "deployment.started" '{
    "stack_name": "my-stack",
    "timestamp": "2024-01-15T10:00:00Z",
    "user": "john.doe"
}'
```

#### Subscribing to Events

```bash
# Function: subscribe_event
# Parameters: event_pattern, handler_function
subscribe_event() {
    local event_pattern="$1"
    local handler="$2"
    
    unity_event_subscribe "$event_pattern" "$handler"
}

# Example: Subscribe to all deployment events
handle_deployment_event() {
    local event_data="$1"
    echo "Handling deployment event: $event_data"
}

subscribe_event "deployment.*" "handle_deployment_event"
```

### Configuration API

Centralized configuration management with validation.

#### Loading Configuration

```bash
# Load configuration with defaults
unity_config_load() {
    local config_file="${1:-config/unity.yml}"
    local environment="${2:-development}"
    
    # Load base configuration
    unity_config_parse "$config_file"
    
    # Apply environment overrides
    unity_config_apply_env "$environment"
}

# Get configuration value
unity_config_get() {
    local key="$1"
    local default="${2:-}"
    
    unity_config_read "$key" "$default"
}
```

#### Dynamic Configuration Updates

```bash
# Watch for configuration changes
unity_config_watch() {
    local callback="$1"
    
    unity_config_monitor "$CONFIG_FILE" "$callback"
}

# Reload configuration
unity_config_reload() {
    unity_event_publish "config.reload" "{}"
}
```

## Service Development

### Creating a New Service

Use the service template to create new services:

```bash
#!/bin/bash
# Service: my-custom-service
# Description: Custom service implementation

# Source Unity core
source "${UNITY_LIB_DIR}/core/base.sh"

# Service metadata
SERVICE_NAME="my-custom-service"
SERVICE_VERSION="1.0.0"
SERVICE_DEPENDENCIES="config,events"

# Initialize service
init_service() {
    log_info "Initializing $SERVICE_NAME"
    
    # Register with service registry
    register_service "$SERVICE_NAME" "$0" "$SERVICE_DEPENDENCIES"
    
    # Subscribe to events
    subscribe_event "config.changed" "handle_config_change"
    
    return 0
}

# Service implementation
start_service() {
    log_info "Starting $SERVICE_NAME"
    
    # Service logic here
    
    return 0
}

stop_service() {
    log_info "Stopping $SERVICE_NAME"
    
    # Cleanup logic here
    
    return 0
}

# Event handlers
handle_config_change() {
    local event_data="$1"
    log_debug "Configuration changed: $event_data"
    
    # Handle configuration changes
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_service
    start_service
fi
```

### Service Communication

Services communicate through the event bus:

```bash
# Request-Response Pattern
request_aws_resource() {
    local resource_type="$1"
    local request_id=$(generate_uuid)
    
    # Subscribe to response
    subscribe_event "aws.response.$request_id" "handle_aws_response"
    
    # Send request
    publish_event "aws.request" "{
        \"id\": \"$request_id\",
        \"type\": \"$resource_type\",
        \"action\": \"create\"
    }"
    
    # Wait for response (with timeout)
    wait_for_event "aws.response.$request_id" 30
}
```

## Event System

### Event Patterns

Unity uses pattern-based event routing:

```bash
# Event naming convention: service.action.status
# Examples:
- deployment.start.initiated
- deployment.start.completed
- deployment.start.failed
- aws.ec2.instance.created
- config.reload.requested
- monitor.alert.triggered
```

### Event Handlers

Create robust event handlers:

```bash
# Idempotent event handler
handle_deployment_completed() {
    local event_data="$1"
    local stack_name=$(echo "$event_data" | jq -r '.stack_name')
    
    # Check if already processed
    if unity_cache_exists "processed.$stack_name"; then
        log_debug "Event already processed for $stack_name"
        return 0
    fi
    
    # Process event
    log_info "Processing deployment completion for $stack_name"
    
    # Update monitoring
    publish_event "monitor.deployment.register" "$event_data"
    
    # Mark as processed
    unity_cache_set "processed.$stack_name" "true" 3600
}
```

### Event Persistence

Events can be persisted for replay:

```bash
# Enable event persistence
export UNITY_EVENT_PERSISTENCE=true
export UNITY_EVENT_STORE=/var/lib/unity/events

# Replay events from timestamp
unity_event_replay --since "2024-01-15T00:00:00Z" --pattern "deployment.*"
```

## Plugin Development

### Plugin Structure

```bash
# Plugin template: plugins/my-plugin/
my-plugin/
├── plugin.yml          # Plugin metadata
├── main.sh            # Plugin entry point
├── lib/               # Plugin libraries
├── tests/             # Plugin tests
└── README.md          # Plugin documentation
```

### Plugin Metadata (plugin.yml)

```yaml
name: my-plugin
version: 1.0.0
description: Custom Unity plugin
author: Your Name
unity_version: ">=1.0.0"

dependencies:
  - aws-service
  - config-service

configuration:
  enabled:
    type: boolean
    default: true
  custom_option:
    type: string
    required: true

hooks:
  - event: deployment.started
    handler: on_deployment_started
  - event: deployment.completed
    handler: on_deployment_completed
```

### Plugin Implementation

```bash
#!/bin/bash
# Plugin: my-plugin
# Description: Custom Unity plugin

# Plugin initialization
plugin_init() {
    log_info "Initializing my-plugin"
    
    # Validate configuration
    local custom_option=$(unity_config_get "plugins.my-plugin.custom_option")
    if [[ -z "$custom_option" ]]; then
        log_error "Missing required configuration: custom_option"
        return 1
    fi
    
    # Register plugin
    unity_plugin_register "my-plugin" "$0"
    
    return 0
}

# Hook implementations
on_deployment_started() {
    local event_data="$1"
    log_info "Deployment started: $event_data"
    
    # Plugin logic here
}

on_deployment_completed() {
    local event_data="$1"
    log_info "Deployment completed: $event_data"
    
    # Plugin logic here
}

# Plugin commands
plugin_command() {
    local command="$1"
    shift
    
    case "$command" in
        status)
            plugin_status "$@"
            ;;
        custom-action)
            plugin_custom_action "$@"
            ;;
        *)
            log_error "Unknown command: $command"
            return 1
            ;;
    esac
}
```

## Testing & Debugging

### Unit Testing

```bash
#!/bin/bash
# Test file: tests/unity/test-my-service.sh

source "lib/unity/test-framework.sh"

test_service_initialization() {
    # Arrange
    local service_name="my-service"
    
    # Act
    init_service "$service_name"
    local result=$?
    
    # Assert
    assert_equals 0 "$result" "Service initialization should succeed"
    assert_service_registered "$service_name"
}

test_event_handling() {
    # Arrange
    local test_event='{"test": "data"}'
    
    # Act
    handle_test_event "$test_event"
    
    # Assert
    assert_event_published "test.response"
}

# Run tests
run_tests
```

### Integration Testing

```bash
# Integration test example
test_full_deployment_flow() {
    # Start Unity services
    ./scripts/unity-cli.sh start --test-mode
    
    # Execute deployment
    ./scripts/unity-cli.sh deploy test-stack --spot
    
    # Verify results
    assert_deployment_successful "test-stack"
    assert_events_published "deployment.*"
    
    # Cleanup
    ./scripts/unity-cli.sh destroy test-stack
}
```

### Debugging Tools

```bash
# Enable debug logging
export UNITY_DEBUG=true
export UNITY_LOG_LEVEL=debug

# Trace event flow
./scripts/unity-cli.sh events trace --pattern "deployment.*"

# Monitor service logs
./scripts/unity-cli.sh logs --service aws --follow

# Interactive debugging
./scripts/unity-cli.sh console
> unity.registry.list()
> unity.events.history(10)
> unity.config.show()
```

## Best Practices

### 1. Error Handling

```bash
# Always check return codes
if ! unity_service_call "aws" "create_instance" "$params"; then
    log_error "Failed to create instance"
    publish_event "deployment.failed" "$error_data"
    return 1
fi

# Use error recovery
with_retry 3 5 unity_aws_api_call "DescribeInstances"
```

### 2. Logging

```bash
# Use appropriate log levels
log_debug "Detailed information for debugging"
log_info "Normal operational messages"
log_warn "Warning conditions"
log_error "Error conditions"

# Include context in logs
log_info "Starting deployment" \
    "stack_name=$stack_name" \
    "region=$region" \
    "instance_type=$instance_type"
```

### 3. Performance

```bash
# Use caching for expensive operations
get_spot_prices() {
    local cache_key="spot_prices.$region.$instance_type"
    
    # Check cache first
    if unity_cache_exists "$cache_key"; then
        unity_cache_get "$cache_key"
        return 0
    fi
    
    # Fetch and cache
    local prices=$(aws ec2 describe-spot-price-history ...)
    unity_cache_set "$cache_key" "$prices" 300  # 5 minute TTL
    
    echo "$prices"
}

# Batch operations
batch_create_resources() {
    local resources=("$@")
    
    # Create in parallel
    for resource in "${resources[@]}"; do
        create_resource "$resource" &
    done
    
    # Wait for all
    wait
}
```

### 4. Security

```bash
# Never log sensitive data
log_info "Connecting to database" "host=$db_host" "user=$db_user"
# NOT: "password=$db_password"

# Use Parameter Store for secrets
get_secret() {
    local secret_name="$1"
    unity_secrets_get "$secret_name"
}

# Validate input
validate_stack_name() {
    local stack_name="$1"
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        log_error "Invalid stack name: $stack_name"
        return 1
    fi
}
```

## Code Examples

### Complete Service Example

See `/examples/unity/services/example-service.sh` for a complete service implementation.

### Plugin Examples

Browse `/examples/unity/plugins/` for plugin examples:
- `hello-world/` - Basic plugin structure
- `cost-optimizer/` - Advanced plugin with AWS integration
- `slack-notifier/` - Event-driven notification plugin

### Integration Examples

Check `/examples/unity/integrations/` for integration patterns:
- `ci-cd/` - CI/CD pipeline integration
- `monitoring/` - External monitoring integration
- `webhook/` - Webhook handler implementation

## Advanced Topics

### Custom Event Stores

Implement custom event persistence:

```bash
# Custom event store interface
custom_event_store_save() {
    local event="$1"
    # Implementation specific to your store
}

custom_event_store_query() {
    local pattern="$1"
    local since="$2"
    # Query implementation
}

# Register custom store
unity_event_store_register "custom" \
    "custom_event_store_save" \
    "custom_event_store_query"
```

### Service Mesh Integration

Unity can integrate with service mesh solutions:

```bash
# Enable service mesh support
export UNITY_SERVICE_MESH=true
export UNITY_SERVICE_MESH_PROVIDER=istio

# Automatic sidecar injection
unity_service_mesh_inject "my-service"
```

### Multi-Region Support

Deploy Unity services across regions:

```bash
# Configure multi-region
unity_config_set "regions" "us-east-1,us-west-2,eu-west-1"

# Deploy to specific region
unity_deploy --region us-west-2 my-stack

# Replicate across regions
unity_replicate my-stack --to-regions "us-west-2,eu-west-1"
```

## Resources

- **API Reference**: See API documentation for complete function reference
- **Examples**: `/examples/unity/` directory
- **Tests**: `/tests/unity/` for test examples
- **Community**: Join #unity-dev on Slack