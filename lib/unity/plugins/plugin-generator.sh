#!/bin/bash
# =============================================================================
# Unity Plugin Generator
# Interactive tool for generating customized plugins from templates
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# =============================================================================
# PLUGIN GENERATOR CONSTANTS
# =============================================================================

readonly UNITY_PLUGIN_GENERATOR_VERSION="1.0.0"
readonly PLUGIN_TEMPLATE_FILE="$PROJECT_ROOT/templates/unity-plugin-template.sh"
readonly PLUGIN_OUTPUT_DIR="$PROJECT_ROOT/lib/unity/plugins"

# Plugin types and categories
PLUGIN_TYPES=("core" "infrastructure" "deployment" "monitoring" "optimization" "integration" "extension")
PLUGIN_CATEGORIES=("cost-optimization" "security" "performance" "deployment" "monitoring" "integration" "utility")

# Default values
DEFAULT_PLUGIN_TYPE="extension"
DEFAULT_PLUGIN_CATEGORY="optimization"
DEFAULT_PLUGIN_PRIORITY="50"
DEFAULT_PLUGIN_AUTHOR="Plugin Developer"
DEFAULT_PLUGIN_LICENSE="MIT"
DEFAULT_MAX_MEMORY="50"
DEFAULT_MAX_CPU="10"
DEFAULT_MAX_DISK="100"

# =============================================================================
# PLUGIN GENERATOR FUNCTIONS
# =============================================================================

# Generate plugin interactively
# Usage: generate_plugin_interactive
generate_plugin_interactive() {
    echo "Unity Plugin Generator v$UNITY_PLUGIN_GENERATOR_VERSION"
    echo "Interactive plugin creation wizard"
    echo "========================================"
    echo ""
    
    # Check if template exists
    if [[ ! -f "$PLUGIN_TEMPLATE_FILE" ]]; then
        echo "ERROR: Plugin template not found: $PLUGIN_TEMPLATE_FILE" >&2
        return 1
    fi
    
    # Collect plugin information
    local plugin_config
    plugin_config=$(cat <<'EOF'
{
  "name": "",
  "description": "",
  "author": "",
  "homepage": "",
  "type": "",
  "category": "",
  "priority": "",
  "license": "",
  "required_deps": [],
  "optional_deps": [],
  "unity_services": [],
  "system_commands": [],
  "extension_points": [],
  "event_handlers": [],
  "has_config": true,
  "has_metrics": true,
  "has_health": true,
  "required_config": [],
  "optional_config": [],
  "max_memory": "",
  "max_cpu": "",
  "max_disk": "",
  "network_access": true,
  "file_permissions": [],
  "sandbox_mode": true,
  "allowed_commands": [],
  "restricted_paths": [],
  "env_isolation": true
}
EOF
)
    
    # Interactive prompts
    plugin_config=$(_prompt_basic_info "$plugin_config")
    plugin_config=$(_prompt_dependencies "$plugin_config")
    plugin_config=$(_prompt_capabilities "$plugin_config")
    plugin_config=$(_prompt_configuration "$plugin_config")
    plugin_config=$(_prompt_resources "$plugin_config")
    plugin_config=$(_prompt_security "$plugin_config")
    
    # Show summary and confirm
    echo ""
    echo "Plugin Configuration Summary:"
    echo "==============================="
    _show_plugin_summary "$plugin_config"
    echo ""
    
    if _confirm "Generate plugin with this configuration?"; then
        local plugin_name
        plugin_name=$(echo "$plugin_config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
        
        if generate_plugin_from_config "$plugin_name" "$plugin_config"; then
            echo ""
            echo "Plugin generated successfully!"
            echo "Plugin location: $PLUGIN_OUTPUT_DIR/$plugin_name/"
            echo ""
            echo "Next steps:"
            echo "1. Review and customize the generated plugin code"
            echo "2. Implement your specific functionality"
            echo "3. Test the plugin thoroughly"
            echo "4. Register and load the plugin"
            echo ""
            echo "To load the plugin:"
            echo "  ./lib/unity/plugins/unity-plugin-framework.sh discover"
            echo "  # or"
            echo "  ./lib/unity/plugins/unity-plugin-framework.sh install $PLUGIN_OUTPUT_DIR/$plugin_name/plugin.sh"
        else
            echo "ERROR: Failed to generate plugin" >&2
            return 1
        fi
    else
        echo "Plugin generation cancelled."
        return 0
    fi
}

# Generate plugin from configuration file
# Usage: generate_plugin_from_file config_file
generate_plugin_from_file() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    local plugin_config
    plugin_config=$(cat "$config_file")
    
    local plugin_name
    plugin_name=$(echo "$plugin_config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$plugin_name" ]]; then
        echo "ERROR: Plugin name not found in configuration" >&2
        return 1
    fi
    
    generate_plugin_from_config "$plugin_name" "$plugin_config"
}

# Generate plugin from configuration object
# Usage: generate_plugin_from_config plugin_name config_json
generate_plugin_from_config() {
    local plugin_name="$1"
    local plugin_config="$2"
    
    echo "Generating plugin: $plugin_name"
    
    # Validate plugin name
    if [[ ! "$plugin_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        echo "ERROR: Invalid plugin name. Use alphanumeric characters, hyphens, and underscores only." >&2
        return 1
    fi
    
    # Create plugin directory
    local plugin_dir="$PLUGIN_OUTPUT_DIR/$plugin_name"
    if [[ -d "$plugin_dir" ]]; then
        if ! _confirm "Plugin directory already exists. Overwrite?"; then
            echo "Plugin generation cancelled."
            return 0
        fi
        rm -rf "$plugin_dir"
    fi
    
    mkdir -p "$plugin_dir"
    
    # Generate plugin file
    local plugin_file="$plugin_dir/plugin.sh"
    if ! _generate_plugin_from_template "$plugin_config" > "$plugin_file"; then
        echo "ERROR: Failed to generate plugin from template" >&2
        rm -rf "$plugin_dir"
        return 1
    fi
    
    # Make plugin executable
    chmod +x "$plugin_file"
    
    # Generate additional files
    _generate_plugin_readme "$plugin_config" > "$plugin_dir/README.md"
    _generate_plugin_config "$plugin_config" > "$plugin_dir/config.yml"
    _generate_plugin_example "$plugin_config" > "$plugin_dir/example.sh"
    
    echo "Plugin files generated:"
    echo "  - $plugin_file (main plugin script)"
    echo "  - $plugin_dir/README.md (documentation)"
    echo "  - $plugin_dir/config.yml (configuration template)"
    echo "  - $plugin_dir/example.sh (usage example)"
    
    return 0
}

# =============================================================================
# INTERACTIVE PROMPTS
# =============================================================================

# Prompt for basic plugin information
# Usage: _prompt_basic_info config_json
_prompt_basic_info() {
    local config="$1"
    
    echo "Basic Plugin Information"
    echo "========================"
    
    # Plugin name
    local plugin_name
    while true; do
        read -p "Plugin name (alphanumeric, hyphens, underscores): " plugin_name
        if [[ -n "$plugin_name" ]] && [[ "$plugin_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            break
        else
            echo "Invalid plugin name. Use alphanumeric characters, hyphens, and underscores only."
        fi
    done
    config=$(echo "$config" | sed "s/\"name\": \"\"/\"name\": \"$plugin_name\"/")
    
    # Plugin description
    local description
    read -p "Plugin description: " description
    config=$(echo "$config" | sed "s/\"description\": \"\"/\"description\": \"$description\"/")
    
    # Plugin author
    local author
    read -p "Author [$DEFAULT_PLUGIN_AUTHOR]: " author
    author="${author:-$DEFAULT_PLUGIN_AUTHOR}"
    config=$(echo "$config" | sed "s/\"author\": \"\"/\"author\": \"$author\"/")
    
    # Plugin homepage
    local homepage
    read -p "Homepage (optional): " homepage
    config=$(echo "$config" | sed "s/\"homepage\": \"\"/\"homepage\": \"$homepage\"/")
    
    # Plugin type
    echo ""
    echo "Available plugin types:"
    for i in "${!PLUGIN_TYPES[@]}"; do
        echo "  $((i+1)). ${PLUGIN_TYPES[i]}"
    done
    
    local type_choice
    while true; do
        read -p "Select plugin type [1-${#PLUGIN_TYPES[@]}] (default: extension): " type_choice
        if [[ -z "$type_choice" ]]; then
            type_choice="$DEFAULT_PLUGIN_TYPE"
            break
        elif [[ "$type_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$type_choice" -le "${#PLUGIN_TYPES[@]}" ]]; then
            type_choice="${PLUGIN_TYPES[$((type_choice-1))]}"
            break
        else
            echo "Invalid choice. Please select 1-${#PLUGIN_TYPES[@]}."
        fi
    done
    config=$(echo "$config" | sed "s/\"type\": \"\"/\"type\": \"$type_choice\"/")
    
    # Plugin category
    echo ""
    echo "Available plugin categories:"
    for i in "${!PLUGIN_CATEGORIES[@]}"; do
        echo "  $((i+1)). ${PLUGIN_CATEGORIES[i]}"
    done
    
    local category_choice
    while true; do
        read -p "Select plugin category [1-${#PLUGIN_CATEGORIES[@]}] (default: optimization): " category_choice
        if [[ -z "$category_choice" ]]; then
            category_choice="$DEFAULT_PLUGIN_CATEGORY"
            break
        elif [[ "$category_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$category_choice" -le "${#PLUGIN_CATEGORIES[@]}" ]]; then
            category_choice="${PLUGIN_CATEGORIES[$((category_choice-1))]}"
            break
        else
            echo "Invalid choice. Please select 1-${#PLUGIN_CATEGORIES[@]}."
        fi
    done
    config=$(echo "$config" | sed "s/\"category\": \"\"/\"category\": \"$category_choice\"/")
    
    # Plugin priority
    local priority
    read -p "Plugin priority (1-100, higher loads first) [$DEFAULT_PLUGIN_PRIORITY]: " priority
    priority="${priority:-$DEFAULT_PLUGIN_PRIORITY}"
    config=$(echo "$config" | sed "s/\"priority\": \"\"/\"priority\": \"$priority\"/")
    
    # Plugin license
    local license
    read -p "License [$DEFAULT_PLUGIN_LICENSE]: " license
    license="${license:-$DEFAULT_PLUGIN_LICENSE}"
    config=$(echo "$config" | sed "s/\"license\": \"\"/\"license\": \"$license\"/")
    
    echo "$config"
}

# Prompt for plugin dependencies
# Usage: _prompt_dependencies config_json
_prompt_dependencies() {
    local config="$1"
    
    echo ""
    echo "Plugin Dependencies"
    echo "==================="
    
    # Required dependencies
    local required_deps=()
    echo "Required dependencies (command names, press Enter when done):"
    while true; do
        read -p "Required dependency (or Enter to finish): " dep
        if [[ -z "$dep" ]]; then
            break
        else
            required_deps+=("\"$dep\"")
        fi
    done
    
    if [[ ${#required_deps[@]} -gt 0 ]]; then
        local required_deps_json="[$(IFS=,; echo "${required_deps[*]}")]"
        config=$(echo "$config" | sed "s/\"required_deps\": \[\]/\"required_deps\": $required_deps_json/")
    fi
    
    # Optional dependencies
    local optional_deps=()
    echo ""
    echo "Optional dependencies (press Enter when done):"
    while true; do
        read -p "Optional dependency (or Enter to finish): " dep
        if [[ -z "$dep" ]]; then
            break
        else
            optional_deps+=("\"$dep\"")
        fi
    done
    
    if [[ ${#optional_deps[@]} -gt 0 ]]; then
        local optional_deps_json="[$(IFS=,; echo "${optional_deps[*]}")]"
        config=$(echo "$config" | sed "s/\"optional_deps\": \[\]/\"optional_deps\": $optional_deps_json/")
    fi
    
    # Unity services
    local unity_services=()
    echo ""
    echo "Unity services this plugin depends on (config, events, aws, docker, monitor):"
    echo "Common services: config, events, aws, docker, monitor"
    while true; do
        read -p "Unity service (or Enter to finish): " service
        if [[ -z "$service" ]]; then
            break
        else
            unity_services+=("\"$service\"")
        fi
    done
    
    if [[ ${#unity_services[@]} -gt 0 ]]; then
        local unity_services_json="[$(IFS=,; echo "${unity_services[*]}")]"
        config=$(echo "$config" | sed "s/\"unity_services\": \[\]/\"unity_services\": $unity_services_json/")
    fi
    
    # System commands
    local system_commands=()
    echo ""
    echo "System commands this plugin uses:"
    while true; do
        read -p "System command (or Enter to finish): " cmd
        if [[ -z "$cmd" ]]; then
            break
        else
            system_commands+=("\"$cmd\"")
        fi
    done
    
    if [[ ${#system_commands[@]} -gt 0 ]]; then
        local system_commands_json="[$(IFS=,; echo "${system_commands[*]}")]"
        config=$(echo "$config" | sed "s/\"system_commands\": \[\]/\"system_commands\": $system_commands_json/")
    fi
    
    echo "$config"
}

# Prompt for plugin capabilities
# Usage: _prompt_capabilities config_json
_prompt_capabilities() {
    local config="$1"
    
    echo ""
    echo "Plugin Capabilities"
    echo "==================="
    
    # Extension points
    local extension_points=()
    echo "Extension points this plugin hooks into:"
    echo "Available: pre_deployment, post_deployment, pre_config_load, post_config_load,"
    echo "          pre_service_start, post_service_start, pre_health_check, post_health_check,"
    echo "          on_error, on_alert, on_metric_threshold, on_cost_threshold"
    while true; do
        read -p "Extension point (or Enter to finish): " point
        if [[ -z "$point" ]]; then
            break
        else
            extension_points+=("\"$point\"")
        fi
    done
    
    if [[ ${#extension_points[@]} -gt 0 ]]; then
        local extension_points_json="[$(IFS=,; echo "${extension_points[*]}")]"
        config=$(echo "$config" | sed "s/\"extension_points\": \[\]/\"extension_points\": $extension_points_json/")
    fi
    
    # Event handlers
    local event_handlers=()
    echo ""
    echo "Events this plugin handles:"
    echo "Available: deployment.started, deployment.completed, deployment.failed,"
    echo "          aws.resource.created, config.updated, monitor.alert.triggered"
    while true; do
        read -p "Event type (or Enter to finish): " event
        if [[ -z "$event" ]]; then
            break
        else
            event_handlers+=("\"$event\"")
        fi
    done
    
    if [[ ${#event_handlers[@]} -gt 0 ]]; then
        local event_handlers_json="[$(IFS=,; echo "${event_handlers[*]}")]"
        config=$(echo "$config" | sed "s/\"event_handlers\": \[\]/\"event_handlers\": $event_handlers_json/")
    fi
    
    # Capabilities
    echo ""
    if _confirm "Does this plugin have configuration options?"; then
        config=$(echo "$config" | sed "s/\"has_config\": true/\"has_config\": true/")
    else
        config=$(echo "$config" | sed "s/\"has_config\": true/\"has_config\": false/")
    fi
    
    if _confirm "Does this plugin collect metrics?"; then
        config=$(echo "$config" | sed "s/\"has_metrics\": true/\"has_metrics\": true/")
    else
        config=$(echo "$config" | sed "s/\"has_metrics\": true/\"has_metrics\": false/")
    fi
    
    if _confirm "Does this plugin have health monitoring?"; then
        config=$(echo "$config" | sed "s/\"has_health\": true/\"has_health\": true/")
    else
        config=$(echo "$config" | sed "s/\"has_health\": true/\"has_health\": false/")
    fi
    
    echo "$config"
}

# Prompt for plugin configuration
# Usage: _prompt_configuration config_json
_prompt_configuration() {
    local config="$1"
    
    echo ""
    echo "Plugin Configuration"
    echo "===================="
    
    # Required configuration
    local required_config=()
    echo "Required configuration parameters:"
    while true; do
        read -p "Required config parameter (or Enter to finish): " param
        if [[ -z "$param" ]]; then
            break
        else
            required_config+=("\"$param\"")
        fi
    done
    
    if [[ ${#required_config[@]} -gt 0 ]]; then
        local required_config_json="[$(IFS=,; echo "${required_config[*]}")]"
        config=$(echo "$config" | sed "s/\"required_config\": \[\]/\"required_config\": $required_config_json/")
    fi
    
    # Optional configuration
    local optional_config=()
    echo ""
    echo "Optional configuration parameters:"
    while true; do
        read -p "Optional config parameter (or Enter to finish): " param
        if [[ -z "$param" ]]; then
            break
        else
            optional_config+=("\"$param\"")
        fi
    done
    
    if [[ ${#optional_config[@]} -gt 0 ]]; then
        local optional_config_json="[$(IFS=,; echo "${optional_config[*]}")]"
        config=$(echo "$config" | sed "s/\"optional_config\": \[\]/\"optional_config\": $optional_config_json/")
    fi
    
    echo "$config"
}

# Prompt for resource limits
# Usage: _prompt_resources config_json
_prompt_resources() {
    local config="$1"
    
    echo ""
    echo "Resource Limits"
    echo "==============="
    
    # Memory limit
    local max_memory
    read -p "Maximum memory usage (MB) [$DEFAULT_MAX_MEMORY]: " max_memory
    max_memory="${max_memory:-$DEFAULT_MAX_MEMORY}"
    config=$(echo "$config" | sed "s/\"max_memory\": \"\"/\"max_memory\": \"$max_memory\"/")
    
    # CPU limit
    local max_cpu
    read -p "Maximum CPU usage (%) [$DEFAULT_MAX_CPU]: " max_cpu
    max_cpu="${max_cpu:-$DEFAULT_MAX_CPU}"
    config=$(echo "$config" | sed "s/\"max_cpu\": \"\"/\"max_cpu\": \"$max_cpu\"/")
    
    # Disk limit
    local max_disk
    read -p "Maximum disk usage (MB) [$DEFAULT_MAX_DISK]: " max_disk
    max_disk="${max_disk:-$DEFAULT_MAX_DISK}"
    config=$(echo "$config" | sed "s/\"max_disk\": \"\"/\"max_disk\": \"$max_disk\"/")
    
    # Network access
    echo ""
    if _confirm "Does this plugin need network access?"; then
        config=$(echo "$config" | sed "s/\"network_access\": true/\"network_access\": true/")
    else
        config=$(echo "$config" | sed "s/\"network_access\": true/\"network_access\": false/")
    fi
    
    # File permissions
    local file_permissions=()
    echo ""
    echo "File permissions needed (e.g., 'read', 'write:tmp', 'write:/var/log'):"
    while true; do
        read -p "File permission (or Enter to finish): " perm
        if [[ -z "$perm" ]]; then
            break
        else
            file_permissions+=("\"$perm\"")
        fi
    done
    
    if [[ ${#file_permissions[@]} -gt 0 ]]; then
        local file_permissions_json="[$(IFS=,; echo "${file_permissions[*]}")]"
        config=$(echo "$config" | sed "s/\"file_permissions\": \[\]/\"file_permissions\": $file_permissions_json/")
    fi
    
    echo "$config"
}

# Prompt for security settings
# Usage: _prompt_security config_json
_prompt_security() {
    local config="$1"
    
    echo ""
    echo "Security Settings"
    echo "================="
    
    # Sandbox mode
    if _confirm "Enable sandbox mode?"; then
        config=$(echo "$config" | sed "s/\"sandbox_mode\": true/\"sandbox_mode\": true/")
    else
        config=$(echo "$config" | sed "s/\"sandbox_mode\": true/\"sandbox_mode\": false/")
    fi
    
    # Allowed commands
    local allowed_commands=()
    echo ""
    echo "Commands this plugin is allowed to execute:"
    while true; do
        read -p "Allowed command (or Enter to finish): " cmd
        if [[ -z "$cmd" ]]; then
            break
        else
            allowed_commands+=("\"$cmd\"")
        fi
    done
    
    if [[ ${#allowed_commands[@]} -gt 0 ]]; then
        local allowed_commands_json="[$(IFS=,; echo "${allowed_commands[*]}")]"
        config=$(echo "$config" | sed "s/\"allowed_commands\": \[\]/\"allowed_commands\": $allowed_commands_json/")
    fi
    
    # Restricted paths
    local restricted_paths=()
    echo ""
    echo "Paths this plugin should NOT access:"
    while true; do
        read -p "Restricted path (or Enter to finish): " path
        if [[ -z "$path" ]]; then
            break
        else
            restricted_paths+=("\"$path\"")
        fi
    done
    
    if [[ ${#restricted_paths[@]} -gt 0 ]]; then
        local restricted_paths_json="[$(IFS=,; echo "${restricted_paths[*]}")]"
        config=$(echo "$config" | sed "s/\"restricted_paths\": \[\]/\"restricted_paths\": $restricted_paths_json/")
    fi
    
    # Environment isolation
    echo ""
    if _confirm "Enable environment isolation?"; then
        config=$(echo "$config" | sed "s/\"env_isolation\": true/\"env_isolation\": true/")
    else
        config=$(echo "$config" | sed "s/\"env_isolation\": true/\"env_isolation\": false/")
    fi
    
    echo "$config"
}

# =============================================================================
# PLUGIN GENERATION FROM TEMPLATE
# =============================================================================

# Generate plugin from template
# Usage: _generate_plugin_from_template config_json
_generate_plugin_from_template() {
    local config="$1"
    
    # Extract values from config
    local plugin_name=$(echo "$config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    local plugin_description=$(echo "$config" | grep -o '"description": "[^"]*"' | cut -d'"' -f4)
    local plugin_author=$(echo "$config" | grep -o '"author": "[^"]*"' | cut -d'"' -f4)
    local plugin_homepage=$(echo "$config" | grep -o '"homepage": "[^"]*"' | cut -d'"' -f4)
    local plugin_type=$(echo "$config" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    local plugin_category=$(echo "$config" | grep -o '"category": "[^"]*"' | cut -d'"' -f4)
    local plugin_priority=$(echo "$config" | grep -o '"priority": "[^"]*"' | cut -d'"' -f4)
    local plugin_license=$(echo "$config" | grep -o '"license": "[^"]*"' | cut -d'"' -f4)
    
    # Convert plugin name to uppercase for environment variables
    local plugin_name_upper=$(echo "$plugin_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    
    # Extract arrays (simplified extraction)
    local required_deps=$(echo "$config" | grep -o '"required_deps": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local optional_deps=$(echo "$config" | grep -o '"optional_deps": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local unity_services=$(echo "$config" | grep -o '"unity_services": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local system_commands=$(echo "$config" | grep -o '"system_commands": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local extension_points=$(echo "$config" | grep -o '"extension_points": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local event_handlers=$(echo "$config" | grep -o '"event_handlers": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local required_config=$(echo "$config" | grep -o '"required_config": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local optional_config=$(echo "$config" | grep -o '"optional_config": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local file_permissions=$(echo "$config" | grep -o '"file_permissions": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local allowed_commands=$(echo "$config" | grep -o '"allowed_commands": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local restricted_paths=$(echo "$config" | grep -o '"restricted_paths": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    
    # Extract resource limits
    local max_memory=$(echo "$config" | grep -o '"max_memory": "[^"]*"' | cut -d'"' -f4)
    local max_cpu=$(echo "$config" | grep -o '"max_cpu": "[^"]*"' | cut -d'"' -f4)
    local max_disk=$(echo "$config" | grep -o '"max_disk": "[^"]*"' | cut -d'"' -f4)
    
    # Extract boolean values
    local has_config=$(echo "$config" | grep -o '"has_config": [a-z]*' | cut -d':' -f2 | tr -d ' ')
    local has_metrics=$(echo "$config" | grep -o '"has_metrics": [a-z]*' | cut -d':' -f2 | tr -d ' ')
    local has_health=$(echo "$config" | grep -o '"has_health": [a-z]*' | cut -d':' -f2 | tr -d ' ')
    local network_access=$(echo "$config" | grep -o '"network_access": [a-z]*' | cut -d':' -f2 | tr -d ' ')
    local sandbox_mode=$(echo "$config" | grep -o '"sandbox_mode": [a-z]*' | cut -d':' -f2 | tr -d ' ')
    local env_isolation=$(echo "$config" | grep -o '"env_isolation": [a-z]*' | cut -d':' -f2 | tr -d ' ')
    
    # Convert arrays to bash format for validation functions
    local required_deps_bash=""
    if [[ -n "$required_deps" ]]; then
        required_deps_bash=$(echo "$required_deps" | tr ',' ' ' | tr -d '"')
    fi
    
    local required_config_bash=""
    if [[ -n "$required_config" ]]; then
        required_config_bash=$(echo "$required_config" | tr ',' ' ' | tr -d '"')
    fi
    
    # Read template and perform substitutions
    local template_content
    template_content=$(cat "$PLUGIN_TEMPLATE_FILE")
    
    # Perform all substitutions
    template_content="${template_content//\{\{PLUGIN_NAME\}\}/$plugin_name}"
    template_content="${template_content//\{\{PLUGIN_DESCRIPTION\}\}/$plugin_description}"
    template_content="${template_content//\{\{PLUGIN_AUTHOR\}\}/$plugin_author}"
    template_content="${template_content//\{\{PLUGIN_HOMEPAGE\}\}/$plugin_homepage}"
    template_content="${template_content//\{\{PLUGIN_TYPE\}\}/$plugin_type}"
    template_content="${template_content//\{\{PLUGIN_CATEGORY\}\}/$plugin_category}"
    template_content="${template_content//\{\{PLUGIN_PRIORITY\}\}/$plugin_priority}"
    template_content="${template_content//\{\{PLUGIN_NAME_UPPER\}\}/$plugin_name_upper}"
    template_content="${template_content//\{\{PLUGIN_REQUIRED_DEPS\}\}/[$required_deps]}"
    template_content="${template_content//\{\{PLUGIN_OPTIONAL_DEPS\}\}/[$optional_deps]}"
    template_content="${template_content//\{\{PLUGIN_UNITY_SERVICES\}\}/[$unity_services]}"
    template_content="${template_content//\{\{PLUGIN_SYSTEM_COMMANDS\}\}/[$system_commands]}"
    template_content="${template_content//\{\{PLUGIN_EXTENSION_POINTS\}\}/[$extension_points]}"
    template_content="${template_content//\{\{PLUGIN_EVENT_HANDLERS\}\}/[$event_handlers]}"
    template_content="${template_content//\{\{PLUGIN_HAS_CONFIG\}\}/$has_config}"
    template_content="${template_content//\{\{PLUGIN_HAS_METRICS\}\}/$has_metrics}"
    template_content="${template_content//\{\{PLUGIN_HAS_HEALTH\}\}/$has_health}"
    template_content="${template_content//\{\{PLUGIN_REQUIRED_CONFIG\}\}/[$required_config]}"
    template_content="${template_content//\{\{PLUGIN_OPTIONAL_CONFIG\}\}/[$optional_config]}"
    template_content="${template_content//\{\{PLUGIN_MAX_MEMORY\}\}/$max_memory}"
    template_content="${template_content//\{\{PLUGIN_MAX_CPU\}\}/$max_cpu}"
    template_content="${template_content//\{\{PLUGIN_MAX_DISK\}\}/$max_disk}"
    template_content="${template_content//\{\{PLUGIN_NETWORK_ACCESS\}\}/$network_access}"
    template_content="${template_content//\{\{PLUGIN_FILE_PERMISSIONS\}\}/[$file_permissions]}"
    template_content="${template_content//\{\{PLUGIN_SANDBOX_MODE\}\}/$sandbox_mode}"
    template_content="${template_content//\{\{PLUGIN_ALLOWED_COMMANDS\}\}/[$allowed_commands]}"
    template_content="${template_content//\{\{PLUGIN_RESTRICTED_PATHS\}\}/[$restricted_paths]}"
    template_content="${template_content//\{\{PLUGIN_ENV_ISOLATION\}\}/$env_isolation}"
    template_content="${template_content//\{\{PLUGIN_REQUIRED_DEPS_BASH\}\}/$required_deps_bash}"
    template_content="${template_content//\{\{PLUGIN_REQUIRED_CONFIG_BASH\}\}/$required_config_bash}"
    
    echo "$template_content"
}

# =============================================================================
# ADDITIONAL FILE GENERATORS
# =============================================================================

# Generate plugin README
# Usage: _generate_plugin_readme config_json
_generate_plugin_readme() {
    local config="$1"
    local plugin_name=$(echo "$config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    local plugin_description=$(echo "$config" | grep -o '"description": "[^"]*"' | cut -d'"' -f4)
    local plugin_author=$(echo "$config" | grep -o '"author": "[^"]*"' | cut -d'"' -f4)
    local plugin_type=$(echo "$config" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    
    cat <<EOF
# $plugin_name

$plugin_description

## Plugin Information

- **Type**: $plugin_type
- **Author**: $plugin_author
- **Generated**: $(date '+%Y-%m-%d %H:%M:%S')

## Installation

1. Copy this plugin directory to your Unity plugins directory
2. Register and load the plugin:
   \`\`\`bash
   ./lib/unity/plugins/unity-plugin-framework.sh discover
   \`\`\`

## Configuration

See \`config.yml\` for configuration options.

## Development

This plugin was generated from the Unity Plugin Template. To customize:

1. Edit \`plugin.sh\` to implement your specific functionality
2. Update the metadata in the \`plugin_metadata()\` function
3. Implement the required lifecycle functions
4. Add your event handlers and extension hooks
5. Test thoroughly before deployment

## Usage Example

See \`example.sh\` for usage examples.

## License

This plugin is licensed under the terms specified in the plugin metadata.
EOF
}

# Generate plugin configuration template
# Usage: _generate_plugin_config config_json
_generate_plugin_config() {
    local config="$1"
    local plugin_name=$(echo "$config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    
    cat <<EOF
# Unity Plugin Configuration: $plugin_name
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

plugin:
  enabled: true
  priority: 50
  
  # Plugin-specific configuration
  settings:
    # Add your configuration options here
    debug: false
    timeout: 30
    
  # Resource limits
  resources:
    max_memory_mb: 50
    max_cpu_percent: 10
    max_disk_mb: 100
    
  # Security settings
  security:
    sandbox_mode: true
    network_access: true
EOF
}

# Generate plugin usage example
# Usage: _generate_plugin_example config_json
_generate_plugin_example() {
    local config="$1"
    local plugin_name=$(echo "$config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    
    cat <<EOF
#!/bin/bash
# Unity Plugin Usage Example: $plugin_name
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

set -euo pipefail

# Example of how to use the $plugin_name plugin

echo "Loading Unity Plugin Framework..."
source "./lib/unity/plugins/unity-plugin-framework.sh"

echo "Discovering plugins..."
discover_plugins

echo "Loading $plugin_name plugin..."
load_plugin "$plugin_name"

echo "Starting $plugin_name plugin..."
start_plugin "$plugin_name"

echo "Checking plugin status..."
get_plugin_status "$plugin_name"

echo "Running plugin health check..."
run_plugin_health_check "$plugin_name"

echo "Plugin example completed!"
EOF
    
    chmod +x
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Show plugin configuration summary
# Usage: _show_plugin_summary config_json
_show_plugin_summary() {
    local config="$1"
    
    echo "Name:        $(echo "$config" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)"
    echo "Description: $(echo "$config" | grep -o '"description": "[^"]*"' | cut -d'"' -f4)"
    echo "Author:      $(echo "$config" | grep -o '"author": "[^"]*"' | cut -d'"' -f4)"
    echo "Type:        $(echo "$config" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)"
    echo "Category:    $(echo "$config" | grep -o '"category": "[^"]*"' | cut -d'"' -f4)"
    echo "Priority:    $(echo "$config" | grep -o '"priority": "[^"]*"' | cut -d'"' -f4)"
    
    local required_deps=$(echo "$config" | grep -o '"required_deps": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    if [[ -n "$required_deps" ]]; then
        echo "Required Dependencies: [$required_deps]"
    fi
    
    local extension_points=$(echo "$config" | grep -o '"extension_points": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    if [[ -n "$extension_points" ]]; then
        echo "Extension Points: [$extension_points]"
    fi
    
    local event_handlers=$(echo "$config" | grep -o '"event_handlers": \[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    if [[ -n "$event_handlers" ]]; then
        echo "Event Handlers: [$event_handlers]"
    fi
}

# Confirm user action
# Usage: _confirm "Question?"
_confirm() {
    local question="$1"
    local response
    
    while true; do
        read -p "$question (y/n): " response
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# =============================================================================
# MAIN SCRIPT EXECUTION
# =============================================================================

# Main function for command-line usage
main() {
    case "${1:-interactive}" in
        "interactive"|"i")
            generate_plugin_interactive
            ;;
        "from-file"|"f")
            if [[ -n "${2:-}" ]]; then
                generate_plugin_from_file "$2"
            else
                echo "Usage: $0 from-file <config-file>" >&2
                exit 1
            fi
            ;;
        "help"|"h"|*)
            echo "Unity Plugin Generator v$UNITY_PLUGIN_GENERATOR_VERSION"
            echo ""
            echo "Usage:"
            echo "  $0 interactive          - Interactive plugin generation (default)"
            echo "  $0 from-file <config>   - Generate from configuration file"
            echo "  $0 help                 - Show this help"
            echo ""
            echo "The interactive mode will guide you through creating a new plugin."
            echo "Configuration files should contain JSON with plugin specifications."
            ;;
    esac
}

# Export functions for use by other scripts
export -f generate_plugin_interactive
export -f generate_plugin_from_file
export -f generate_plugin_from_config

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi