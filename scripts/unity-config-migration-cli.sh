#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Migration CLI Tool
# Command-line interface for configuration migration operations
# Compatible with bash 3.x+ and enterprise deployment patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL CONSTANTS
# =============================================================================

readonly CLI_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly CONFIG_ROOT="$PROJECT_ROOT/config"
readonly LIB_DIR="$PROJECT_ROOT/lib"

# CLI Configuration
readonly CLI_NAME="unity-config-migration"
readonly CLI_DESCRIPTION="Unity Configuration Migration and Validation Tool"

# Load Unity services
readonly UNITY_SERVICES_DIR="$LIB_DIR/unity/services"
readonly MIGRATION_SERVICE="$UNITY_SERVICES_DIR/unity-config-migration.sh"
readonly VALIDATION_ENGINE="$UNITY_SERVICES_DIR/config-validation-engine.sh"

# =============================================================================
# CLI FRAMEWORK AND UTILITIES
# =============================================================================

# Enhanced logging for CLI
cli_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo "[$timestamp] [CLI] ERROR: $message" >&2
            ;;
        "WARN")
            echo "[$timestamp] [CLI] WARN: $message" >&2
            ;;
        "INFO")
            echo "[$timestamp] [CLI] INFO: $message"
            ;;
        "SUCCESS")
            echo "[$timestamp] [CLI] SUCCESS: $message"
            ;;
        "DEBUG")
            [[ "${CLI_DEBUG:-false}" == "true" ]] && \
                echo "[$timestamp] [CLI] DEBUG: $message" >&2
            ;;
    esac
}

# CLI error handler
cli_error() {
    local error_code="$1"
    local error_message="$2"
    local suggestion="${3:-}"
    
    cli_log "ERROR" "$error_message"
    [[ -n "$suggestion" ]] && cli_log "INFO" "Suggestion: $suggestion"
    exit "$error_code"
}

# Load Unity services
load_unity_services() {
    cli_log "DEBUG" "Loading Unity services..."
    
    # Load migration service
    if [[ -f "$MIGRATION_SERVICE" ]]; then
        source "$MIGRATION_SERVICE" || {
            cli_error 1 "Failed to load migration service" \
                "Check if $MIGRATION_SERVICE exists and is readable"
        }
        cli_log "DEBUG" "Migration service loaded"
    else
        cli_error 1 "Migration service not found" \
            "Run from project root or ensure Unity services are installed"
    fi
    
    # Load validation engine
    if [[ -f "$VALIDATION_ENGINE" ]]; then
        source "$VALIDATION_ENGINE" || {
            cli_log "WARN" "Failed to load validation engine - some features may be unavailable"
        }
        cli_log "DEBUG" "Validation engine loaded"
    else
        cli_log "WARN" "Validation engine not found - validation features unavailable"
    fi
}

# Check prerequisites
check_prerequisites() {
    cli_log "DEBUG" "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    # Check for optional but recommended tools
    if ! command -v yq >/dev/null 2>&1; then
        cli_log "WARN" "yq not found - YAML processing will be limited"
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        cli_log "WARN" "bc not found - numeric validations will be limited"
    fi
    
    # Report missing critical tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        cli_error 2 "Missing required tools: ${missing_tools[*]}" \
            "Install missing tools: brew install jq yq (macOS) or apt-get install jq yq (Ubuntu)"
    fi
    
    # Check project structure
    if [[ ! -d "$CONFIG_ROOT" ]]; then
        cli_error 3 "Config directory not found: $CONFIG_ROOT" \
            "Run from project root directory"
    fi
    
    cli_log "DEBUG" "Prerequisites check completed"
}

# =============================================================================
# CLI COMMAND IMPLEMENTATIONS
# =============================================================================

# Discover configuration sources
cmd_discover() {
    local output_format="${1:-json}"
    local output_file="${2:-}"
    
    cli_log "INFO" "Discovering configuration sources..."
    
    # Initialize migration system
    initialize_config_migration || {
        cli_error 10 "Failed to initialize migration system"
    }
    
    # Discover sources
    local discovery_report
    discovery_report=$(discover_configuration_sources) || {
        cli_error 11 "Failed to discover configuration sources"
    }
    
    # Output results
    case "$output_format" in
        "json")
            if [[ -n "$output_file" ]]; then
                cp "$discovery_report" "$output_file"
                cli_log "SUCCESS" "Discovery report saved to: $output_file"
            else
                cat "$discovery_report"
            fi
            ;;
        "summary")
            generate_discovery_summary "$discovery_report"
            ;;
        "table")
            generate_discovery_table "$discovery_report"
            ;;
        *)
            cli_error 12 "Invalid output format: $output_format" \
                "Valid formats: json, summary, table"
            ;;
    esac
    
    cli_log "SUCCESS" "Configuration discovery completed"
}

