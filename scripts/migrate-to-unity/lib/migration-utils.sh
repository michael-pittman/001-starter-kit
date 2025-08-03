#!/bin/bash
# Migration utilities - Shared functions for migrating legacy code to Unity

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Migration log file
MIGRATION_LOG="$PROJECT_ROOT/logs/unity/migration-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$MIGRATION_LOG")"

# Log migration activity
log_migration() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] [$level] $message" >> "$MIGRATION_LOG"
    
    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
    esac
}

# Check if a file contains legacy patterns
check_legacy_patterns() {
    local file="$1"
    local patterns=(
        "source.*lib/modules"
        "MODULES_DIR"
        "load_module"
        "validate_bash_version"
        "check_bash_version"
        "BASH_VERSION_REQUIRED"
    )
    
    for pattern in "${patterns[@]}"; do
        if grep -q "$pattern" "$file" 2>/dev/null; then
            return 0  # Found legacy pattern
        fi
    done
    
    return 1  # No legacy patterns found
}

# Extract functions from a legacy module
extract_functions() {
    local module_file="$1"
    local output_file="$2"
    
    log_migration "INFO" "Extracting functions from: $module_file"
    
    # Use awk to extract function definitions
    awk '
    /^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)/ ||
    /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)/ {
        in_function = 1
        print
        next
    }
    in_function && /^}[[:space:]]*$/ {
        print
        in_function = 0
        next
    }
    in_function {
        print
    }
    ' "$module_file" > "$output_file"
    
    log_migration "INFO" "Extracted functions to: $output_file"
}

# Convert legacy function to Unity pattern
convert_to_unity_function() {
    local function_name="$1"
    local service_name="$2"
    local function_body="$3"
    
    # Unity function naming convention
    local unity_function_name="${function_name}_${service_name}"
    
    # Replace common legacy patterns
    local converted_body=$(echo "$function_body" | sed \
        -e 's/log_error/unity_log "ERROR"/g' \
        -e 's/log_info/unity_log "INFO"/g' \
        -e 's/log_warning/unity_log "WARN"/g' \
        -e 's/check_command/command -v/g' \
        -e 's/\$SCRIPT_DIR\/\.\./\$PROJECT_ROOT/g')
    
    echo "$unity_function_name() {
$converted_body
}"
}

# Create Unity service from legacy module
create_unity_service() {
    local module_name="$1"
    local module_file="$2"
    local service_file="$3"
    
    log_migration "INFO" "Creating Unity service from: $module_name"
    
    # Service header
    cat > "$service_file" << 'EOF'
#!/bin/bash
# Unity Service - Auto-migrated from legacy module
# Generated on: $(date)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || {
    echo "Error: Failed to load Unity core" >&2
    exit 1
}

# Service metadata
SERVICE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
SERVICE_VERSION="1.0.0"
SERVICE_TYPE="migrated"

EOF

    # Add initialization function
    cat >> "$service_file" << EOF
# Initialize service
init_${module_name}_service() {
    unity_log "INFO" "Initializing $module_name service (migrated)"
    
    # Service-specific initialization
    return 0
}

# Start service
start_${module_name}_service() {
    unity_log "INFO" "Starting $module_name service"
    
    # Update service status
    unity_set_service_status "$SERVICE_NAME" "running"
    
    return 0
}

# Stop service
stop_${module_name}_service() {
    unity_log "INFO" "Stopping $module_name service"
    
    # Update service status
    unity_set_service_status "$SERVICE_NAME" "stopped"
    
    return 0
}

# Health check
health_${module_name}_service() {
    # Basic health check
    echo "healthy|Service is operational"
    return 0
}

# Configuration management
config_${module_name}_service() {
    local action="\${1:-get}"
    local key="\${2:-}"
    local value="\${3:-}"
    
    case "\$action" in
        get)
            # Get configuration
            ;;
        set)
            # Set configuration
            ;;
        reload)
            # Reload configuration
            ;;
    esac
    
    return 0
}

