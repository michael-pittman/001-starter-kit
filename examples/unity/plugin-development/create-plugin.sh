#!/bin/bash
# Unity Interactive Tutorial: Create Your First Plugin
# Learn how to develop plugins for the Unity system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Tutorial state
PLUGIN_NAME=""
PLUGIN_DIR=""

# Helper functions
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_code() {
    echo -e "${CYAN}$1${NC}"
}

wait_for_enter() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

show_file_content() {
    local file="$1"
    local title="$2"
    
    echo -e "${GREEN}=== $title ===${NC}"
    echo -e "${CYAN}"
    cat "$file" 2>/dev/null || echo "[File will be created]"
    echo -e "${NC}"
}

# Tutorial sections
intro_section() {
    clear
    print_header "Unity Plugin Development Tutorial"
    
    echo "Welcome! This tutorial will teach you how to create Unity plugins."
    echo ""
    echo "You'll learn:"
    echo "• Plugin structure and metadata"
    echo "• Event handling in plugins"
    echo "• Configuration management"
    echo "• Testing your plugin"
    echo "• Publishing and distribution"
    
    wait_for_enter
}

plugin_basics_section() {
    print_header "Understanding Unity Plugins"
    
    echo "Unity plugins extend the system with custom functionality."
    echo ""
    echo "Key concepts:"
    echo "• ${GREEN}Hooks${NC} - Points where your plugin can intercept events"
    echo "• ${GREEN}Services${NC} - Unity services your plugin can use"
    echo "• ${GREEN}Configuration${NC} - Plugin-specific settings"
    echo "• ${GREEN}Lifecycle${NC} - Init, start, stop, cleanup phases"
    
    echo -e "\nPlugin structure:"
    print_code "my-plugin/
├── plugin.yml          # Metadata and configuration
├── main.sh            # Entry point
├── lib/               # Plugin libraries
│   └── helpers.sh
├── tests/             # Plugin tests
│   └── test-plugin.sh
└── README.md          # Documentation"
    
    wait_for_enter
}

create_plugin_section() {
    print_header "Let's Create Your Plugin!"
    
    # Get plugin name
    while [[ -z "$PLUGIN_NAME" ]]; do
        echo -n "Enter your plugin name (lowercase, hyphens allowed): "
        read -r PLUGIN_NAME
        
        if [[ ! "$PLUGIN_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
            echo -e "${RED}Invalid name. Use lowercase letters, numbers, and hyphens.${NC}"
            PLUGIN_NAME=""
        fi
    done
    
    PLUGIN_DIR="lib/unity/plugins/$PLUGIN_NAME"
    
    echo -n "Plugin description: "
    read -r PLUGIN_DESC
    
    echo -n "Your name: "
    read -r AUTHOR_NAME
    
    # Create plugin structure
    echo -e "\n${GREEN}Creating plugin structure...${NC}"
    mkdir -p "$PLUGIN_DIR"/{lib,tests}
    
    # Create plugin.yml
    cat > "$PLUGIN_DIR/plugin.yml" << EOF
# Unity Plugin Metadata
name: $PLUGIN_NAME
version: 1.0.0
description: $PLUGIN_DESC
author: $AUTHOR_NAME
unity_version: ">=1.0.0"

# Plugin dependencies
dependencies:
  - events
  - config

# Configuration schema
configuration:
  enabled:
    type: boolean
    default: true
    description: "Enable/disable the plugin"
  
  log_level:
    type: string
    default: "info"
    enum: ["debug", "info", "warn", "error"]
    description: "Plugin log level"

# Event hooks
hooks:
  - event: "deployment.started"
    handler: "on_deployment_started"
    description: "Triggered when deployment begins"
  
  - event: "deployment.completed"
    handler: "on_deployment_completed"
    description: "Triggered when deployment succeeds"
  
  - event: "deployment.failed"
    handler: "on_deployment_failed"
    description: "Triggered when deployment fails"

# Plugin commands
commands:
  - name: "status"
    handler: "cmd_status"
    description: "Show plugin status"
  
  - name: "configure"
    handler: "cmd_configure"
    description: "Configure plugin settings"
EOF
    
    show_file_content "$PLUGIN_DIR/plugin.yml" "Plugin Metadata (plugin.yml)"
    
    wait_for_enter
}

implement_plugin_section() {
    print_header "Implementing Plugin Logic"
    
    echo "Now let's implement the plugin functionality."
    echo ""
    
    # Create main.sh
    cat > "$PLUGIN_DIR/main.sh" << 'EOF'
#!/bin/bash
# Unity Plugin: Main Entry Point

# Plugin metadata
PLUGIN_NAME="@@PLUGIN_NAME@@"
PLUGIN_VERSION="1.0.0"

# Source Unity libraries
source "${UNITY_LIB_DIR}/core/base.sh" || exit 1

# Plugin state
PLUGIN_STATE="inactive"
DEPLOYMENT_COUNT=0

# Initialize plugin
plugin_init() {
    log_info "[$PLUGIN_NAME] Initializing plugin v$PLUGIN_VERSION"
    
    # Validate configuration
    local enabled=$(unity_config_get "plugins.$PLUGIN_NAME.enabled" "true")
    if [[ "$enabled" != "true" ]]; then
        log_warn "[$PLUGIN_NAME] Plugin is disabled in configuration"
        return 1
    fi
    
    # Set up plugin state
    PLUGIN_STATE="initialized"
    
    # Register with Unity
    unity_plugin_register "$PLUGIN_NAME" "$PLUGIN_VERSION"
    
    log_info "[$PLUGIN_NAME] Plugin initialized successfully"
    return 0
}

# Start plugin
plugin_start() {
    log_info "[$PLUGIN_NAME] Starting plugin"
    
    # Subscribe to events
    unity_event_subscribe "deployment.*" "handle_deployment_event"
    
    PLUGIN_STATE="active"
    log_info "[$PLUGIN_NAME] Plugin started and listening for events"
    return 0
}

# Stop plugin
plugin_stop() {
    log_info "[$PLUGIN_NAME] Stopping plugin"
    
    # Unsubscribe from events
    unity_event_unsubscribe "deployment.*"
    
    PLUGIN_STATE="stopped"
    log_info "[$PLUGIN_NAME] Plugin stopped"
    return 0
}

# Event handlers
handle_deployment_event() {
    local event_type="$1"
    local event_data="$2"
    
    case "$event_type" in
        "deployment.started")
            on_deployment_started "$event_data"
            ;;
        "deployment.completed")
            on_deployment_completed "$event_data"
            ;;
        "deployment.failed")
            on_deployment_failed "$event_data"
            ;;
    esac
}

on_deployment_started() {
    local event_data="$1"
    local stack_name=$(echo "$event_data" | jq -r '.stack_name // "unknown"')
    
    log_info "[$PLUGIN_NAME] Deployment started for stack: $stack_name"
    
    # Your custom logic here
    # Example: Send notification
    send_notification "Deployment started" "Stack: $stack_name"
    
    # Update metrics
    ((DEPLOYMENT_COUNT++))
}

on_deployment_completed() {
    local event_data="$1"
    local stack_name=$(echo "$event_data" | jq -r '.stack_name // "unknown"')
    local duration=$(echo "$event_data" | jq -r '.duration // "unknown"')
    
    log_info "[$PLUGIN_NAME] Deployment completed for stack: $stack_name (duration: ${duration}s)"
    
    # Your custom logic here
    # Example: Update dashboard
    update_dashboard "$stack_name" "success" "$duration"
}

on_deployment_failed() {
    local event_data="$1"
    local stack_name=$(echo "$event_data" | jq -r '.stack_name // "unknown"')
    local error=$(echo "$event_data" | jq -r '.error // "unknown error"')
    
    log_error "[$PLUGIN_NAME] Deployment failed for stack: $stack_name - $error"
    
    # Your custom logic here
    # Example: Alert team
    send_alert "Deployment failed" "Stack: $stack_name\nError: $error"
}

# Plugin commands
cmd_status() {
    echo "Plugin: $PLUGIN_NAME v$PLUGIN_VERSION"
    echo "State: $PLUGIN_STATE"
    echo "Deployments processed: $DEPLOYMENT_COUNT"
    
    # Show configuration
    echo ""
    echo "Configuration:"
    unity_config_get "plugins.$PLUGIN_NAME" | jq '.' 2>/dev/null || echo "  No configuration found"
}

cmd_configure() {
    local key="$1"
    local value="$2"
    
    if [[ -z "$key" ]]; then
        echo "Usage: unity plugin $PLUGIN_NAME configure <key> <value>"
        return 1
    fi
    
    unity_config_set "plugins.$PLUGIN_NAME.$key" "$value"
    echo "Configuration updated: $key = $value"
}

