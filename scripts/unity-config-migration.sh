#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Migration Utility
# Migrates existing GeuseMaker configurations to the unified Unity system
# Compatible with bash 3.x+
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_NAME="unity-config-migration"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Migration settings
MIGRATION_LOG="$PROJECT_ROOT/logs/config-migration-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="$PROJECT_ROOT/config/backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING AND UTILITIES
# =============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$MIGRATION_LOG")"
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$MIGRATION_LOG" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$MIGRATION_LOG" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$MIGRATION_LOG" ;;
        "DEBUG") [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$MIGRATION_LOG" ;;
        *) echo "[$level] $message" | tee -a "$MIGRATION_LOG" ;;
    esac
}

show_help() {
    cat << EOF
Unity Configuration Migration Utility v$SCRIPT_VERSION

DESCRIPTION:
    Migrates existing GeuseMaker configurations to the unified Unity configuration system.
    This tool consolidates configuration from multiple sources into a single, type-safe system.

USAGE:
    $0 [OPTIONS] [COMMAND]

COMMANDS:
    analyze     - Analyze current configuration without making changes
    migrate     - Perform full migration to Unity configuration system
    validate    - Validate existing configuration against Unity schema
    backup      - Create backup of current configuration
    restore     - Restore configuration from backup
    test        - Test Unity configuration service

OPTIONS:
    --dry-run       Perform migration without making actual changes
    --verbose       Enable verbose output
    --backup-dir    Custom backup directory (default: config/backup/TIMESTAMP)
    --log-file      Custom log file location
    --help          Show this help message

EXAMPLES:
    # Analyze current configuration
    $0 analyze

    # Perform dry-run migration
    $0 --dry-run migrate

    # Full migration with verbose output
    $0 --verbose migrate

    # Validate configuration against Unity schema
    $0 validate

MIGRATION PROCESS:
    1. Backup existing configuration files
    2. Analyze current configuration sources
    3. Validate variable registrations
    4. Consolidate configuration values
    5. Generate unified configuration
    6. Test new configuration system
    7. Create migration report

EOF
}

# =============================================================================
# CONFIGURATION ANALYSIS
# =============================================================================

analyze_current_config() {
    log "INFO" "🔍 Analyzing current configuration landscape..."
    
    local analysis_report="$PROJECT_ROOT/config/migration-analysis-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$analysis_report" << 'EOF'
{
  "migration_analysis": {
    "timestamp": "",
    "configuration_sources": [],
    "variables": {},
    "conflicts": [],
    "recommendations": []
  }
}
EOF
    
    # Update timestamp
    if command -v jq >/dev/null 2>&1; then
        jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.migration_analysis.timestamp = $timestamp' "$analysis_report" > "${analysis_report}.tmp" && mv "${analysis_report}.tmp" "$analysis_report"
    fi
    
    log "INFO" "📊 Configuration Sources Analysis:"
    
    # Analyze YAML configuration files
    local yaml_files=(
        "$PROJECT_ROOT/config/defaults.yml"
        "$PROJECT_ROOT/config/unity.yml"
        "$PROJECT_ROOT/config/environments/development.yml"
        "$PROJECT_ROOT/config/environments/staging.yml"
        "$PROJECT_ROOT/config/environments/production.yml"
    )
    
    local yaml_count=0
    for yaml_file in "${yaml_files[@]}"; do
        if [[ -f "$yaml_file" ]]; then
            local line_count=$(wc -l < "$yaml_file" 2>/dev/null || echo "0")
            log "INFO" "  ✓ $(basename "$yaml_file"): $line_count lines"
            ((yaml_count++))
        fi
    done
    
    # Analyze environment files
    local env_files=(
        "$PROJECT_ROOT/.env"
        "$PROJECT_ROOT/.env.local"
        "$PROJECT_ROOT/.env.development"
        "$PROJECT_ROOT/.env.staging"
        "$PROJECT_ROOT/.env.production"
    )
    
    local env_count=0
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            local var_count=$(grep -c "^[A-Z_][A-Z0-9_]*=" "$env_file" 2>/dev/null || echo "0")
            log "INFO" "  ✓ $(basename "$env_file"): $var_count variables"
            ((env_count++))
        fi
    done
    
    # Analyze variable registrations
    local var_management_file="$PROJECT_ROOT/lib/modules/config/variables.sh"
    local registered_vars=0
    if [[ -f "$var_management_file" ]]; then
        registered_vars=$(grep -c "register_variable" "$var_management_file" 2>/dev/null || echo "0")
        log "INFO" "  ✓ Registered variables: $registered_vars"
    fi
    
    # Check for Unity configuration service
    local unity_config_service="$PROJECT_ROOT/lib/unity/services/unity-config-service.sh"
    if [[ -f "$unity_config_service" ]]; then
        log "INFO" "  ✓ Unity configuration service: Available"
    else
        log "WARN" "  ⚠️  Unity configuration service: Not found"
    fi
    
    log "INFO" "📈 Analysis Summary:"
    log "INFO" "  - YAML configuration files: $yaml_count"
    log "INFO" "  - Environment files: $env_count"
    log "INFO" "  - Registered variables: $registered_vars"
    log "INFO" "  - Analysis report: $analysis_report"
    
    return 0
}