EOF

    # Extract and convert functions from legacy module
    local temp_functions=$(mktemp)
    extract_functions "$module_file" "$temp_functions"
    
    # Add converted functions
    echo "# Migrated functions from legacy module" >> "$service_file"
    cat "$temp_functions" >> "$service_file"
    
    rm -f "$temp_functions"
    
    # Add export statements
    echo "" >> "$service_file"
    echo "# Export service functions" >> "$service_file"
    echo "export -f init_${module_name}_service" >> "$service_file"
    echo "export -f start_${module_name}_service" >> "$service_file"
    echo "export -f stop_${module_name}_service" >> "$service_file"
    echo "export -f health_${module_name}_service" >> "$service_file"
    echo "export -f config_${module_name}_service" >> "$service_file"
    
    log_migration "SUCCESS" "Created Unity service: $service_file"
}

# Validate migrated service
validate_unity_service() {
    local service_file="$1"
    local errors=0
    
    log_migration "INFO" "Validating Unity service: $service_file"
    
    # Check required functions
    local required_functions=(
        "init_.*_service"
        "start_.*_service"
        "stop_.*_service"
        "health_.*_service"
        "config_.*_service"
    )
    
    for func_pattern in "${required_functions[@]}"; do
        if ! grep -q "^${func_pattern}()" "$service_file"; then
            log_migration "ERROR" "Missing required function pattern: $func_pattern"
            ((errors++))
        fi
    done
    
    # Check for Unity core sourcing
    if ! grep -q "source.*unity-core.sh" "$service_file"; then
        log_migration "ERROR" "Service does not source Unity core"
        ((errors++))
    fi
    
    # Check syntax
    if ! bash -n "$service_file" 2>/dev/null; then
        log_migration "ERROR" "Service has syntax errors"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_migration "SUCCESS" "Service validation passed"
        return 0
    else
        log_migration "ERROR" "Service validation failed with $errors errors"
        return 1
    fi
}

# Create migration backup
create_migration_backup() {
    local source_file="$1"
    local backup_dir="$PROJECT_ROOT/archive/unity-migration-backup-$(date +%Y%m%d-%H%M%S)"
    
    mkdir -p "$backup_dir"
    
    local relative_path="${source_file#$PROJECT_ROOT/}"
    local backup_file="$backup_dir/$relative_path"
    
    mkdir -p "$(dirname "$backup_file")"
    cp "$source_file" "$backup_file"
    
    log_migration "INFO" "Created backup: $backup_file"
    echo "$backup_file"
}

# Update references to legacy module
update_legacy_references() {
    local old_path="$1"
    local new_path="$2"
    local search_dir="${3:-$PROJECT_ROOT}"
    
    log_migration "INFO" "Updating references from $old_path to $new_path"
    
    # Find all shell scripts that might reference the old path
    find "$search_dir" -name "*.sh" -type f | while read -r file; do
        if grep -q "$old_path" "$file" 2>/dev/null; then
            # Create backup
            create_migration_backup "$file" >/dev/null
            
            # Update references
            sed -i.bak "s|$old_path|$new_path|g" "$file"
            rm -f "${file}.bak"
            
            log_migration "INFO" "Updated references in: $file"
        fi
    done
}

# Generate migration report
generate_migration_report() {
    local module_name="$1"
    local status="$2"
    local details="$3"
    local report_file="$PROJECT_ROOT/logs/unity/migration-report-$(date +%Y%m%d-%H%M%S).json"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "module": "$module_name",
    "status": "$status",
    "details": "$details",
    "migration_log": "$MIGRATION_LOG"
}
EOF
    
    log_migration "INFO" "Migration report generated: $report_file"
}

# Export utilities
export -f log_migration
export -f check_legacy_patterns
export -f extract_functions
export -f convert_to_unity_function
export -f create_unity_service
export -f validate_unity_service
export -f create_migration_backup
export -f update_legacy_references
export -f generate_migration_report