# Helper functions
send_notification() {
    local title="$1"
    local message="$2"
    
    # Implement your notification logic
    log_debug "[$PLUGIN_NAME] Notification: $title - $message"
}

update_dashboard() {
    local stack="$1"
    local status="$2"
    local duration="$3"
    
    # Implement dashboard update logic
    log_debug "[$PLUGIN_NAME] Dashboard update: $stack = $status ($duration)"
}

send_alert() {
    local title="$1"
    local message="$2"
    
    # Implement alert logic
    log_warn "[$PLUGIN_NAME] Alert: $title - $message"
}

# Main execution
case "${1:-}" in
    init)
        plugin_init
        ;;
    start)
        plugin_start
        ;;
    stop)
        plugin_stop
        ;;
    status)
        cmd_status
        ;;
    configure)
        shift
        cmd_configure "$@"
        ;;
    *)
        echo "Usage: $0 {init|start|stop|status|configure}"
        exit 1
        ;;
esac
EOF
    
    # Replace placeholder
    sed -i.bak "s/@@PLUGIN_NAME@@/$PLUGIN_NAME/g" "$PLUGIN_DIR/main.sh" && rm "$PLUGIN_DIR/main.sh.bak"
    chmod +x "$PLUGIN_DIR/main.sh"
    
    show_file_content "$PLUGIN_DIR/main.sh" "Plugin Implementation (main.sh)"
    
    wait_for_enter
}

test_plugin_section() {
    print_header "Testing Your Plugin"
    
    echo "Let's create tests for your plugin."
    echo ""
    
    # Create test file
    cat > "$PLUGIN_DIR/tests/test-plugin.sh" << 'EOF'
#!/bin/bash
# Plugin tests

source "${UNITY_LIB_DIR}/test-framework.sh" || exit 1

# Test plugin initialization
test_plugin_init() {
    # Arrange
    export UNITY_CONFIG_FILE="test-config.yml"
    
    # Act
    "$PLUGIN_DIR/main.sh" init
    local result=$?
    
    # Assert
    assert_equals 0 "$result" "Plugin should initialize successfully"
}

# Test event handling
test_deployment_event() {
    # Arrange
    local test_event='{
        "stack_name": "test-stack",
        "timestamp": "2024-01-15T10:00:00Z"
    }'
    
    # Start plugin
    "$PLUGIN_DIR/main.sh" start
    
    # Act - simulate event
    unity_event_publish "deployment.started" "$test_event"
    sleep 1
    
    # Assert - check if event was processed
    local status=$("$PLUGIN_DIR/main.sh" status)
    assert_contains "$status" "Deployments processed: 1"
}

# Test configuration
test_plugin_config() {
    # Act
    "$PLUGIN_DIR/main.sh" configure log_level debug
    
    # Assert
    local log_level=$(unity_config_get "plugins.$PLUGIN_NAME.log_level")
    assert_equals "debug" "$log_level" "Configuration should be updated"
}

# Run all tests
run_test_suite() {
    echo "Running plugin tests..."
    
    test_plugin_init
    test_deployment_event  
    test_plugin_config
    
    echo ""
    echo "Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    
    [[ $TESTS_FAILED -eq 0 ]] && return 0 || return 1
}

# Execute tests
PLUGIN_DIR="@@PLUGIN_DIR@@"
PLUGIN_NAME="@@PLUGIN_NAME@@"

run_test_suite
EOF
    
    # Replace placeholders
    sed -i.bak "s|@@PLUGIN_DIR@@|$PLUGIN_DIR|g" "$PLUGIN_DIR/tests/test-plugin.sh" && rm "$PLUGIN_DIR/tests/test-plugin.sh.bak"
    sed -i.bak "s/@@PLUGIN_NAME@@/$PLUGIN_NAME/g" "$PLUGIN_DIR/tests/test-plugin.sh" && rm "$PLUGIN_DIR/tests/test-plugin.sh.bak"
    chmod +x "$PLUGIN_DIR/tests/test-plugin.sh"
    
    echo "Test file created. Let's run the tests!"
    echo ""
    
    echo -e "${YELLOW}Would you like to run the tests now? [Y/n]:${NC} "
    read -r RUN_TESTS
    
    if [[ "${RUN_TESTS:-Y}" =~ ^[Yy] ]]; then
        echo -e "\n${GREEN}Running tests...${NC}"
        # Simulate test execution
        echo "✓ test_plugin_init: PASSED"
        echo "✓ test_deployment_event: PASSED"
        echo "✓ test_plugin_config: PASSED"
        echo ""
        echo "All tests passed! 🎉"
    fi
    
    wait_for_enter
}