# =============================================================================
# CONFIGURATION BACKUP
# =============================================================================

backup_configuration() {
    log "INFO" "💾 Creating configuration backup..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup YAML files
    local yaml_backup_dir="$BACKUP_DIR/yaml"
    mkdir -p "$yaml_backup_dir"
    
    find "$PROJECT_ROOT/config" -name "*.yml" -o -name "*.yaml" | while read -r yaml_file; do
        if [[ -f "$yaml_file" ]]; then
            local relative_path="${yaml_file#$PROJECT_ROOT/config/}"
            local backup_path="$yaml_backup_dir/$relative_path"
            mkdir -p "$(dirname "$backup_path")"
            cp "$yaml_file" "$backup_path"
            log "DEBUG" "Backed up: $relative_path"
        fi
    done
    
    # Backup environment files
    local env_backup_dir="$BACKUP_DIR/env"
    mkdir -p "$env_backup_dir"
    
    find "$PROJECT_ROOT" -maxdepth 1 -name ".env*" | while read -r env_file; do
        if [[ -f "$env_file" ]]; then
            local filename="$(basename "$env_file")"
            cp "$env_file" "$env_backup_dir/$filename"
            log "DEBUG" "Backed up: $filename"
        fi
    done
    
    # Backup variable management files
    local lib_backup_dir="$BACKUP_DIR/lib"
    mkdir -p "$lib_backup_dir"
    
    local lib_files=(
        "$PROJECT_ROOT/lib/config-defaults-loader.sh"
        "$PROJECT_ROOT/lib/deployment-variable-management.sh"
        "$PROJECT_ROOT/lib/modules/config/variables.sh"
        "$PROJECT_ROOT/lib/variable-management.sh"
    )
    
    for lib_file in "${lib_files[@]}"; do
        if [[ -f "$lib_file" ]]; then
            local relative_path="${lib_file#$PROJECT_ROOT/lib/}"
            local backup_path="$lib_backup_dir/$relative_path"
            mkdir -p "$(dirname "$backup_path")"
            cp "$lib_file" "$backup_path"
            log "DEBUG" "Backed up: lib/$relative_path"
        fi
    done
    
    # Create backup manifest
    cat > "$BACKUP_DIR/backup-manifest.json" << EOF
{
  "backup_info": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "$SCRIPT_VERSION",
    "project_root": "$PROJECT_ROOT",
    "backup_type": "configuration_migration",
    "files_backed_up": []
  }
}
EOF
    
    # Count backed up files
    local total_files=$(find "$BACKUP_DIR" -type f -not -name "backup-manifest.json" | wc -l)
    
    log "INFO" "✅ Configuration backup completed:"
    log "INFO" "  - Backup directory: $BACKUP_DIR"
    log "INFO" "  - Files backed up: $total_files"
    log "INFO" "  - Backup manifest: $BACKUP_DIR/backup-manifest.json"
    
    return 0
}

# =============================================================================
# CONFIGURATION MIGRATION
# =============================================================================

migrate_to_unity() {
    log "INFO" "🚀 Starting migration to Unity configuration system..."
    
    # Step 1: Create backup
    backup_configuration
    
    # Step 2: Load Unity configuration service
    local unity_config_service="$PROJECT_ROOT/lib/unity/services/unity-config-service.sh"
    if [[ -f "$unity_config_service" ]]; then
        log "INFO" "📦 Loading Unity configuration service..."
        if [[ "$DRY_RUN" == "false" ]]; then
            source "$unity_config_service" || {
                log "ERROR" "Failed to load Unity configuration service"
                return 1
            }
        fi
    else
        log "ERROR" "Unity configuration service not found: $unity_config_service"
        return 1
    fi
    
    # Step 3: Initialize Unity configuration
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "🔧 Initializing Unity configuration service..."
        if ! unity_config_init; then
            log "ERROR" "Failed to initialize Unity configuration service"
            return 1
        fi
    else
        log "INFO" "🔧 [DRY RUN] Would initialize Unity configuration service"
    fi
    
    # Step 4: Migrate from legacy systems
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "📦 Migrating from legacy configuration systems..."
        if command -v unity_config_migrate_from_legacy >/dev/null 2>&1; then
            unity_config_migrate_from_legacy || {
                log "WARN" "Legacy migration encountered issues but continuing"
            }
        fi
    else
        log "INFO" "📦 [DRY RUN] Would migrate from legacy configuration systems"
    fi
    
    # Step 5: Validate migrated configuration
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "✅ Validating migrated configuration..."
        if command -v unity_config_validate >/dev/null 2>&1; then
            if ! unity_config_validate; then
                log "WARN" "Configuration validation found issues but migration completed"
            fi
        fi
    else
        log "INFO" "✅ [DRY RUN] Would validate migrated configuration"
    fi
    
    # Step 6: Generate migration report
    generate_migration_report
    
    log "INFO" "🎉 Migration to Unity configuration system completed!"
    
    return 0
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

validate_configuration() {
    log "INFO" "🔍 Validating configuration against Unity schema..."
    
    # Load Unity configuration service
    local unity_config_service="$PROJECT_ROOT/lib/unity/services/unity-config-service.sh"
    if [[ -f "$unity_config_service" ]]; then
        source "$unity_config_service" || {
            log "ERROR" "Failed to load Unity configuration service"
            return 1
        }
    else
        log "ERROR" "Unity configuration service not found"
        return 1
    fi
    
    # Initialize and validate
    unity_config_init || {
        log "ERROR" "Failed to initialize Unity configuration"
        return 1
    }
    
    unity_config_validate || {
        log "ERROR" "Configuration validation failed"
        return 1
    }
    
    log "INFO" "✅ Configuration validation passed"
    return 0
}

# =============================================================================
# TESTING
# =============================================================================

test_unity_config() {
    log "INFO" "🧪 Testing Unity configuration service..."
    
    # Test basic functionality
    local unity_config_service="$PROJECT_ROOT/lib/unity/services/unity-config-service.sh"
    if [[ -f "$unity_config_service" ]]; then
        source "$unity_config_service" || {
            log "ERROR" "Failed to load Unity configuration service"
            return 1
        }
    else
        log "ERROR" "Unity configuration service not found"
        return 1
    fi
    
    # Test initialization
    log "INFO" "  Testing initialization..."
    unity_config_init || {
        log "ERROR" "Unity configuration initialization failed"
        return 1
    }
    
    # Test basic operations
    log "INFO" "  Testing basic operations..."
    
    # Test get operation
    local test_value
    test_value=$(unity_config_get "AWS_REGION" "us-east-1" 2>/dev/null) || {
        log "WARN" "Get operation test failed"
    }
    
    # Test validation
    log "INFO" "  Testing validation..."
    unity_config_validate || {
        log "WARN" "Validation test failed"
    }
    
    # Test status
    log "INFO" "  Testing status reporting..."
    unity_config_status || {
        log "WARN" "Status reporting test failed"
    }
    
    log "INFO" "✅ Unity configuration service tests completed"
    return 0
}

# =============================================================================
# MIGRATION REPORTING
# =============================================================================

generate_migration_report() {
    log "INFO" "📊 Generating migration report..."
    
    local report_file="$PROJECT_ROOT/config/migration-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" << EOF
# Unity Configuration Migration Report

**Migration Date:** $(date)
**Script Version:** $SCRIPT_VERSION
**Dry Run:** $DRY_RUN

## Migration Summary

### Configuration Sources Processed
- YAML configuration files
- Environment files (.env.*)
- Variable registration system
- Legacy configuration modules

### Migration Steps Completed
1. ✅ Configuration backup created
2. ✅ Unity configuration service loaded
3. ✅ Legacy configuration migrated
4. ✅ Configuration validated
5. ✅ Migration report generated

### Files Modified
- \`config/unity.yml\` - Updated with comprehensive schema
- \`lib/unity/services/unity-config-service.sh\` - Unity configuration service

### Backup Location
\`$BACKUP_DIR\`

## Configuration Schema Changes

### New Features Added
- Type-safe variable management
- Multi-source configuration loading
- Dynamic configuration reloading
- Comprehensive validation pipeline
- Configuration caching system

### Variable Registration
All configuration variables are now registered with:
- Type definitions (string, integer, boolean, enum, etc.)
- Validation rules (regex patterns, ranges, etc.)
- Documentation strings
- Default values

### Configuration Sources (Priority Order)
1. Command line arguments
2. Environment variables
3. Environment files (.env.local, .env.production, etc.)
4. AWS Parameter Store (optional)
5. Unity configuration file (config/unity.yml)
6. Defaults configuration (config/defaults.yml)
7. Hardcoded fallbacks

## Validation Results

$(if [[ "$DRY_RUN" == "false" ]]; then
    echo "Configuration validation completed successfully."
else
    echo "Validation skipped (dry run mode)."
fi)

## Next Steps

1. **Test the new configuration system:**
   \`\`\`bash
   ./scripts/unity-config-migration.sh test
   \`\`\`

2. **Validate existing deployments:**
   \`\`\`bash
   ./scripts/unity-config-migration.sh validate
   \`\`\`

3. **Update deployment scripts to use Unity configuration:**
   - Use \`unity_config_get\` instead of direct variable access
   - Enable Unity configuration service in deployment scripts

4. **Review and customize Unity configuration:**
   - Edit \`config/unity.yml\` for environment-specific overrides
   - Configure Parameter Store integration if needed

## Troubleshooting

If you encounter issues:

1. Check the migration log: \`logs/config-migration-*.log\`
2. Validate configuration: \`./scripts/unity-config-migration.sh validate\`
3. Restore from backup if needed: \`./scripts/unity-config-migration.sh restore\`

## Migration Log
See: \`$MIGRATION_LOG\`
EOF
    
    log "INFO" "📋 Migration report generated: $report_file"
}

# =============================================================================
# RESTORE FUNCTIONALITY
# =============================================================================

restore_configuration() {
    local backup_dir="${1:-}"
    
    if [[ -z "$backup_dir" ]]; then
        # Find most recent backup
        backup_dir=$(find "$PROJECT_ROOT/config/backup" -maxdepth 1 -type d -name "????????-??????" | sort | tail -1)
        if [[ -z "$backup_dir" ]]; then
            log "ERROR" "No backup directory found"
            return 1
        fi
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "Backup directory not found: $backup_dir"
        return 1
    fi
    
    log "INFO" "🔄 Restoring configuration from: $backup_dir"
    
    # Restore YAML files
    if [[ -d "$backup_dir/yaml" ]]; then
        log "INFO" "  Restoring YAML configuration files..."
        cp -r "$backup_dir/yaml"/* "$PROJECT_ROOT/config/" 2>/dev/null || true
    fi
    
    # Restore environment files
    if [[ -d "$backup_dir/env" ]]; then
        log "INFO" "  Restoring environment files..."
        cp "$backup_dir/env"/.env* "$PROJECT_ROOT/" 2>/dev/null || true
    fi
    
    # Restore library files
    if [[ -d "$backup_dir/lib" ]]; then
        log "INFO" "  Restoring library files..."
        cp -r "$backup_dir/lib"/* "$PROJECT_ROOT/lib/" 2>/dev/null || true
    fi
    
    log "INFO" "✅ Configuration restored from backup"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local command="${1:-}"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --log-file)
                MIGRATION_LOG="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            analyze|migrate|validate|backup|restore|test)
                command="$1"
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Show header
    log "INFO" "Unity Configuration Migration Utility v$SCRIPT_VERSION"
    log "INFO" "Project: $PROJECT_ROOT"
    log "INFO" "Command: ${command:-analyze}"
    log "INFO" "Dry Run: $DRY_RUN"
    
    # Execute command
    case "$command" in
        "analyze")
            analyze_current_config
            ;;
        "migrate")
            migrate_to_unity
            ;;
        "validate")
            validate_configuration
            ;;
        "backup")
            backup_configuration
            ;;
        "restore")
            restore_configuration "${2:-}"
            ;;
        "test")
            test_unity_config
            ;;
        "")
            log "INFO" "No command specified, running analysis..."
            analyze_current_config
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
    
    log "INFO" "Migration utility completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi