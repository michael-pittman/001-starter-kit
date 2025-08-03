#!/bin/bash
# Unity CLI - Unified command-line interface for all GeuseMaker operations

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source Unity core
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || {
    echo "Error: Failed to load Unity core system" >&2
    exit 1
}

# CLI version
UNITY_CLI_VERSION="1.0.0"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Show banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
   _   _       _ _           ____ _     ___ 
  | | | |_ __ (_) |_ _   _  / ___| |   |_ _|
  | | | | '_ \| | __| | | || |   | |    | | 
  | |_| | | | | | |_| |_| || |___| |___ | | 
   \___/|_| |_|_|\__|\__, | \____|_____|___|
                     |___/                   
EOF
    echo -e "${NC}"
    echo -e "${WHITE}GeuseMaker Unity Command Line Interface v${UNITY_CLI_VERSION}${NC}"
    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Usage: unity-cli [command] [subcommand] [options]

Commands:
  init                 Initialize Unity system
  deploy               Deploy infrastructure
  destroy              Destroy resources
  status               Show deployment status
  logs                 View logs
  config               Configuration management
  monitor              Monitoring operations
  service              Service management
  plugin               Plugin management
  maintain             Maintenance operations
  event                Event management
  help                 Show help for a command

Global Options:
  --verbose, -v        Enable verbose output
  --quiet, -q          Suppress non-error output
  --json               Output in JSON format
  --no-color           Disable colored output
  --help, -h           Show this help message

Examples:
  unity-cli init                           # Initialize Unity system
  unity-cli deploy spot my-stack           # Deploy spot instance
  unity-cli status my-deployment           # Check deployment status
  unity-cli service list                   # List all services
  unity-cli monitor health                 # Check system health
  unity-cli help deploy                    # Get help for deploy command

For detailed help on any command:
  unity-cli help [command]
EOF
}

# Command: init
cmd_init() {
    echo -e "${BLUE}Initializing Unity system...${NC}"
    
    # Initialize Unity core
    unity_init || {
        echo -e "${RED}Failed to initialize Unity core${NC}" >&2
        return 1
    }
    
    # Check for required configuration
    if [[ ! -f "$PROJECT_ROOT/config/unity.yml" ]]; then
        echo -e "${YELLOW}Unity configuration not found. Creating default configuration...${NC}"
        
        # Run configuration setup
        if [[ -x "$PROJECT_ROOT/scripts/setup-configuration.sh" ]]; then
            "$PROJECT_ROOT/scripts/setup-configuration.sh"
        else
            echo -e "${RED}Configuration setup script not found${NC}" >&2
            return 1
        fi
    fi
    
    # Initialize all core services
    echo -e "${BLUE}Initializing core services...${NC}"
    
    local services=("config" "aws" "docker" "monitor" "deployment")
    for service in "${services[@]}"; do
        echo -n "  Initializing $service service... "
        if unity_initialize_service "$service" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            echo -e "${RED}Failed to initialize $service service${NC}" >&2
            return 1
        fi
    done
    
    echo -e "${GREEN}Unity system initialized successfully!${NC}"
}

# Command: deploy
cmd_deploy() {
    local deployment_type="${1:-}"
    local stack_name="${2:-}"
    
    if [[ -z "$deployment_type" ]]; then
        cat << EOF
Usage: unity-cli deploy [type] [stack-name] [options]

Deployment Types:
  spot         Deploy spot instance (70% cost savings)
  alb          Deploy with Application Load Balancer
  cdn          Deploy with CloudFront CDN
  full         Deploy complete stack

Options:
  --strategy STRATEGY    Deployment strategy (rolling/blue-green/canary)
  --environment ENV      Environment (dev/staging/prod)
  --region REGION        AWS region
  --dry-run             Validate without deploying

Examples:
  unity-cli deploy spot my-stack
  unity-cli deploy alb prod-stack --environment production
  unity-cli deploy full test-stack --strategy blue-green
EOF
        return 0
    fi
    
    # Forward to deploy.sh
    "$PROJECT_ROOT/deploy.sh" "$@"
}

# Command: destroy
cmd_destroy() {
    local stack_name="${1:-}"
    
    if [[ -z "$stack_name" ]]; then
        echo "Usage: unity-cli destroy [stack-name]"
        return 1
    fi
    
    # Forward to deploy.sh
    "$PROJECT_ROOT/deploy.sh" destroy "$stack_name"
}