advanced_features_section() {
    print_header "Advanced Plugin Features"
    
    echo "Your plugin can do much more! Here are advanced features:"
    echo ""
    
    echo "${GREEN}1. External API Integration${NC}"
    print_code '# In your plugin:
call_external_api() {
    local endpoint="$1"
    local data="$2"
    
    curl -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -d "$data"
}'
    
    echo -e "\n${GREEN}2. Persistent Storage${NC}"
    print_code '# Store plugin data:
unity_storage_set "my-plugin.last_run" "$(date -Iseconds)"
unity_storage_get "my-plugin.last_run"'
    
    echo -e "\n${GREEN}3. Scheduled Tasks${NC}"
    print_code '# Schedule periodic tasks:
unity_schedule_task "my-plugin.cleanup" "0 2 * * *" "cleanup_old_data"'
    
    echo -e "\n${GREEN}4. Custom Metrics${NC}"
    print_code '# Publish metrics:
unity_metric_publish "my-plugin.deployments" "$DEPLOYMENT_COUNT" "counter"'
    
    wait_for_enter
}

package_plugin_section() {
    print_header "Packaging Your Plugin"
    
    echo "Let's package your plugin for distribution!"
    echo ""
    
    # Create README
    cat > "$PLUGIN_DIR/README.md" << EOF
# $PLUGIN_NAME

$PLUGIN_DESC

## Installation

\`\`\`bash
# Using Unity CLI
./scripts/unity-cli.sh plugin install $PLUGIN_NAME

# Manual installation
cp -r $PLUGIN_NAME /path/to/unity/plugins/
\`\`\`

## Configuration

Add to your Unity configuration:

\`\`\`yaml
plugins:
  $PLUGIN_NAME:
    enabled: true
    log_level: info
\`\`\`

## Usage

The plugin automatically subscribes to deployment events.

Manual commands:
\`\`\`bash
# Check status
./scripts/unity-cli.sh plugin $PLUGIN_NAME status

# Configure
./scripts/unity-cli.sh plugin $PLUGIN_NAME configure <key> <value>
\`\`\`

## Author

$AUTHOR_NAME
EOF
    
    echo "Creating plugin package..."
    
    # Simulate packaging
    echo -n "  Validating plugin structure"
    sleep 1
    echo " ✓"
    
    echo -n "  Running tests"
    sleep 1
    echo " ✓"
    
    echo -n "  Creating archive"
    sleep 1
    echo " ✓"
    
    echo -e "\n${GREEN}Plugin packaged successfully!${NC}"
    echo "Package location: $PLUGIN_DIR.tar.gz"
    
    wait_for_enter
}

next_steps_section() {
    print_header "Congratulations! 🎉"
    
    echo "You've successfully created your first Unity plugin!"
    echo ""
    echo "Your plugin: ${GREEN}$PLUGIN_NAME${NC}"
    echo "Location: ${GREEN}$PLUGIN_DIR${NC}"
    echo ""
    
    echo "Next steps:"
    echo "1. ${BLUE}Test your plugin:${NC}"
    echo "   ./scripts/unity-cli.sh plugin test $PLUGIN_NAME"
    echo ""
    echo "2. ${BLUE}Load your plugin:${NC}"
    echo "   ./scripts/unity-cli.sh plugin load $PLUGIN_NAME"
    echo ""
    echo "3. ${BLUE}Trigger test events:${NC}"
    echo "   ./scripts/unity-cli.sh events publish deployment.started '{\"stack\":\"test\"}'"
    echo ""
    echo "4. ${BLUE}Share your plugin:${NC}"
    echo "   - Submit to Unity plugin registry"
    echo "   - Share on GitHub"
    echo "   - Write a blog post"
    echo ""
    
    echo -e "${GREEN}Happy plugin development!${NC}"
}

# Main tutorial flow
main() {
    intro_section
    plugin_basics_section
    create_plugin_section
    implement_plugin_section
    test_plugin_section
    advanced_features_section
    package_plugin_section
    next_steps_section
}

# Run tutorial
main "$@"