# Validate configuration
cmd_validate() {
    local config_file="${1:-$CONFIG_ROOT/defaults.yml}"
    local output_format="${2:-json}"
    local output_file="${3:-}"
    
    cli_log "INFO" "Validating configuration: $config_file"
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        cli_error 20 "Configuration file not found: $config_file"
    fi
    
    # Initialize validation engine if available
    if declare -f initialize_validation_engine >/dev/null 2>&1; then
        initialize_validation_engine || {
            cli_log "WARN" "Failed to initialize validation engine - using basic validation"
        }
    fi
    
    # Validate configuration
    local validation_report
    if declare -f validate_configuration >/dev/null 2>&1; then
        validation_report=$(validate_configuration "$config_file") || {
            cli_error 21 "Configuration validation failed"
        }
    else
        cli_error 22 "Validation functionality not available" \
            "Ensure validation engine is properly loaded"
    fi
    
    # Output results
    case "$output_format" in
        "json")
            if [[ -n "$output_file" ]]; then
                cp "$validation_report" "$output_file"
                cli_log "SUCCESS" "Validation report saved to: $output_file"
            else
                cat "$validation_report"
            fi
            ;;
        "summary")
            generate_validation_summary "$validation_report"
            ;;
        "table")
            generate_validation_table "$validation_report"
            ;;
        "errors-only")
            show_validation_errors_only "$validation_report"
            ;;
        *)
            cli_error 23 "Invalid output format: $output_format" \
                "Valid formats: json, summary, table, errors-only"
            ;;
    esac
    
    # Determine exit code based on validation results
    local error_count=$(jq '.errors | length' "$validation_report" 2>/dev/null || echo "0")
    if [[ "$error_count" -gt "0" ]]; then
        cli_log "WARN" "Validation completed with $error_count errors"
        exit 1
    else
        cli_log "SUCCESS" "Configuration validation passed"
    fi
}

# Generate migration plan
cmd_plan() {
    local target_environment="${1:-development}"
    local output_file="${2:-}"
    local show_details="${3:-false}"
    
    cli_log "INFO" "Generating migration plan for environment: $target_environment"
    
    # Initialize migration system
    initialize_config_migration "$target_environment" || {
        cli_error 30 "Failed to initialize migration system"
    }
    
    # Generate migration plan
    local migration_plan
    migration_plan=$(generate_migration_plan "$target_environment") || {
        cli_error 31 "Failed to generate migration plan"
    }
    
    # Output results
    if [[ -n "$output_file" ]]; then
        cp "$migration_plan" "$output_file"
        cli_log "SUCCESS" "Migration plan saved to: $output_file"
    else
        if [[ "$show_details" == "true" ]]; then
            cat "$migration_plan"
        else
            generate_migration_plan_summary "$migration_plan"
        fi
    fi
    
    cli_log "SUCCESS" "Migration plan generated successfully"
}

# Execute migration
cmd_migrate() {
    local target_environment="${1:-development}"
    local dry_run="${2:-false}"
    local backup_name="${3:-}"
    local force="${4:-false}"
    
    cli_log "INFO" "Starting configuration migration to environment: $target_environment"
    
    # Confirmation for non-dry-run
    if [[ "$dry_run" != "true" ]] && [[ "$force" != "true" ]]; then
        echo "This will modify your configuration files. Are you sure? (y/N)"
        read -r confirmation
        if [[ "$confirmation" != "y" ]] && [[ "$confirmation" != "Y" ]]; then
            cli_log "INFO" "Migration cancelled by user"
            exit 0
        fi
    fi
    
    # Create backup if specified
    if [[ -n "$backup_name" ]] && [[ "$dry_run" != "true" ]]; then
        cli_log "INFO" "Creating backup: $backup_name"
        create_config_backup "$backup_name" || {
            cli_error 40 "Failed to create backup"
        }
    fi
    
    # Execute migration
    if declare -f migrate_configuration >/dev/null 2>&1; then
        migrate_configuration "$target_environment" "$dry_run" || {
            cli_error 41 "Migration failed"
        }
    else
        cli_error 42 "Migration functionality not available" \
            "Ensure migration service is properly loaded"
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        cli_log "SUCCESS" "Dry run completed - no changes made"
    else
        cli_log "SUCCESS" "Configuration migration completed successfully"
    fi
}

# Create backup
cmd_backup() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local include_state="${2:-true}"
    
    cli_log "INFO" "Creating configuration backup: $backup_name"
    
    # Create backup
    local backup_dir
    if declare -f create_config_backup >/dev/null 2>&1; then
        backup_dir=$(create_config_backup "$backup_name") || {
            cli_error 50 "Failed to create backup"
        }
    else
        cli_error 51 "Backup functionality not available"
    fi
    
    cli_log "SUCCESS" "Backup created: $backup_dir"
    
    # Show backup contents
    if [[ -f "$backup_dir/backup-metadata.json" ]]; then
        local files_count=$(jq -r '.files_count' "$backup_dir/backup-metadata.json" 2>/dev/null || echo "unknown")
        cli_log "INFO" "Backup contains $files_count files"
    fi
}

# Restore backup
cmd_restore() {
    local backup_name="$1"
    local force="${2:-false}"
    
    if [[ -z "$backup_name" ]]; then
        cli_error 60 "Backup name is required" \
            "Use: $CLI_NAME restore <backup_name>"
    fi
    
    cli_log "INFO" "Restoring configuration from backup: $backup_name"
    
    # Confirmation
    if [[ "$force" != "true" ]]; then
        echo "This will overwrite your current configuration. Are you sure? (y/N)"
        read -r confirmation
        if [[ "$confirmation" != "y" ]] && [[ "$confirmation" != "Y" ]]; then
            cli_log "INFO" "Restore cancelled by user"
            exit 0
        fi
    fi
    
    # Restore backup
    if declare -f restore_config_backup >/dev/null 2>&1; then
        restore_config_backup "$backup_name" || {
            cli_error 61 "Failed to restore backup"
        }
    else
        cli_error 62 "Restore functionality not available"
    fi
    
    cli_log "SUCCESS" "Configuration restored from backup: $backup_name"
}

