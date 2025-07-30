#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Migration Script: Unified Error Handling
# Migrates scripts from old error handling systems to the unified system
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
ERRORS_FOUND=0

# Find all files using old error handling systems
find_files_to_migrate() {
    log_info "Scanning for files using old error handling systems..."
    
    local files=()
    
    # Find files sourcing old error handling systems
    while IFS= read -r file; do
        if grep -l "source.*error-handling\.sh\|modern-error-handling\.sh\|aws-api-error-handling\.sh" "$file" 2>/dev/null; then
            files+=("$file")
        fi
    done < <(find "$PROJECT_ROOT" -name "*.sh" -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/archive/*" \
        -not -path "*/tests/*")
    
    echo "${files[@]}"
}

# Create compatibility wrapper
create_compatibility_wrapper() {
    local old_file="$1"
    local wrapper_content=""
    
    case "$old_file" in
        *"error-handling.sh")
            wrapper_content='#!/usr/bin/env bash
# Compatibility wrapper for error-handling.sh
# Redirects to unified error handling system

# Source unified system
source "$(dirname "${BASH_SOURCE[0]}")/unified-error-handling.sh"

# Compatibility aliases
alias handle_error_old=handle_error
alias log_error=log_error_internal

# Compatibility functions
error() {
    throw_error 100 "$@"
}

# Export for backward compatibility
export -f error
'
            ;;
        *"modern-error-handling.sh")
            wrapper_content='#!/usr/bin/env bash
# Compatibility wrapper for modern-error-handling.sh
# Redirects to unified error handling system

# Source unified system
source "$(dirname "${BASH_SOURCE[0]}")/unified-error-handling.sh"

# Compatibility functions
throw_aws_error() {
    handle_aws_error "$@"
}

# Export for backward compatibility
export -f throw_aws_error
'
            ;;
        *"aws-api-error-handling.sh")
            wrapper_content='#!/usr/bin/env bash
# Compatibility wrapper for aws-api-error-handling.sh
# Redirects to unified error handling system

# Source unified system
source "$(dirname "${BASH_SOURCE[0]}")/unified-error-handling.sh"

# AWS-specific compatibility
handle_aws_api_error() {
    handle_aws_error "$@"
}

# Export for backward compatibility
export -f handle_aws_api_error
'
            ;;
    esac
    
    if [[ -n "$wrapper_content" ]]; then
        # Backup original
        mv "$old_file" "${old_file}.original"
        
        # Create wrapper
        echo "$wrapper_content" > "$old_file"
        chmod +x "$old_file"
        
        log_info "Created compatibility wrapper: $old_file"
    fi
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
    
    # Replace source statements
    if grep -q 'source.*error-handling\.sh' "$file"; then
        sed -i.tmp 's|source.*error-handling\.sh|source "${LIB_DIR}/unified-error-handling.sh"|g' "$file"
        modified=true
    fi
    
    if grep -q 'source.*modern-error-handling\.sh' "$file"; then
        sed -i.tmp 's|source.*modern-error-handling\.sh|source "${LIB_DIR}/unified-error-handling.sh"|g' "$file"
        modified=true
    fi
    
    if grep -q 'source.*aws-api-error-handling\.sh' "$file"; then
        sed -i.tmp 's|source.*aws-api-error-handling\.sh|source "${LIB_DIR}/unified-error-handling.sh"|g' "$file"
        modified=true
    fi
    
    # Update function calls
    if grep -q 'handle_error_old' "$file"; then
        sed -i.tmp 's/handle_error_old/handle_error/g' "$file"
        modified=true
    fi
    
    if grep -q 'throw_aws_error' "$file"; then
        sed -i.tmp 's/throw_aws_error/handle_aws_error/g' "$file"
        modified=true
    fi
    
    # Clean up temp files
    rm -f "${file}.tmp"
    
    if [[ "$modified" == "true" ]]; then
        ((FILES_MIGRATED++))
        log_info "Migrated: $file"
        
        # Validate the migrated file
        if bash -n "$file" 2>/dev/null; then
            log_info "Syntax check passed"
        else
            log_error "Syntax check failed for $file"
            ((ERRORS_FOUND++))
            # Restore backup
            mv "$backup_file" "$file"
            log_warning "Restored backup due to syntax error"
        fi
    else
        # Remove backup if no changes
        rm -f "$backup_file"
    fi
}

# Update imports in a directory
update_directory_imports() {
    local dir="$1"
    
    log_step "Updating imports in directory: $dir"
    
    # Update any reference to old error handling modules
    find "$dir" -name "*.sh" -type f | while read -r file; do
        # Skip test files for now
        if [[ "$file" == *"/test"* ]] || [[ "$file" == *"/tests/"* ]]; then
            continue
        fi
        
        # Check if file needs updating
        if grep -q "modules/errors/error_types\.sh\|error-recovery\.sh" "$file" 2>/dev/null; then
            log_info "Updating imports in: $file"
            
            # Update imports
            sed -i.tmp 's|modules/errors/error_types\.sh|unified-error-handling.sh|g' "$file"
            sed -i.tmp 's|error-recovery\.sh|unified-error-handling.sh|g' "$file"
            
            rm -f "${file}.tmp"
        fi
    done
}

# Main migration process
main() {
    log_info "Starting unified error handling migration"
    log_info "Project root: $PROJECT_ROOT"
    
    # Step 1: Create compatibility wrappers
    log_step "Creating compatibility wrappers..."
    
    for old_file in "$PROJECT_ROOT/lib/error-handling.sh" \
                   "$PROJECT_ROOT/lib/modern-error-handling.sh" \
                   "$PROJECT_ROOT/lib/aws-api-error-handling.sh"; do
        if [[ -f "$old_file" ]]; then
            create_compatibility_wrapper "$old_file"
        fi
    done
    
    # Step 2: Find and migrate files
    log_step "Finding files to migrate..."
    
    local files_to_migrate=($(find_files_to_migrate))
    
    if [[ ${#files_to_migrate[@]} -eq 0 ]]; then
        log_info "No files found that need migration"
    else
        log_info "Found ${#files_to_migrate[@]} files to migrate"
        
        for file in "${files_to_migrate[@]}"; do
            migrate_file "$file"
        done
    fi
    
    # Step 3: Update directory imports
    log_step "Updating module imports..."
    
    update_directory_imports "$PROJECT_ROOT/scripts"
    update_directory_imports "$PROJECT_ROOT/lib"
    update_directory_imports "$PROJECT_ROOT/tools"
    
    # Step 4: Summary
    echo ""
    log_info "Migration Summary"
    echo "=================="
    echo "Files analyzed: $FILES_ANALYZED"
    echo "Files migrated: $FILES_MIGRATED"
    echo "Errors found: $ERRORS_FOUND"
    
    # Step 5: Recommendations
    echo ""
    log_info "Next Steps:"
    echo "1. Test all migrated scripts thoroughly"
    echo "2. Review compatibility wrappers in lib/"
    echo "3. Update test files to use unified error handling"
    echo "4. Consider removing old error handling files after validation"
    echo "5. Update documentation to reference unified system"
    
    # Step 6: Validation
    echo ""
    log_step "Running basic validation..."
    
    # Check if unified error handling can be sourced
    if bash -c "source '$PROJECT_ROOT/lib/unified-error-handling.sh' && init_error_handling" 2>/dev/null; then
        log_info "✓ Unified error handling system is functional"
    else
        log_error "✗ Unified error handling system has issues"
        ((ERRORS_FOUND++))
    fi
    
    if [[ $ERRORS_FOUND -gt 0 ]]; then
        log_error "Migration completed with $ERRORS_FOUND errors - manual review required"
        exit 1
    else
        log_info "Migration completed successfully!"
    fi
}

# Run main function
main "$@"