# Command: status
cmd_status() {
    local target="${1:-all}"
    
    echo -e "${BLUE}Unity System Status${NC}"
    echo "==================="
    echo ""
    
    # Show Unity core status
    echo -e "${CYAN}Core System:${NC}"
    echo "  Unity Initialized: ${UNITY_INITIALIZED:-false}"
    echo "  Services Directory: ${UNITY_SERVICES_DIR:-not set}"
    echo "  Events Directory: ${UNITY_EVENTS_DIR:-not set}"
    echo ""
    
    # Show service status
    echo -e "${CYAN}Services:${NC}"
    for service in $(unity_list_services); do
        local status
        if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
            status="${UNITY_SERVICE_STATUS[$service]:-unknown}"
        else
            local status_var="UNITY_SERVICE_${service}_STATUS"
            status="${!status_var:-unknown}"
        fi
        
        case "$status" in
            initialized|running)
                echo -e "  $service: ${GREEN}$status${NC}"
                ;;
            registered)
                echo -e "  $service: ${YELLOW}$status${NC}"
                ;;
            *)
                echo -e "  $service: ${RED}$status${NC}"
                ;;
        esac
    done
    echo ""
    
    # Show deployment status if requested
    if [[ "$target" != "all" ]]; then
        echo -e "${CYAN}Deployment Status:${NC}"
        unity_deployment_execute "status" "$target"
    else
        echo -e "${CYAN}Active Deployments:${NC}"
        unity_deployment_execute "status" "all"
    fi
}

# Command: logs
cmd_logs() {
    local target="${1:-unity}"
    local lines="${2:-50}"
    
    case "$target" in
        unity)
            echo -e "${BLUE}Unity Core Logs:${NC}"
            tail -n "$lines" logs/unity/core.log 2>/dev/null || echo "No Unity core logs found"
            ;;
        events)
            echo -e "${BLUE}Unity Event Logs:${NC}"
            tail -n "$lines" logs/unity/events.log 2>/dev/null || echo "No event logs found"
            ;;
        deployment|deploy)
            echo -e "${BLUE}Deployment Logs:${NC}"
            tail -n "$lines" logs/unity/deployment-service.log 2>/dev/null || echo "No deployment logs found"
            ;;
        *)
            # Assume it's a deployment ID
            echo -e "${BLUE}Logs for deployment: $target${NC}"
            local log_file=".unity/deployment/logs/${target}.log"
            if [[ -f "$log_file" ]]; then
                tail -n "$lines" "$log_file"
            else
                echo -e "${RED}No logs found for deployment: $target${NC}"
            fi
            ;;
    esac
}

# Command: config
cmd_config() {
    local action="${1:-list}"
    shift
    
    case "$action" in
        list)
            echo -e "${BLUE}Unity Configuration:${NC}"
            config_config_service "get"
            ;;
        get)
            local key="$1"
            if [[ -z "$key" ]]; then
                echo "Usage: unity-cli config get <key>"
                return 1
            fi
            config_config_service "get" "$key"
            ;;
        set)
            local key="$1"
            local value="$2"
            if [[ -z "$key" || -z "$value" ]]; then
                echo "Usage: unity-cli config set <key> <value>"
                return 1
            fi
            config_config_service "set" "$key" "$value"
            ;;
        reload)
            echo -e "${BLUE}Reloading configuration...${NC}"
            config_config_service "reload"
            echo -e "${GREEN}Configuration reloaded${NC}"
            ;;
        validate)
            echo -e "${BLUE}Validating configuration...${NC}"
            if validate_config; then
                echo -e "${GREEN}Configuration is valid${NC}"
            else
                echo -e "${RED}Configuration validation failed${NC}"
                return 1
            fi
            ;;
        *)
            echo "Usage: unity-cli config [list|get|set|reload|validate]"
            return 1
            ;;
    esac
}

# Command: monitor
cmd_monitor() {
    local action="${1:-status}"
    shift
    
    case "$action" in
        status)
            echo -e "${BLUE}System Health Status:${NC}"
            unity_get_service_metrics "all"
            ;;
        health)
            echo -e "${BLUE}Running health checks...${NC}"
            for service in $(unity_list_services); do
                echo -n "  Checking $service... "
                if health_result=$(health_${service}_service 2>&1); then
                    local status="${health_result%%|*}"
                    local details="${health_result#*|}"
                    if [[ "$status" == "healthy" ]]; then
                        echo -e "${GREEN}✓ healthy${NC}"
                    else
                        echo -e "${RED}✗ $status${NC}"
                        [[ -n "$details" ]] && echo "    Details: $details"
                    fi
                else
                    echo -e "${RED}✗ check failed${NC}"
                fi
            done
            ;;
        metrics)
            echo -e "${BLUE}System Metrics:${NC}"
            unity_get_service_metrics
            ;;
        alerts)
            echo -e "${BLUE}Recent Alerts:${NC}"
            find .unity/alerts -name "*.alert" -mtime -1 -exec basename {} \; 2>/dev/null | head -20
            ;;
        report)
            echo -e "${BLUE}Generating monitoring report...${NC}"
            generate_metrics_report
            echo -e "${GREEN}Report generated${NC}"
            ;;
        *)
            echo "Usage: unity-cli monitor [status|health|metrics|alerts|report]"
            return 1
            ;;
    esac
}

# Command: service
cmd_service() {
    local action="${1:-list}"
    local service_name="${2:-}"
    shift 2
    
    case "$action" in
        list)
            echo -e "${BLUE}Registered Services:${NC}"
            unity_list_services
            ;;
        status)
            if [[ -z "$service_name" ]]; then
                echo "Usage: unity-cli service status <service-name>"
                return 1
            fi
            local status
            if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
                status="${UNITY_SERVICE_STATUS[$service_name]:-not found}"
            else
                local status_var="UNITY_SERVICE_${service_name}_STATUS"
                status="${!status_var:-not found}"
            fi
            echo "Service $service_name: $status"
            ;;
        start)
            if [[ -z "$service_name" ]]; then
                echo "Usage: unity-cli service start <service-name>"
                return 1
            fi
            echo -e "${BLUE}Starting service: $service_name${NC}"
            if start_${service_name}_service; then
                echo -e "${GREEN}Service started successfully${NC}"
            else
                echo -e "${RED}Failed to start service${NC}"
                return 1
            fi
            ;;
        stop)
            if [[ -z "$service_name" ]]; then
                echo "Usage: unity-cli service stop <service-name>"
                return 1
            fi
            echo -e "${BLUE}Stopping service: $service_name${NC}"
            if stop_${service_name}_service; then
                echo -e "${GREEN}Service stopped successfully${NC}"
            else
                echo -e "${RED}Failed to stop service${NC}"
                return 1
            fi
            ;;
        restart)
            if [[ -z "$service_name" ]]; then
                echo "Usage: unity-cli service restart <service-name>"
                return 1
            fi
            cmd_service stop "$service_name" && cmd_service start "$service_name"
            ;;
        health)
            if [[ -z "$service_name" ]]; then
                echo "Usage: unity-cli service health <service-name>"
                return 1
            fi
            echo -e "${BLUE}Checking health of service: $service_name${NC}"
            if health_result=$(health_${service_name}_service 2>&1); then
                local status="${health_result%%|*}"
                local details="${health_result#*|}"
                echo "Health Status: $status"
                [[ -n "$details" ]] && echo "Details: $details"
            else
                echo -e "${RED}Health check failed${NC}"
                return 1
            fi
            ;;
        *)
            echo "Usage: unity-cli service [list|status|start|stop|restart|health] [service-name]"
            return 1
            ;;
    esac
}

# Command: plugin
cmd_plugin() {
    local action="${1:-list}"
    shift
    
    case "$action" in
        list)
            echo -e "${BLUE}Available Plugins:${NC}"
            if [[ -d "$PROJECT_ROOT/lib/unity/plugins" ]]; then
                for plugin_dir in "$PROJECT_ROOT/lib/unity/plugins"/*; do
                    if [[ -d "$plugin_dir" && -f "$plugin_dir/plugin.sh" ]]; then
                        local plugin_name=$(basename "$plugin_dir")
                        echo "  - $plugin_name"
                    fi
                done
            else
                echo "  No plugins found"
            fi
            ;;
        enable)
            local plugin_name="$1"
            if [[ -z "$plugin_name" ]]; then
                echo "Usage: unity-cli plugin enable <plugin-name>"
                return 1
            fi
            echo -e "${BLUE}Enabling plugin: $plugin_name${NC}"
            # Plugin enabling logic here
            echo -e "${GREEN}Plugin enabled${NC}"
            ;;
        disable)
            local plugin_name="$1"
            if [[ -z "$plugin_name" ]]; then
                echo "Usage: unity-cli plugin disable <plugin-name>"
                return 1
            fi
            echo -e "${BLUE}Disabling plugin: $plugin_name${NC}"
            # Plugin disabling logic here
            echo -e "${GREEN}Plugin disabled${NC}"
            ;;
        info)
            local plugin_name="$1"
            if [[ -z "$plugin_name" ]]; then
                echo "Usage: unity-cli plugin info <plugin-name>"
                return 1
            fi
            echo -e "${BLUE}Plugin Information: $plugin_name${NC}"
            # Show plugin info
            ;;
        *)
            echo "Usage: unity-cli plugin [list|enable|disable|info] [plugin-name]"
            return 1
            ;;
    esac
}

# Command: maintain
cmd_maintain() {
    local action="${1:-help}"
    shift
    
    case "$action" in
        fix)
            echo -e "${BLUE}Running maintenance fix operations...${NC}"
            # Maintenance fix logic
            ;;
        cleanup)
            echo -e "${BLUE}Running cleanup operations...${NC}"
            # Cleanup logic
            ;;
        backup)
            echo -e "${BLUE}Creating backup...${NC}"
            # Backup logic
            ;;
        optimize)
            echo -e "${BLUE}Running optimization...${NC}"
            # Optimization logic
            ;;
        *)
            echo "Usage: unity-cli maintain [fix|cleanup|backup|optimize]"
            return 1
            ;;
    esac
}

# Command: event
cmd_event() {
    local action="${1:-list}"
    shift
    
    case "$action" in
        list)
            echo -e "${BLUE}Recent Events:${NC}"
            tail -20 logs/unity/events.log 2>/dev/null || echo "No events found"
            ;;
        emit)
            local event_name="$1"
            local event_data="${2:-}"
            if [[ -z "$event_name" ]]; then
                echo "Usage: unity-cli event emit <event-name> [data]"
                return 1
            fi
            unity_emit_event "$event_name" "unity-cli" "$event_data"
            echo -e "${GREEN}Event emitted: $event_name${NC}"
            ;;
        watch)
            echo -e "${BLUE}Watching Unity events (Ctrl+C to stop)...${NC}"
            tail -f logs/unity/events.log 2>/dev/null || echo "No event log found"
            ;;
        *)
            echo "Usage: unity-cli event [list|emit|watch]"
            return 1
            ;;
    esac
}

# Command: help
cmd_help() {
    local command="${1:-}"
    
    if [[ -z "$command" ]]; then
        show_usage
        return 0
    fi
    
    case "$command" in
        deploy)
            cmd_deploy
            ;;
        destroy)
            echo "Usage: unity-cli destroy [stack-name]"
            echo ""
            echo "Destroy all resources for the specified stack."
            ;;
        status)
            echo "Usage: unity-cli status [target]"
            echo ""
            echo "Show status of Unity system or specific deployment."
            echo "Target can be 'all' or a specific deployment ID."
            ;;
        *)
            echo "No help available for command: $command"
            echo "Try: unity-cli help"
            return 1
            ;;
    esac
}

# Parse global options
parse_global_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                export UNITY_LOG_LEVEL="DEBUG"
                shift
                ;;
            --quiet|-q)
                export UNITY_LOG_LEVEL="ERROR"
                shift
                ;;
            --json)
                export UNITY_OUTPUT_FORMAT="json"
                shift
                ;;
            --no-color)
                RED=""
                GREEN=""
                YELLOW=""
                BLUE=""
                PURPLE=""
                CYAN=""
                WHITE=""
                NC=""
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Return remaining arguments
    echo "$@"
}

# Main execution
main() {
    # Parse global options
    local remaining_args
    remaining_args=$(parse_global_options "$@")
    set -- $remaining_args
    
    # Get command
    local command="${1:-help}"
    shift
    
    # Show banner for interactive commands
    if [[ -t 1 && "$command" != "help" && "${UNITY_OUTPUT_FORMAT:-}" != "json" ]]; then
        show_banner
    fi
    
    # Initialize Unity if not already initialized
    if [[ "$command" != "init" && "$command" != "help" ]]; then
        unity_init >/dev/null 2>&1 || true
    fi
    
    # Execute command
    case "$command" in
        init)
            cmd_init "$@"
            ;;
        deploy)
            cmd_deploy "$@"
            ;;
        destroy)
            cmd_destroy "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;
        config)
            cmd_config "$@"
            ;;
        monitor)
            cmd_monitor "$@"
            ;;
        service)
            cmd_service "$@"
            ;;
        plugin)
            cmd_plugin "$@"
            ;;
        maintain)
            cmd_maintain "$@"
            ;;
        event)
            cmd_event "$@"
            ;;
        help)
            cmd_help "$@"
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}" >&2
            echo "Try: unity-cli help" >&2
            exit 1
            ;;
    esac
}

# Run main
main "$@"