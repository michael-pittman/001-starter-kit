#!/bin/bash
# Master migration script - Orchestrates migration of all legacy components to Unity

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source migration utilities
source "$SCRIPT_DIR/lib/migration-utils.sh"

# Migration status tracking
MIGRATION_SUMMARY="$PROJECT_ROOT/logs/unity/migration-summary-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$(dirname "$MIGRATION_SUMMARY")"

# Track migration progress
TOTAL_MODULES=0
MIGRATED_MODULES=0
FAILED_MODULES=0

# Print banner
print_banner() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Unity Migration Tool - Legacy to Unity              ║"
    echo "║                  Automated Migration System                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [options]

Options:
  --dry-run          Show what would be migrated without making changes
  --module MODULE    Migrate specific module only
  --skip-backup      Skip creating backups (not recommended)
  --force            Force migration even if validation fails
  --help, -h         Show this help message

Examples:
  $0                      # Migrate all legacy modules
  $0 --dry-run           # Preview migration without changes
  $0 --module vpc        # Migrate only VPC module

EOF
}

# Parse arguments
DRY_RUN=false
SPECIFIC_MODULE=""
SKIP_BACKUP=false
FORCE_MIGRATION=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --module)
            SPECIFIC_MODULE="$2"
            shift 2
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --force)
            FORCE_MIGRATION=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Find legacy modules to migrate
find_legacy_modules() {
    local legacy_base="$PROJECT_ROOT/archive/unity-cleanup-20250803_024204/original-files/lib/modules"
    local modules=()
    
    if [[ -d "$legacy_base" ]]; then
        # Find all module directories
        for module_dir in "$legacy_base"/*; do
            if [[ -d "$module_dir" ]]; then
                local module_name=$(basename "$module_dir")
                
                # Find .sh files in the module directory
                for module_file in "$module_dir"/*.sh; do
                    if [[ -f "$module_file" ]]; then
                        modules+=("$module_name:$module_file")
                    fi
                done
            fi
        done
    fi
    
    echo "${modules[@]}"
}

# Migrate individual module
migrate_module() {
    local module_info="$1"
    local module_name="${module_info%%:*}"
    local module_file="${module_info#*:}"
    local module_basename=$(basename "$module_file" .sh)
    
    ((TOTAL_MODULES++))
    
    log_migration "INFO" "Starting migration of module: $module_name/$module_basename"
    echo "Module: $module_name/$module_basename" >> "$MIGRATION_SUMMARY"
    
    # Determine target service name
    local service_name=""
    case "$module_name" in
        infrastructure)
            case "$module_basename" in
                vpc|alb|cloudfront|efs)
                    service_name="aws"
                    ;;
                *)
                    service_name="infrastructure"
                    ;;
            esac
            ;;
        compute)
            service_name="aws"
            ;;
        application)
            service_name="docker"
            ;;
        monitoring)
            service_name="monitor"
            ;;
        config)
            service_name="config"
            ;;
        *)
            service_name="$module_name"
            ;;
    esac
    
    # Target path for migrated functionality
    local target_service="$PROJECT_ROOT/lib/unity/services/unity-${service_name}-service.sh"
    local migration_staging="$PROJECT_ROOT/.unity/migration/staging/${service_name}-${module_basename}.sh"
    
    mkdir -p "$(dirname "$migration_staging")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_migration "INFO" "[DRY RUN] Would migrate $module_file to $target_service"
        echo "  Status: DRY RUN" >> "$MIGRATION_SUMMARY"
        ((MIGRATED_MODULES++))
        return 0
    fi
    
    # Create backup if not skipped
    if [[ "$SKIP_BACKUP" != "true" ]]; then
        create_migration_backup "$module_file" >/dev/null
    fi
    
    # Extract and convert functions
    log_migration "INFO" "Extracting functions from $module_file"
    
    # Create temporary migration file
    cat > "$migration_staging" << EOF
# Migrated from: $module_file
# Migration date: $(date)
# Module: $module_name/$module_basename

EOF
    
    # Extract functions and convert them
    local temp_functions=$(mktemp)
    extract_functions "$module_file" "$temp_functions"
    
    # Process each function
    while IFS= read -r line; do
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\(\) ]]; then
            local func_name="${BASH_REMATCH[1]}"
            
            # Skip internal/helper functions
            if [[ "$func_name" =~ ^_ ]]; then
                continue
            fi
            
            # Convert function name to Unity pattern
            local unity_func_name="${func_name}_unity"
            
            # Add function with Unity patterns
            echo "" >> "$migration_staging"
            echo "# Migrated from: $func_name" >> "$migration_staging"
            echo "${unity_func_name}() {" >> "$migration_staging"
            echo "    # Original implementation from $module_basename" >> "$migration_staging"
        else
            # Replace legacy patterns with Unity equivalents
            echo "$line" | sed \
                -e 's/log_error/unity_log "ERROR"/g' \
                -e 's/log_info/unity_log "INFO"/g' \
                -e 's/log_warn/unity_log "WARN"/g' \
                -e 's/\$MODULES_DIR/\$UNITY_SERVICES_DIR/g' \
                -e 's/load_module/unity_initialize_service/g' \
                >> "$migration_staging"
        fi
    done < "$temp_functions"
    
    rm -f "$temp_functions"
    
    # Validate the migrated code
    if bash -n "$migration_staging" 2>/dev/null || [[ "$FORCE_MIGRATION" == "true" ]]; then
        log_migration "SUCCESS" "Migration staging completed: $migration_staging"
        echo "  Status: STAGED" >> "$MIGRATION_SUMMARY"
        echo "  Staging: $migration_staging" >> "$MIGRATION_SUMMARY"
        ((MIGRATED_MODULES++))
        
        # If targeting an existing service, append the functions
        if [[ -f "$target_service" ]]; then
            echo "" >> "$target_service"
            echo "# === Migrated from $module_name/$module_basename ===" >> "$target_service"
            cat "$migration_staging" >> "$target_service"
            log_migration "SUCCESS" "Appended to existing service: $target_service"
        else
            log_migration "INFO" "Target service does not exist yet: $target_service"
            log_migration "INFO" "Staged migration can be manually integrated"
        fi
    else
        log_migration "ERROR" "Migration validation failed for $module_file"
        echo "  Status: FAILED" >> "$MIGRATION_SUMMARY"
        ((FAILED_MODULES++))
    fi
    
    echo "" >> "$MIGRATION_SUMMARY"
}

# Run specific module migrations
run_module_migrations() {
    # Run individual migration scripts if they exist
    local migration_scripts=(
        "migrate-vpc-module.sh"
        "migrate-ec2-module.sh"
        "migrate-alb-module.sh"
        "migrate-monitoring.sh"
        "migrate-config.sh"
    )
    
    for script in "${migration_scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            log_migration "INFO" "Running migration script: $script"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_migration "INFO" "[DRY RUN] Would execute: $script_path"
            else
                if "$script_path"; then
                    log_migration "SUCCESS" "Completed: $script"
                else
                    log_migration "ERROR" "Failed: $script"
                fi
            fi
        fi
    done
}

# Generate final migration report
generate_final_report() {
    local report_file="$PROJECT_ROOT/logs/unity/migration-final-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" << EOF
# Unity Migration Report

Generated: $(date)

## Summary

- Total Modules: $TOTAL_MODULES
- Successfully Migrated: $MIGRATED_MODULES
- Failed Migrations: $FAILED_MODULES
- Success Rate: $(( TOTAL_MODULES > 0 ? MIGRATED_MODULES * 100 / TOTAL_MODULES : 0 ))%

## Migration Details

$(cat "$MIGRATION_SUMMARY")

## Next Steps

1. Review staged migrations in: $PROJECT_ROOT/.unity/migration/staging/
2. Test migrated services: ./tests/unity/test-unity-complete-system.sh
3. Update service registrations in deploy.sh
4. Remove legacy code after validation

## Migration Logs

- Summary: $MIGRATION_SUMMARY
- Detailed Log: $MIGRATION_LOG

EOF
    
    log_migration "INFO" "Final migration report: $report_file"
    
    # Display summary
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Migration Complete!"
    echo "═══════════════════════════════════════════════════════════"
    echo "Total Modules: $TOTAL_MODULES"
    echo "Migrated: $MIGRATED_MODULES"
    echo "Failed: $FAILED_MODULES"
    echo ""
    echo "See full report: $report_file"
}

# Main execution
main() {
    print_banner
    
    log_migration "INFO" "Starting Unity migration process"
    echo "Migration started at: $(date)" > "$MIGRATION_SUMMARY"
    echo "Options: dry_run=$DRY_RUN, skip_backup=$SKIP_BACKUP, force=$FORCE_MIGRATION" >> "$MIGRATION_SUMMARY"
    echo "" >> "$MIGRATION_SUMMARY"
    
    # Find modules to migrate
    local modules=($(find_legacy_modules))
    
    if [[ ${#modules[@]} -eq 0 ]]; then
        log_migration "WARN" "No legacy modules found to migrate"
        exit 0
    fi
    
    log_migration "INFO" "Found ${#modules[@]} modules to migrate"
    
    # Filter by specific module if requested
    if [[ -n "$SPECIFIC_MODULE" ]]; then
        local filtered_modules=()
        for module in "${modules[@]}"; do
            if [[ "$module" =~ ^$SPECIFIC_MODULE: ]]; then
                filtered_modules+=("$module")
            fi
        done
        modules=("${filtered_modules[@]}")
        
        if [[ ${#modules[@]} -eq 0 ]]; then
            log_migration "ERROR" "No modules found matching: $SPECIFIC_MODULE"
            exit 1
        fi
    fi
    
    # Migrate each module
    for module in "${modules[@]}"; do
        migrate_module "$module"
    done
    
    # Run specific migration scripts
    run_module_migrations
    
    # Generate final report
    generate_final_report
}

# Run main
main