#!/bin/bash
# Unity Documentation Generator
# Generates API documentation from Unity source code

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
UNITY_LIB_DIR="$UNITY_ROOT/lib/unity"
DOCS_DIR="$UNITY_ROOT/docs/unity"
API_DOCS_DIR="$DOCS_DIR/api"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Extract function documentation
extract_functions() {
    local file="$1"
    local service_name="$2"
    
    # Extract function definitions and their comments
    awk '
    /^# Function:/ {
        desc = $0
        getline
        while ($0 ~ /^#/) {
            desc = desc "\n" $0
            getline
        }
    }
    /^(function |)[a-zA-Z_][a-zA-Z0-9_]*\(\)/ {
        if (desc) {
            print desc
        }
        print $0
        desc = ""
    }
    ' "$file"
}

# Generate markdown for a service
generate_service_docs() {
    local service_file="$1"
    local service_name="$2"
    local output_file="$API_DOCS_DIR/${service_name}-api.md"
    
    log_info "Generating documentation for $service_name service..."
    
    cat > "$output_file" << EOF
# $service_name Service API Reference

## Overview

This document provides the complete API reference for the Unity $service_name service.

## Functions

EOF
    
    # Extract and document each function
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ Function: ]]; then
            # Start new function documentation
            echo "" >> "$output_file"
            echo "---" >> "$output_file"
            echo "" >> "$output_file"
        fi
        
        if [[ "$line" =~ ^function\ ([a-zA-Z_][a-zA-Z0-9_]*) ]] || [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\(\) ]]; then
            local func_name="${BASH_REMATCH[1]}"
            echo "### \`$func_name()\`" >> "$output_file"
            echo "" >> "$output_file"
        elif [[ "$line" =~ ^#\ Parameters: ]]; then
            echo "**Parameters:**" >> "$output_file"
            echo "" >> "$output_file"
        elif [[ "$line" =~ ^#\ Returns: ]]; then
            echo "**Returns:**" >> "$output_file"
            echo "" >> "$output_file"
        elif [[ "$line" =~ ^#\ Description: ]]; then
            echo "${line#*: }" >> "$output_file"
            echo "" >> "$output_file"
        elif [[ "$line" =~ ^#\ Example: ]]; then
            echo "**Example:**" >> "$output_file"
            echo "" >> "$output_file"
            echo "\`\`\`bash" >> "$output_file"
        elif [[ "$line" =~ ^#\ \ \ (.+) ]]; then
            echo "${BASH_REMATCH[1]}" >> "$output_file"
        fi
    done < <(extract_functions "$service_file" "$service_name")
    
    # Add usage examples section
    cat >> "$output_file" << EOF

## Usage Examples

### Basic Usage

\`\`\`bash
# Source the service
source "\${UNITY_LIB_DIR}/services/${service_name}.sh"

# Initialize service
unity_${service_name}_init

# Use service functions
unity_${service_name}_example_function "parameter"
\`\`\`

### Advanced Usage

See the [Unity Developer Guide](../core/unity-developer-guide.md) for advanced usage patterns and best practices.

## Events

This service publishes the following events:

| Event | Description | Data |
|-------|-------------|------|
| \`${service_name}.initialized\` | Service initialized | \`{}\` |
| \`${service_name}.error\` | Service error occurred | \`{"error": "message"}\` |

## Configuration

Configuration options for this service:

\`\`\`yaml
services:
  ${service_name}:
    enabled: true
    # Add service-specific configuration here
\`\`\`

## Error Codes

| Code | Description | Resolution |
|------|-------------|------------|
| 1 | Initialization failed | Check configuration and dependencies |
| 2 | Invalid parameters | Verify function parameters |
| 3 | Service unavailable | Ensure service is started |

## See Also

- [Unity Overview](../core/unity-overview.md)
- [Unity Configuration](../core/unity-configuration.md)
- [Unity Developer Guide](../core/unity-developer-guide.md)
EOF
    
    log_success "Generated $output_file"
}

# Generate docs for all services
generate_all_docs() {
    log_info "Starting API documentation generation..."
    
    # Create API docs directory
    mkdir -p "$API_DOCS_DIR"
    
    # Generate docs for each service
    for service_file in "$UNITY_LIB_DIR/services"/*.sh; do
        if [[ -f "$service_file" ]]; then
            local service_name=$(basename "$service_file" .sh)
            generate_service_docs "$service_file" "$service_name"
        fi
    done
    
    # Generate index file
    generate_api_index
    
    log_success "API documentation generation complete!"
}

# Generate API index
generate_api_index() {
    local index_file="$API_DOCS_DIR/index.md"
    
    log_info "Generating API index..."
    
    cat > "$index_file" << EOF
# Unity API Reference

## Services

The Unity system provides the following services:

EOF
    
    for api_file in "$API_DOCS_DIR"/*-api.md; do
        if [[ -f "$api_file" ]]; then
            local service_name=$(basename "$api_file" -api.md)
            echo "- [$service_name](./${service_name}-api.md)" >> "$index_file"
        fi
    done
    
    cat >> "$index_file" << EOF

## Core Libraries

### Base Functions

Located in \`lib/unity/core/base.sh\`:

- Logging functions (\`log_info\`, \`log_error\`, etc.)
- Error handling (\`error_handler\`, \`trap_errors\`)
- Utility functions (\`generate_uuid\`, \`timestamp\`)

### Event System

Located in \`lib/unity/events/\`:

- Event publishing (\`publish_event\`)
- Event subscription (\`subscribe_event\`)
- Event handling (\`handle_event\`)

### Plugin System

Located in \`lib/unity/plugins/\`:

- Plugin loading (\`load_plugin\`)
- Plugin lifecycle (\`init_plugin\`, \`start_plugin\`, \`stop_plugin\`)
- Plugin registry (\`register_plugin\`, \`list_plugins\`)

## Conventions

### Function Naming

All Unity functions follow the naming convention:

\`\`\`
unity_<service>_<action>
\`\`\`

Examples:
- \`unity_aws_ec2_create\`
- \`unity_config_get\`
- \`unity_docker_compose_up\`

### Event Naming

Events follow the pattern:

\`\`\`
<service>.<action>.<status>
\`\`\`

Examples:
- \`deployment.start.initiated\`
- \`aws.ec2.instance.created\`
- \`config.reload.completed\`

### Error Handling

All functions return:
- \`0\` on success
- Non-zero on failure

Error details are logged and optionally published as events.

## Getting Help

- [Unity Developer Guide](../core/unity-developer-guide.md)
- [Unity Tutorials](../core/unity-tutorials.md)
- Community: #unity-dev on Slack
EOF
    
    log_success "Generated API index"
}

# Main execution
main() {
    case "${1:-all}" in
        all)
            generate_all_docs
            ;;
        service)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 service <service-name>"
                exit 1
            fi
            service_file="$UNITY_LIB_DIR/services/${2}.sh"
            if [[ -f "$service_file" ]]; then
                generate_service_docs "$service_file" "$2"
            else
                log_warn "Service file not found: $service_file"
                exit 1
            fi
            ;;
        index)
            generate_api_index
            ;;
        *)
            echo "Usage: $0 {all|service <name>|index}"
            exit 1
            ;;
    esac
}

main "$@"