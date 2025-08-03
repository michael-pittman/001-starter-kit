# Unity Plugin Framework Development Guide

The Unity Plugin Framework provides a comprehensive system for extending the GeuseMaker Unity architecture with custom functionality. This guide covers everything you need to know to develop, deploy, and maintain plugins.

## Table of Contents

1. [Framework Overview](#framework-overview)
2. [Plugin Architecture](#plugin-architecture)
3. [Getting Started](#getting-started)
4. [Plugin Interface](#plugin-interface)
5. [Plugin Lifecycle](#plugin-lifecycle)
6. [Extension Points](#extension-points)
7. [Configuration and Dependencies](#configuration-and-dependencies)
8. [Security and Validation](#security-and-validation)
9. [Testing and Debugging](#testing-and-debugging)
10. [Best Practices](#best-practices)
11. [API Reference](#api-reference)

## Framework Overview

The Unity Plugin Framework is designed to provide:

- **Extensibility**: Add custom functionality without modifying core code
- **Security**: Comprehensive validation and sandboxing capabilities
- **Lifecycle Management**: Full control over plugin initialization, startup, and shutdown
- **Event Integration**: Seamless integration with Unity's event-driven architecture
- **Cross-compatibility**: Works with bash 3.x+ across different platforms

### Key Components

- **Plugin Interface**: Defines contracts and specifications for plugins
- **Plugin Loader**: Discovers, validates, and loads plugins dynamically
- **Lifecycle Manager**: Manages plugin state transitions and health monitoring
- **Extension Points**: Predefined hooks throughout the Unity system
- **Validator**: Security scanning and compliance checking

## Plugin Architecture

### Plugin Types

The framework supports several plugin types:

```bash
PLUGIN_TYPE_CORE="core"               # Core system functionality
PLUGIN_TYPE_INFRASTRUCTURE="infrastructure"  # Infrastructure management
PLUGIN_TYPE_DEPLOYMENT="deployment"   # Deployment automation
PLUGIN_TYPE_MONITORING="monitoring"   # System monitoring
PLUGIN_TYPE_OPTIMIZATION="optimization"  # Performance optimization
PLUGIN_TYPE_INTEGRATION="integration"  # External integrations
PLUGIN_TYPE_EXTENSION="extension"     # General extensions
```

### Plugin Structure

Every plugin must follow this directory structure:

```
lib/unity/plugins/my-plugin/
├── plugin.sh              # Main plugin implementation (required)
├── config.yml             # Plugin configuration (optional)
├── dependencies.txt       # Plugin dependencies (optional)
└── README.md              # Plugin documentation (optional)
```

## Getting Started

### 1. Generate a Plugin Template

Use the plugin generator to create a new plugin:

```bash
# Interactive plugin generation
./lib/unity/plugins/plugin-generator.sh

# Or create manually from template
cp ./templates/unity-plugin-template.sh ./lib/unity/plugins/my-plugin/plugin.sh
```

### 2. Basic Plugin Structure

Here's a minimal plugin implementation:

```bash
#!/bin/bash
# My Custom Plugin

# Plugin metadata (required)
plugin_metadata() {
    cat <<EOF
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "My custom Unity plugin",
  "author": "Your Name",
  "type": "extension",
  "priority": 50,
  "api_version": "2.0",
  "dependencies": [],
  "config_schema": {}
}
EOF
}

# Plugin validation (required)
plugin_validate() {
    echo "Validating my-plugin..."
    return 0
}

# Plugin initialization (required)
plugin_init() {
    echo "Initializing my-plugin..."
    return 0
}

# Plugin startup (required)
plugin_start() {
    echo "Starting my-plugin..."
    return 0
}

# Plugin shutdown (required)
plugin_stop() {
    echo "Stopping my-plugin..."
    return 0
}

# Plugin cleanup (required)
plugin_cleanup() {
    echo "Cleaning up my-plugin..."
    return 0
}
```

### 3. Deploy Your Plugin

```bash
# Install plugin
./lib/unity/plugins/unity-plugin-framework.sh install ./lib/unity/plugins/my-plugin/plugin.sh

# Discover and load all plugins
./lib/unity/plugins/unity-plugin-framework.sh discover

# Check plugin status
./lib/unity/plugins/unity-plugin-framework.sh status
```

## Plugin Interface

### Required Functions

Every plugin must implement these functions:

#### `plugin_metadata()`
Returns JSON metadata about the plugin:

```bash
plugin_metadata() {
    cat <<EOF
{
  "name": "plugin-name",           # Unique plugin identifier
  "version": "1.0.0",              # Semantic version
  "description": "Plugin description",
  "author": "Author Name",
  "type": "extension",             # Plugin type
  "priority": 50,                  # Loading priority (1-100)
  "api_version": "2.0",            # Framework API version
  "dependencies": ["plugin1"],     # Plugin dependencies
  "config_schema": {               # Configuration schema
    "setting1": {"type": "string", "required": true}
  }
}
EOF
}
```

#### `plugin_validate()`
Performs plugin validation checks:

```bash
plugin_validate() {
    # Check dependencies
    command -v curl >/dev/null 2>&1 || {
        echo "ERROR: curl is required"
        return 1
    }
    
    # Validate configuration
    if [[ -z "${MY_PLUGIN_CONFIG:-}" ]]; then
        echo "WARNING: MY_PLUGIN_CONFIG not set"
    fi
    
    return 0
}
```

#### `plugin_init()`
Initializes the plugin:

```bash
plugin_init() {
    # Initialize plugin state
    mkdir -p ".unity/state/my-plugin"
    
    # Load configuration
    load_plugin_config
    
    # Set up resources
    setup_plugin_resources
    
    echo "Plugin initialized successfully"
    return 0
}
```

#### `plugin_start()`
Starts the plugin:

```bash
plugin_start() {
    # Start background processes
    start_plugin_daemon &
    echo $! > ".unity/pids/my-plugin.pid"
    
    # Register with Unity services
    register_with_unity
    
    echo "Plugin started successfully"
    return 0
}
```

#### `plugin_stop()`
Stops the plugin:

```bash
plugin_stop() {
    # Stop background processes
    if [[ -f ".unity/pids/my-plugin.pid" ]]; then
        local pid=$(cat ".unity/pids/my-plugin.pid")
        kill "$pid" 2>/dev/null || true
        rm -f ".unity/pids/my-plugin.pid"
    fi
    
    # Unregister from Unity services
    unregister_from_unity
    
    echo "Plugin stopped successfully"
    return 0
}
```

#### `plugin_cleanup()`
Cleans up plugin resources:

```bash
plugin_cleanup() {
    # Remove temporary files
    rm -rf ".unity/temp/my-plugin"
    
    # Clean up state
    rm -rf ".unity/state/my-plugin"
    
    echo "Plugin cleanup completed"
    return 0
}
```

### Optional Functions

#### `plugin_configure()`
Handles dynamic configuration changes:

```bash
plugin_configure() {
    local config_file="$1"
    
    # Reload configuration
    source "$config_file"
    
    # Apply new settings
    apply_configuration_changes
    
    return 0
}
```

#### `plugin_health_check()`
Returns plugin health status:

```bash
plugin_health_check() {
    local status="healthy"
    local message="Plugin is running normally"
    
    # Check critical resources
    if ! check_plugin_daemon; then
        status="unhealthy"
        message="Plugin daemon is not running"
    fi
    
    cat <<EOF
{
  "status": "$status",
  "message": "$message",
  "timestamp": $(date '+%s'),
  "details": {
    "daemon_running": $(check_plugin_daemon && echo true || echo false),
    "memory_usage": "$(get_memory_usage)MB"
  }
}
EOF
}
```

#### `plugin_handle_event()`
Handles Unity events:

```bash
plugin_handle_event() {
    local event_type="$1"
    local event_data="$2"
    
    case "$event_type" in
        "deployment.started")
            handle_deployment_started "$event_data"
            ;;
        "system.alert")
            handle_system_alert "$event_data"
            ;;
        *)
            # Unknown event, ignore
            ;;
    esac
    
    return 0
}
```

#### Extension Hook Functions

Plugins can implement hooks for extension points:

```bash
# Pre-deployment hook
plugin_pre_hook() {
    local extension_point="$1"
    local context_data="$2"
    
    case "$extension_point" in
        "pre_deployment")
            prepare_for_deployment "$context_data"
            ;;
    esac
    
    return 0
}

# Post-deployment hook
plugin_post_hook() {
    local extension_point="$1"
    local context_data="$2"
    
    case "$extension_point" in
        "post_deployment")
            handle_deployment_completion "$context_data"
            ;;
    esac
    
    return 0
}
```

## Plugin Lifecycle

### State Machine

Plugins follow a well-defined state machine:

```
UNLOADED → LOADING → LOADED → INITIALIZING → INITIALIZED → STARTING → ACTIVE
                                                      ↑                    ↓
                                                   STOPPED ← STOPPING ←---
```

### Lifecycle Operations

```bash
# Initialize plugin framework
init_unity_plugin_framework

# Load plugin
load_plugin "my-plugin" "/path/to/plugin.sh"

# Initialize plugin
initialize_plugin "my-plugin"

# Start plugin
start_plugin "my-plugin"

# Check plugin health
run_plugin_health_check "my-plugin"

# Stop plugin
stop_plugin "my-plugin"

# Restart plugin
restart_plugin "my-plugin"

# Unload plugin
unload_plugin "my-plugin"
```

### Batch Operations

```bash
# Start all loaded plugins
start_all_plugins

# Stop all active plugins
stop_all_plugins

# Run health checks for all plugins
run_all_plugin_health_checks
```

## Extension Points

The framework provides predefined extension points where plugins can hook into system operations:

### Available Extension Points

- `pre_deployment`: Before deployment operations start
- `post_deployment`: After deployment operations complete
- `pre_config_load`: Before configuration is loaded
- `post_config_load`: After configuration is loaded
- `pre_service_start`: Before a service starts
- `post_service_start`: After a service starts
- `pre_health_check`: Before health check is performed
- `post_health_check`: After health check is performed
- `on_error`: When an error occurs
- `on_alert`: When an alert is triggered
- `on_metric_threshold`: When a metric threshold is exceeded
- `on_cost_threshold`: When a cost threshold is exceeded
- `on_security_violation`: When a security violation is detected
- `on_performance_degradation`: When performance degradation is detected

### Registering Extension Handlers

```bash
# Register plugin for extension point
register_extension_handler "my-plugin" "pre_deployment" "handle_pre_deployment"

# Trigger extension point
trigger_extension_point "pre_deployment" '{"stack_name": "test-stack"}'

# List available extension points
list_extension_points
```

### Example Extension Handler

```bash
handle_pre_deployment() {
    local extension_point="$1"
    local context_data="$2"
    
    # Parse context data
    local stack_name=$(echo "$context_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4)
    
    # Perform pre-deployment actions
    echo "Preparing for deployment of stack: $stack_name"
    
    # Validate environment
    validate_deployment_environment "$stack_name"
    
    # Send notification
    send_deployment_notification "starting" "$stack_name"
    
    return 0
}
```

## Configuration and Dependencies

### Plugin Configuration

Create a `config.yml` file in your plugin directory:

```yaml
# Plugin configuration
settings:
  timeout: 30
  retry_count: 3
  log_level: "info"
  
# Environment-specific settings
environments:
  development:
    debug: true
    timeout: 60
  production:
    debug: false
    timeout: 10

# Dependencies
dependencies:
  system:
    - curl
    - jq
  plugins:
    - base-monitoring
```

### Loading Configuration

```bash
load_plugin_config() {
    local config_file="./lib/unity/plugins/my-plugin/config.yml"
    
    if [[ -f "$config_file" ]]; then
        # Load configuration using yq or similar
        PLUGIN_TIMEOUT=$(yq '.settings.timeout' "$config_file")
        PLUGIN_RETRY_COUNT=$(yq '.settings.retry_count' "$config_file")
    fi
}
```

### Dependency Management

```bash
plugin_validate() {
    # Check system dependencies
    local system_deps=("curl" "jq" "docker")
    for dep in "${system_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "ERROR: Missing system dependency: $dep"
            return 1
        fi
    done
    
    # Check plugin dependencies
    local plugin_deps=("base-monitoring")
    for plugin_dep in "${plugin_deps[@]}"; do
        if ! is_plugin_loaded "$plugin_dep"; then
            echo "ERROR: Missing plugin dependency: $plugin_dep"
            return 1
        fi
    done
    
    return 0
}
```

## Security and Validation

### Security Levels

The framework supports multiple validation levels:

- `basic`: Basic syntax and structure validation
- `standard`: Standard security checks (default)
- `strict`: Strict security validation
- `paranoid`: Maximum security validation

### Security Features

```bash
# Validate plugin with specific security level
validate_plugin "my-plugin" "/path/to/plugin.sh" "strict"

# Check for dangerous commands
SECURITY_DANGEROUS_COMMANDS=(
    "rm -rf /"
    "dd if="
    "mkfs"
    "curl.*|.*sh"
    "wget.*|.*sh"
)

# Quarantine suspicious plugins
quarantine_plugin "suspicious-plugin" "Contains dangerous commands"
```

### Security Best Practices

1. **Input Validation**: Always validate user inputs
2. **Privilege Separation**: Run with minimal necessary privileges  
3. **Resource Limits**: Implement timeouts and resource constraints
4. **Secure Communication**: Use encrypted channels for external communication
5. **Audit Logging**: Log all security-relevant events

## Testing and Debugging

### Plugin Testing

```bash
# Test plugin validation
test_plugin_validation() {
    local plugin_name="my-plugin"
    local plugin_path="./lib/unity/plugins/$plugin_name/plugin.sh"
    
    # Load plugin
    source "$plugin_path"
    
    # Test metadata
    local metadata
    metadata=$(plugin_metadata)
    echo "Metadata: $metadata"
    
    # Test validation
    if plugin_validate; then
        echo "Validation: PASSED"
    else
        echo "Validation: FAILED"
    fi
    
    # Test lifecycle functions
    plugin_init && echo "Init: PASSED" || echo "Init: FAILED"
}
```

### Debug Mode

```bash
# Enable verbose logging
export UNITY_PLUGIN_VERBOSE=true

# Enable debug mode
export UNITY_PLUGIN_DEBUG=true

# Run plugin with debugging
UNITY_PLUGIN_VERBOSE=true start_plugin "my-plugin"
```

### Monitoring Plugin Health

```bash
# Run health check
health_result=$(run_plugin_health_check "my-plugin")
echo "Health Check Result: $health_result"

# Monitor plugin logs
tail -f .unity/logs/plugin-lifecycle.log

# Check plugin status
get_plugin_framework_status | jq '.components.lifecycle'
```

## Best Practices

### Code Quality

1. **Error Handling**: Always check return codes and handle errors gracefully
2. **Logging**: Use structured logging with appropriate levels
3. **Documentation**: Document all functions and complex logic
4. **Testing**: Write comprehensive tests for your plugin

### Performance

1. **Resource Management**: Clean up resources properly
2. **Async Operations**: Use background processes for long-running tasks
3. **Caching**: Cache frequently accessed data
4. **Monitoring**: Monitor resource usage and performance metrics

### Security

1. **Input Sanitization**: Sanitize all external inputs
2. **Least Privilege**: Request only necessary permissions
3. **Secure Defaults**: Use secure default configurations
4. **Regular Updates**: Keep dependencies updated

### Example: Complete Plugin Implementation

```bash
#!/bin/bash
# Example: AWS Cost Monitor Plugin

# Plugin metadata
plugin_metadata() {
    cat <<EOF
{
  "name": "aws-cost-monitor",
  "version": "1.2.0",
  "description": "Monitors AWS costs and sends alerts",
  "author": "Unity Team",
  "type": "monitoring",
  "priority": 70,
  "api_version": "2.0",
  "dependencies": ["base-monitoring"],
  "config_schema": {
    "cost_threshold": {"type": "number", "required": true},
    "alert_email": {"type": "string", "required": true}
  }
}
EOF
}

# Plugin validation
plugin_validate() {
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        echo "ERROR: AWS CLI is required"
        return 1
    fi
    
    # Check credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "ERROR: AWS credentials not configured"
        return 1
    fi
    
    # Validate configuration
    if [[ -z "${AWS_COST_THRESHOLD:-}" ]]; then
        echo "ERROR: AWS_COST_THRESHOLD must be set"
        return 1
    fi
    
    return 0
}

# Plugin initialization
plugin_init() {
    # Create state directory
    mkdir -p ".unity/state/aws-cost-monitor"
    
    # Load configuration
    load_cost_monitor_config
    
    # Initialize cost tracking
    initialize_cost_tracking
    
    echo "AWS Cost Monitor initialized"
    return 0
}

# Plugin startup
plugin_start() {
    # Start cost monitoring daemon
    start_cost_monitor_daemon &
    echo $! > ".unity/pids/aws-cost-monitor.pid"
    
    # Register with Unity event system
    register_extension_handler "aws-cost-monitor" "on_cost_threshold" "handle_cost_alert"
    
    echo "AWS Cost Monitor started"
    return 0
}

# Plugin shutdown
plugin_stop() {
    # Stop monitoring daemon
    if [[ -f ".unity/pids/aws-cost-monitor.pid" ]]; then
        local pid=$(cat ".unity/pids/aws-cost-monitor.pid")
        kill "$pid" 2>/dev/null || true
        rm -f ".unity/pids/aws-cost-monitor.pid"
    fi
    
    echo "AWS Cost Monitor stopped"
    return 0
}

# Plugin cleanup
plugin_cleanup() {
    # Remove temporary files
    rm -rf ".unity/temp/aws-cost-monitor"
    
    echo "AWS Cost Monitor cleanup completed"
    return 0
}

# Health check
plugin_health_check() {
    local status="healthy"
    local message="Cost monitoring is active"
    
    # Check daemon status
    if ! check_daemon_running; then
        status="unhealthy"
        message="Cost monitoring daemon is not running"
    fi
    
    # Check AWS connectivity
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        status="unhealthy"
        message="AWS connectivity issues"
    fi
    
    cat <<EOF
{
  "status": "$status",
  "message": "$message",
  "timestamp": $(date '+%s'),
  "details": {
    "daemon_running": $(check_daemon_running && echo true || echo false),
    "aws_connected": $(aws sts get-caller-identity >/dev/null 2>&1 && echo true || echo false),
    "last_check": "$(get_last_cost_check)"
  }
}
EOF
}

# Handle cost alerts
handle_cost_alert() {
    local extension_point="$1"
    local context_data="$2"
    
    # Parse alert data
    local current_cost=$(echo "$context_data" | jq -r '.current_cost')
    local threshold=$(echo "$context_data" | jq -r '.threshold')
    
    # Send alert
    send_cost_alert "$current_cost" "$threshold"
    
    return 0
}

# Helper functions
load_cost_monitor_config() {
    AWS_COST_THRESHOLD="${AWS_COST_THRESHOLD:-100}"
    AWS_ALERT_EMAIL="${AWS_ALERT_EMAIL:-admin@example.com}"
}

start_cost_monitor_daemon() {
    while true; do
        check_aws_costs
        sleep 300  # Check every 5 minutes
    done
}

check_aws_costs() {
    local current_cost
    current_cost=$(aws ce get-cost-and-usage \
        --time-period Start=2024-01-01,End=2024-01-31 \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
        --output text)
    
    if (( $(echo "$current_cost > $AWS_COST_THRESHOLD" | bc -l) )); then
        trigger_extension_point "on_cost_threshold" "{\"current_cost\": $current_cost, \"threshold\": $AWS_COST_THRESHOLD}"
    fi
}

send_cost_alert() {
    local current_cost="$1"
    local threshold="$2"
    
    # Send email alert (implement based on your email system)
    echo "ALERT: AWS costs ($current_cost) exceed threshold ($threshold)" | \
        mail -s "AWS Cost Alert" "$AWS_ALERT_EMAIL"
}
```

## API Reference

### Core Functions

- `init_unity_plugin_framework([verbose], [validation_level])`: Initialize the plugin framework
- `discover_and_load_plugins([pattern], [validation_level])`: Discover and load plugins automatically
- `install_plugin(source, [name], [validation_level])`: Install plugin from file or URL
- `uninstall_plugin(plugin_name, [remove_files])`: Uninstall plugin

### Plugin Management

- `load_plugin(plugin_name, plugin_path)`: Load a plugin
- `unload_plugin(plugin_name)`: Unload a plugin
- `is_plugin_loaded(plugin_name)`: Check if plugin is loaded
- `get_plugin_info(plugin_name)`: Get plugin information

### Lifecycle Management

- `initialize_plugin(plugin_name, [timeout])`: Initialize plugin
- `start_plugin(plugin_name, [timeout])`: Start plugin
- `stop_plugin(plugin_name, [timeout], [force])`: Stop plugin
- `restart_plugin(plugin_name, [stop_timeout], [start_timeout])`: Restart plugin

### Health and Monitoring

- `run_plugin_health_check(plugin_name)`: Run health check for plugin
- `run_all_plugin_health_checks()`: Run health checks for all plugins
- `get_plugin_framework_status()`: Get framework status
- `run_plugin_framework_health_check()`: Run framework health check

### Extension Points

- `register_extension_handler(plugin_name, extension_point, handler_function)`: Register extension handler
- `trigger_extension_point(extension_point, context_data, [sync_mode])`: Trigger extension point
- `list_extension_points()`: List available extension points

### Validation

- `validate_plugin(plugin_name, plugin_path, [validation_level])`: Validate plugin
- `validate_all_plugins([validation_level])`: Validate all plugins
- `quarantine_plugin(plugin_name, reason)`: Quarantine plugin

This completes the Unity Plugin Framework Development Guide. The framework provides a robust, secure, and extensible plugin system that integrates seamlessly with the GeuseMaker Unity architecture.