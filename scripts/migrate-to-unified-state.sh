#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Migration Script: Unified State Management
# Migrates from old state management systems to the unified system
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Statistics
FILES_ANALYZED=0
FILES_MIGRATED=0
STATE_FILES_MIGRATED=0

# Find files using old state management
find_files_to_migrate() {
    log_info "Scanning for files using old state management systems..."
    
    local files=()
    local patterns=(
        "deployment-state-manager\.sh"
        "enhanced-deployment-state\.sh"
        "deployment-state-json-helpers\.sh"
        "deployment-state-monitoring\.sh"
        "deployment-state-sync\.sh"
        "modules/deployment/state\.sh"
    )
    
    for pattern in "${patterns[@]}"; do
        while IFS= read -r file; do
            if grep -q "$pattern" "$file" 2>/dev/null; then
                files+=("$file")
            fi
        done < <(find "$PROJECT_ROOT" -name "*.sh" -type f \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*" \
            -not -path "*/archive/*")
    done
    
    # Remove duplicates
    printf '%s\n' "${files[@]}" | sort -u
}

# Create compatibility wrappers
create_state_compatibility_wrapper() {
    local wrapper_file="$PROJECT_ROOT/lib/state-compatibility.sh"
    
    log_step "Creating state management compatibility wrapper..."
    
    cat > "$wrapper_file" << 'EOF'
#!/usr/bin/env bash
# State Management Compatibility Wrapper
# Provides backward compatibility for old state management functions

# Source unified state manager
source "$(dirname "${BASH_SOURCE[0]}")/unified-state-manager.sh"

# =============================================================================
# COMPATIBILITY ALIASES AND FUNCTIONS
# =============================================================================

# deployment-state-manager.sh compatibility
init_deployment_state() {
    init_state_management "$@"
}

start_deployment() {
    local deployment_id="$1"
    CURRENT_DEPLOYMENT_ID="$deployment_id"
    transition_phase "$PHASE_PREPARING"
}

update_deployment_phase() {
    local phase="$1"
    transition_phase "$phase"
}

get_deployment_status() {
    get_current_phase
}

# enhanced-deployment-state.sh compatibility
load_deployment_state() {
    # No-op - state is loaded automatically
    return 0
}

save_deployment_state() {
    # No-op - state is saved automatically
    return 0
}

backup_deployment_state() {
    create_state_backup "$(get_state_file_path)"
}

# State getters/setters compatibility
get_stack_state() {
    local stack="$1"
    local key="$2"
    CURRENT_STACK_NAME="$stack" get_state "$key" "$STATE_SCOPE_STACK"
}

set_stack_state() {
    local stack="$1"
    local key="$2"
    local value="$3"
    CURRENT_STACK_NAME="$stack" set_state "$key" "$value" "$STATE_SCOPE_STACK"
}

update_resource_state() {
    local resource="$1"
    local key="$2"
    local value="$3"
    set_state "$key" "$value" "$STATE_SCOPE_RESOURCE" "$resource"
}

# deployment-state-json-helpers.sh compatibility
export_deployment_to_json() {
    get_state_summary "$@"
}

import_deployment_from_json() {
    log_warning "import_deployment_from_json is deprecated - use restore functionality"
    return 0
}

# Export compatibility functions
export -f init_deployment_state
export -f start_deployment
export -f update_deployment_phase
export -f get_deployment_status
export -f load_deployment_state
export -f save_deployment_state
export -f backup_deployment_state
export -f get_stack_state
export -f set_stack_state
export -f update_resource_state
export -f export_deployment_to_json
export -f import_deployment_from_json
EOF
    
    chmod +x "$wrapper_file"
    log_info "Created compatibility wrapper: $wrapper_file"
}

# Migrate a single file
migrate_file() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    ((FILES_ANALYZED++))
    
    log_step "Processing: $file"
    
    # Create backup
    cp "$file" "$backup_file"
    
    # Track if file was modified
    local modified=false
    
    # Replace old state management imports with unified system
    if grep -q 'deployment-state-manager\.sh\|enhanced-deployment-state\.sh' "$file"; then
        # Replace with unified system
        sed -i.tmp 's|source.*deployment-state-manager\.sh|source "${LIB_DIR}/unified-state-manager.sh"|g' "$file"
        sed -i.tmp 's|source.*enhanced-deployment-state\.sh|source "${LIB_DIR}/unified-state-manager.sh"|g' "$file"
        sed -i.tmp 's|source.*deployment-state-json-helpers\.sh|# JSON helpers now integrated in unified-state-manager.sh|g' "$file"
        modified=true
    fi
    
    # Replace function calls
    local replacements=(
        "s/init_deployment_state/init_state_management/g"
        "s/start_deployment_phase/transition_phase/g"
        "s/get_deployment_phase/get_current_phase/g"
        "s/update_deployment_status/set_state/g"
    )
    
    for replacement in "${replacements[@]}"; do
        if grep -q "$(echo "$replacement" | cut -d'/' -f2)" "$file" 2>/dev/null; then
            sed -i.tmp "$replacement" "$file"
            modified=true
        fi
    done
    
    # Clean up temp files
    rm -f "${file}.tmp"
    
    if [[ "$modified" == "true" ]]; then
        ((FILES_MIGRATED++))
        log_info "Migrated: $file"
        
        # Validate syntax
        if ! bash -n "$file" 2>/dev/null; then
            log_error "Syntax error after migration, restoring backup"
            mv "$backup_file" "$file"
        else
            log_info "Syntax validation passed"
        fi
    else
        rm -f "$backup_file"
    fi
}

# Migrate existing state files
migrate_state_files() {
    log_step "Migrating existing state files..."
    
    local old_state_files=(
        "/tmp/deployment-state-*.json"
        "/tmp/geuse-deployment-state.json"
        "$PROJECT_ROOT/deployment-state.json"
    )
    
    for pattern in "${old_state_files[@]}"; do
        for state_file in $pattern; do
            if [[ -f "$state_file" ]]; then
                log_info "Found old state file: $state_file"
                
                # Create backup
                cp "$state_file" "${state_file}.pre-migration"
                
                # Convert to new format
                local new_state_file="/tmp/geuse-state/$(basename "$state_file")"
                mkdir -p "$(dirname "$new_state_file")"
                
                # Basic conversion (adapt structure)
                jq '{
                    version: "3.0.0",
                    created: .created // now,
                    backend: "local",
                    global: .global // {},
                    stacks: .deployments // .stacks // {},
                    deployments: .deployment_history // {},
                    events: .events // []
                }' "$state_file" > "$new_state_file"
                
                ((STATE_FILES_MIGRATED++))
                log_info "Migrated state file to: $new_state_file"
            fi
        done
    done
}

# Main migration process
main() {
    log_info "Starting unified state management migration"
    log_info "Project root: $PROJECT_ROOT"
    
    # Step 1: Create compatibility wrapper
    create_state_compatibility_wrapper
    
    # Step 2: Find files to migrate
    log_step "Finding files to migrate..."
    
    local files_to_migrate=($(find_files_to_migrate))
    
    if [[ ${#files_to_migrate[@]} -eq 0 ]]; then
        log_info "No files found that need migration"
    else
        log_info "Found ${#files_to_migrate[@]} files to migrate"
        
        # Step 3: Migrate each file
        for file in "${files_to_migrate[@]}"; do
            migrate_file "$file"
        done
    fi
    
    # Step 4: Migrate state files
    migrate_state_files
    
    # Step 5: Update wrapper scripts for old state modules
    log_step "Creating wrapper scripts for old modules..."
    
    for old_module in deployment-state-manager.sh enhanced-deployment-state.sh; do
        if [[ -f "$PROJECT_ROOT/lib/$old_module" ]]; then
            # Backup original
            mv "$PROJECT_ROOT/lib/$old_module" "$PROJECT_ROOT/lib/${old_module}.original"
            
            # Create wrapper
            cat > "$PROJECT_ROOT/lib/$old_module" << EOF
#!/usr/bin/env bash
# Wrapper for $old_module - redirects to unified state manager
source "\$(dirname "\${BASH_SOURCE[0]}")/unified-state-manager.sh"
source "\$(dirname "\${BASH_SOURCE[0]}")/state-compatibility.sh"
EOF
            chmod +x "$PROJECT_ROOT/lib/$old_module"
            log_info "Created wrapper for $old_module"
        fi
    done
    
    # Step 6: Summary
    echo ""
    log_info "Migration Summary"
    echo "=================="
    echo "Files analyzed: $FILES_ANALYZED"
    echo "Files migrated: $FILES_MIGRATED"
    echo "State files migrated: $STATE_FILES_MIGRATED"
    
    # Step 7: Validation
    echo ""
    log_step "Running validation..."
    
    # Test unified state manager
    if bash -c "source '$PROJECT_ROOT/lib/unified-state-manager.sh' && init_state_management test-stack" 2>/dev/null; then
        log_info "✓ Unified state manager is functional"
    else
        log_error "✗ Unified state manager has issues"
    fi
    
    # Step 8: Recommendations
    echo ""
    log_info "Next Steps:"
    echo "1. Test all migrated scripts thoroughly"
    echo "2. Verify state file migrations are correct"
    echo "3. Update any custom state management code"
    echo "4. Remove .original files after validation"
    echo "5. Update documentation to reference unified system"
    
    log_info "Migration completed!"
}

# Run main function
main "$@"