# List backups
cmd_list_backups() {
    local backup_dir="$CONFIG_ROOT/migration-backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        cli_log "INFO" "No backups found"
        return 0
    fi
    
    cli_log "INFO" "Available configuration backups:"
    echo
    printf "%-20s %-20s %-10s %s\n" "BACKUP NAME" "CREATED" "FILES" "SIZE"
    printf "%-20s %-20s %-10s %s\n" "----------" "-------" "-----" "----"
    
    for backup in "$backup_dir"/*; do
        if [[ -d "$backup" ]]; then
            local backup_name=$(basename "$backup")
            local metadata_file="$backup/backup-metadata.json"
            
            if [[ -f "$metadata_file" ]]; then
                local created_at=$(jq -r '.created_at' "$metadata_file" 2>/dev/null || echo "unknown")
                local files_count=$(jq -r '.files_count' "$metadata_file" 2>/dev/null || echo "0")
                local backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1 || echo "unknown")
                
                # Format timestamp
                local formatted_date=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created_at")
                
                printf "%-20s %-20s %-10s %s\n" "$backup_name" "$formatted_date" "$files_count" "$backup_size"
            else
                printf "%-20s %-20s %-10s %s\n" "$backup_name" "unknown" "unknown" "unknown"
            fi
        fi
    done
}

# Show migration status
cmd_status() {
    local show_details="${1:-false}"
    
    cli_log "INFO" "Checking migration status..."
    
    # Get migration status
    local status_report
    if declare -f get_migration_status >/dev/null 2>&1; then
        status_report=$(get_migration_status) || {
            cli_log "WARN" "Unable to retrieve migration status"
            echo '{"status": "unknown", "message": "Status unavailable"}'
            return 1
        }
    else
        echo '{"status": "not_available", "message": "Migration service not loaded"}'
        return 1
    fi
    
    # Display status
    if [[ "$show_details" == "true" ]]; then
        echo "$status_report" | jq '.'
    else
        local status=$(echo "$status_report" | jq -r '.status')
        local message=$(echo "$status_report" | jq -r '.message')
        
        cli_log "INFO" "Migration Status: $status"
        cli_log "INFO" "Message: $message"
    fi
}

# =============================================================================
# OUTPUT FORMATTING FUNCTIONS
# =============================================================================

# Generate discovery summary
generate_discovery_summary() {
    local discovery_report="$1"
    
    echo "Configuration Discovery Summary"
    echo "==============================="
    echo
    
    # Statistics
    local total_sources=$(jq '.statistics.total_sources' "$discovery_report" 2>/dev/null || echo "0")
    local total_variables=$(jq '.statistics.total_variables' "$discovery_report" 2>/dev/null || echo "0")
    
    echo "Total Sources: $total_sources"
    echo "Total Variables: $total_variables"
    echo
    
    # Source breakdown
    local yaml_count=$(jq '.sources.yaml_configs | length' "$discovery_report" 2>/dev/null || echo "0")
    local env_count=$(jq '.sources.env_files | length' "$discovery_report" 2>/dev/null || echo "0")
    local param_count=$(jq '.sources.parameter_store | length' "$discovery_report" 2>/dev/null || echo "0")
    local script_count=$(jq '.sources.hardcoded_variables | length' "$discovery_report" 2>/dev/null || echo "0")
    
    echo "Source Breakdown:"
    echo "  YAML Configs: $yaml_count"
    echo "  Environment Files: $env_count"
    echo "  Parameter Store: $param_count"
    echo "  Script Variables: $script_count"
    echo
    
    # Key files
    echo "Key Configuration Files:"
    jq -r '.sources.yaml_configs[] | "  - \(.path) (\(.variable_count) variables)"' "$discovery_report" 2>/dev/null || true
}

# Generate discovery table
generate_discovery_table() {
    local discovery_report="$1"
    
    echo "Configuration Sources"
    echo "===================="
    echo
    printf "%-30s %-10s %-15s %-20s\n" "FILE" "TYPE" "VARIABLES" "LAST MODIFIED"
    printf "%-30s %-10s %-15s %-20s\n" "----" "----" "---------" "-------------"
    
    # YAML configs
    jq -r '.sources.yaml_configs[] | "\(.path)\tyaml\t\(.variable_count)\t\(.last_modified)"' "$discovery_report" 2>/dev/null | \
        while IFS=$'\t' read -r path type vars modified; do
            printf "%-30s %-10s %-15s %-20s\n" "$path" "$type" "$vars" "$modified"
        done
    
    # Environment files
    jq -r '.sources.env_files[] | "\(.path)\tenv\t\(.variable_count)\t\(.last_modified)"' "$discovery_report" 2>/dev/null | \
        while IFS=$'\t' read -r path type vars modified; do
            printf "%-30s %-10s %-15s %-20s\n" "$path" "$type" "$vars" "$modified"
        done
}

# Generate validation summary
generate_validation_summary() {
    local validation_report="$1"
    
    echo "Configuration Validation Summary"
    echo "==============================="
    echo
    
    # Status
    local schema_valid=$(jq -r '.schema_valid' "$validation_report" 2>/dev/null || echo "false")
    local business_rules_valid=$(jq -r '.business_rules_valid' "$validation_report" 2>/dev/null || echo "false")
    
    echo "Schema Valid: $schema_valid"
    echo "Business Rules Valid: $business_rules_valid"
    echo
    
    # Counts
    local error_count=$(jq '.errors | length' "$validation_report" 2>/dev/null || echo "0")
    local warning_count=$(jq '.warnings | length' "$validation_report" 2>/dev/null || echo "0")
    
    echo "Errors: $error_count"
    echo "Warnings: $warning_count"
    echo
    
    # Show errors if any
    if [[ "$error_count" -gt "0" ]]; then
        echo "Errors:"
        jq -r '.errors[] | "  - [\(.category)] \(.message)"' "$validation_report" 2>/dev/null || true
        echo
    fi
    
    # Show warnings if any
    if [[ "$warning_count" -gt "0" ]]; then
        echo "Warnings:"
        jq -r '.warnings[] | "  - [\(.category)] \(.message)"' "$validation_report" 2>/dev/null || true
    fi
}

# Generate validation table
generate_validation_table() {
    local validation_report="$1"
    
    echo "Validation Results"
    echo "=================="
    echo
    
    # Errors table
    local error_count=$(jq '.errors | length' "$validation_report" 2>/dev/null || echo "0")
    if [[ "$error_count" -gt "0" ]]; then
        echo "ERRORS ($error_count):"
        printf "%-20s %-60s\n" "CATEGORY" "MESSAGE"
        printf "%-20s %-60s\n" "--------" "-------"
        
        jq -r '.errors[] | "\(.category)\t\(.message)"' "$validation_report" 2>/dev/null | \
            while IFS=$'\t' read -r category message; do
                printf "%-20s %-60s\n" "$category" "$message"
            done
        echo
    fi
    
    # Warnings table
    local warning_count=$(jq '.warnings | length' "$validation_report" 2>/dev/null || echo "0")
    if [[ "$warning_count" -gt "0" ]]; then
        echo "WARNINGS ($warning_count):"
        printf "%-20s %-60s\n" "CATEGORY" "MESSAGE"
        printf "%-20s %-60s\n" "--------" "-------"
        
        jq -r '.warnings[] | "\(.category)\t\(.message)"' "$validation_report" 2>/dev/null | \
            while IFS=$'\t' read -r category message; do
                printf "%-20s %-60s\n" "$category" "$message"
            done
    fi
}

# Show validation errors only
show_validation_errors_only() {
    local validation_report="$1"
    
    local error_count=$(jq '.errors | length' "$validation_report" 2>/dev/null || echo "0")
    if [[ "$error_count" -gt "0" ]]; then
        jq -r '.errors[] | "ERROR [\(.category)]: \(.message)"' "$validation_report" 2>/dev/null || true
    else
        echo "No validation errors found."
    fi
}

# Generate migration plan summary
generate_migration_plan_summary() {
    local migration_plan="$1"
    
    echo "Migration Plan Summary"
    echo "====================="
    echo
    
    local target_env=$(jq -r '.target_environment' "$migration_plan" 2>/dev/null || echo "unknown")
    local steps_count=$(jq '.migration_steps | length' "$migration_plan" 2>/dev/null || echo "0")
    local estimated_duration=$(jq -r '.estimated_duration' "$migration_plan" 2>/dev/null || echo "unknown")
    
    echo "Target Environment: $target_env"
    echo "Migration Steps: $steps_count"
    echo "Estimated Duration: $estimated_duration"
    echo
    
    echo "Migration Steps:"
    jq -r '.migration_steps[] | "  \(.name): \(.description)"' "$migration_plan" 2>/dev/null || true
    echo
    
    echo "Prerequisites:"
    jq -r '.prerequisites[] | "  - \(.)"' "$migration_plan" 2>/dev/null || true
}

# =============================================================================
# CLI HELP SYSTEM
# =============================================================================

# Show main help
show_help() {
    cat << EOF
$CLI_DESCRIPTION v$CLI_VERSION

USAGE:
  $CLI_NAME <command> [options]

COMMANDS:
  discover [format] [output_file]     Discover configuration sources
  validate <config_file> [format]    Validate configuration file
  plan <environment> [output_file]   Generate migration plan
  migrate <environment> [options]    Execute configuration migration
  backup [name]                      Create configuration backup
  restore <backup_name>              Restore configuration from backup
  list-backups                       List available backups
  status [details]                   Show migration status
  help                               Show this help message

DISCOVERY:
  $CLI_NAME discover                 # JSON output to stdout
  $CLI_NAME discover summary         # Human-readable summary
  $CLI_NAME discover table           # Tabular format
  $CLI_NAME discover json report.json  # Save to file

VALIDATION:
  $CLI_NAME validate                 # Validate defaults.yml
  $CLI_NAME validate config/unity.yml # Validate specific file
  $CLI_NAME validate config/unity.yml summary  # Summary format
  $CLI_NAME validate config/unity.yml errors-only  # Show errors only

MIGRATION PLANNING:
  $CLI_NAME plan development         # Generate plan for development
  $CLI_NAME plan production plan.json  # Save plan to file

MIGRATION EXECUTION:
  $CLI_NAME migrate development --dry-run  # Dry run
  $CLI_NAME migrate production --backup=pre_prod  # With backup
  $CLI_NAME migrate staging --force     # Skip confirmation

BACKUP MANAGEMENT:
  $CLI_NAME backup                   # Create backup with timestamp
  $CLI_NAME backup pre_migration     # Create named backup
  $CLI_NAME restore pre_migration    # Restore backup
  $CLI_NAME list-backups             # List all backups

OPTIONS:
  --dry-run                 Perform dry run without making changes
  --force                   Skip confirmation prompts
  --backup=<name>           Create backup before migration
  --debug                   Enable debug output
  --help, -h                Show help for specific command

ENVIRONMENT VARIABLES:
  CLI_DEBUG=true            Enable debug logging
  CONFIG_ROOT=<path>        Override config directory path
  VALIDATION_DEBUG=true     Enable validation debug output

EXAMPLES:
  # Discover all configuration sources
  $CLI_NAME discover summary

  # Validate current configuration
  $CLI_NAME validate config/defaults.yml

  # Plan migration to production
  $CLI_NAME plan production

  # Execute migration with backup
  $CLI_NAME migrate production --backup=pre_prod_migration

  # Create backup before making changes
  $CLI_NAME backup before_changes

  # Restore if something goes wrong
  $CLI_NAME restore before_changes

For more information, visit: https://github.com/your-org/geuse-maker
EOF
}

# Show command-specific help
show_command_help() {
    local command="$1"
    
    case "$command" in
        "discover")
            cat << EOF
DISCOVER COMMAND

Discover all configuration sources in the project.

USAGE:
  $CLI_NAME discover [format] [output_file]

FORMATS:
  json          JSON output (default)
  summary       Human-readable summary
  table         Tabular format

EXAMPLES:
  $CLI_NAME discover
  $CLI_NAME discover summary
  $CLI_NAME discover json sources.json
EOF
            ;;
        "validate")
            cat << EOF
VALIDATE COMMAND

Validate configuration files against business rules and schema.

USAGE:
  $CLI_NAME validate <config_file> [format] [output_file]

FORMATS:
  json          JSON report (default)
  summary       Human-readable summary
  table         Tabular format
  errors-only   Show only errors

EXAMPLES:
  $CLI_NAME validate config/defaults.yml
  $CLI_NAME validate config/unity.yml summary
  $CLI_NAME validate config/production.yml errors-only
EOF
            ;;
        "migrate")
            cat << EOF
MIGRATE COMMAND

Execute configuration migration to target environment.

USAGE:
  $CLI_NAME migrate <environment> [options]

OPTIONS:
  --dry-run             Perform dry run without changes
  --force               Skip confirmation prompts
  --backup=<name>       Create backup before migration

EXAMPLES:
  $CLI_NAME migrate development --dry-run
  $CLI_NAME migrate production --backup=pre_prod
  $CLI_NAME migrate staging --force
EOF
            ;;
        *)
            cli_error 100 "Unknown command: $command" "Use '$CLI_NAME help' for available commands"
            ;;
    esac
}

# =============================================================================
# MAIN CLI ENTRY POINT
# =============================================================================

main() {
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                export CLI_DEBUG=true
                export VALIDATION_DEBUG=true
                export CONFIG_MIGRATION_DEBUG=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "$CLI_NAME version $CLI_VERSION"
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Require at least one argument
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local command="$1"
    shift
    
    # Check prerequisites
    check_prerequisites
    
    # Load Unity services
    load_unity_services
    
    # Execute command
    case "$command" in
        "discover")
            cmd_discover "$@"
            ;;
        "validate")
            cmd_validate "$@"
            ;;
        "plan")
            cmd_plan "$@"
            ;;
        "migrate")
            # Parse migrate-specific options
            local environment=""
            local dry_run="false"
            local backup_name=""
            local force="false"
            
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --dry-run)
                        dry_run="true"
                        shift
                        ;;
                    --force)
                        force="true"
                        shift
                        ;;
                    --backup=*)
                        backup_name="${1#*=}"
                        shift
                        ;;
                    *)
                        if [[ -z "$environment" ]]; then
                            environment="$1"
                        fi
                        shift
                        ;;
                esac
            done
            
            cmd_migrate "$environment" "$dry_run" "$backup_name" "$force"
            ;;
        "backup")
            cmd_backup "$@"
            ;;
        "restore")
            cmd_restore "$@"
            ;;
        "list-backups")
            cmd_list_backups
            ;;
        "status")
            cmd_status "$@"
            ;;
        "help")
            if [[ $# -gt 0 ]]; then
                show_command_help "$1"
            else
                show_help
            fi
            ;;
        *)
            cli_error 99 "Unknown command: $command" "Use '$CLI_NAME help' for available commands"
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi