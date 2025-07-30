#!/usr/bin/env bash
# ==============================================================================
# Script: standardize-headers
# Description: Standardize headers across all shell scripts in the project
# 
# Usage: standardize-headers.sh [options]
#   Options:
#     -h, --help        Show this help message
#     -d, --dry-run     Show what would be changed without modifying files
#     -v, --verbose     Enable verbose output
#     -p, --path PATH   Specific path to process (default: entire project)
#
# Dependencies:
#   - None (uses standard Unix tools)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONSTANTS AND GLOBALS
# ==============================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
DRY_RUN=false
VERBOSE=false
TARGET_PATH="$PROJECT_ROOT"
FILES_PROCESSED=0
FILES_UPDATED=0
FILES_SKIPPED=0

# ==============================================================================
# FUNCTIONS
# ==============================================================================

# Display usage information
usage() {
    grep '^#' "${BASH_SOURCE[0]}" | head -20 | tail -n +2 | cut -c3-
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--path)
                TARGET_PATH="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                usage
                exit 2
                ;;
        esac
    done
}

# Log message if verbose mode is enabled
log_verbose() {
    [[ "$VERBOSE" == "true" ]] && echo "[VERBOSE] $*" >&2
}

# Extract script name from file path
get_script_name() {
    local file_path="$1"
    basename "$file_path" .sh
}

# Extract script type from path
get_script_type() {
    local file_path="$1"
    
    if [[ "$file_path" =~ /lib/modules/ ]]; then
        echo "Module"
    elif [[ "$file_path" =~ /tests?/ ]]; then
        echo "Test"
    elif [[ "$file_path" =~ /tools/ ]]; then
        echo "Tool"
    elif [[ "$file_path" =~ /scripts/ ]]; then
        echo "Script"
    else
        echo "Script"
    fi
}

# Generate standard header for a script
generate_header() {
    local file_path="$1"
    local script_name="$(get_script_name "$file_path")"
    local script_type="$(get_script_type "$file_path")"
    
    # Read first few lines to extract description if it exists
    local description="Brief description of this $script_type"
    if [[ -f "$file_path" ]]; then
        # Try to extract existing description
        local existing_desc
        existing_desc=$(grep -m1 "^# Description:" "$file_path" 2>/dev/null | sed 's/^# Description: *//' || true)
        [[ -n "$existing_desc" ]] && description="$existing_desc"
    fi
    
    cat << EOF
#!/usr/bin/env bash
# ==============================================================================
# $script_type: $script_name
# Description: $description
# 
EOF
    
    # Add usage section for scripts and tools
    if [[ "$script_type" == "Script" ]] || [[ "$script_type" == "Tool" ]]; then
        cat << EOF
# Usage: ${script_name}.sh [options] [arguments]
#   Options:
#     -h, --help        Show this help message
#
# Dependencies:
#   - List any required tools or libraries
#
# Exit Codes:
#   0 - Success
#   1 - General error
EOF
    elif [[ "$script_type" == "Module" ]]; then
        cat << EOF
# Functions:
#   - function_name()     Brief description
#
# Dependencies:
#   - module_name         Why it's needed
#
# Usage:
#   source "path/to/module.sh"
#   function_name "argument"
EOF
    elif [[ "$script_type" == "Test" ]]; then
        cat << EOF
# Test Categories:
#   - Unit tests
#   - Integration tests
#   - Edge cases
#
# Dependencies:
#   - Module or script being tested
#
# Usage:
#   ./test-script.sh
EOF
    fi
    
    echo "# =============================================================================="
    echo ""
}

# Check if file already has standardized header
has_standard_header() {
    local file_path="$1"
    
    # Check for the standard header pattern
    if grep -q "^# ==============================================================================$" "$file_path" 2>/dev/null && \
       grep -q "^# Description:" "$file_path" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Process a single shell script
process_file() {
    local file_path="$1"
    
    ((FILES_PROCESSED++))
    
    # Skip if already has standard header
    if has_standard_header "$file_path"; then
        log_verbose "Skipping $file_path (already has standard header)"
        ((FILES_SKIPPED++))
        return 0
    fi
    
    echo "Processing: $file_path"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  Would add standardized header"
        log_verbose "Generated header:"
        [[ "$VERBOSE" == "true" ]] && generate_header "$file_path"
        return 0
    fi
    
    # Create backup
    cp "$file_path" "${file_path}.bak"
    
    # Generate new header
    local new_header
    new_header=$(generate_header "$file_path")
    
    # Extract existing content (skip shebang and old headers)
    local content
    content=$(awk '
        BEGIN { found_content = 0 }
        /^#!/ && NR == 1 { next }
        /^#/ && !found_content { next }
        /^[[:space:]]*$/ && !found_content { next }
        { found_content = 1; print }
    ' "$file_path")
    
    # Write new file
    {
        echo "$new_header"
        echo "$content"
    } > "$file_path"
    
    # Remove backup if successful
    rm "${file_path}.bak"
    
    ((FILES_UPDATED++))
    echo "  ✓ Header standardized"
}

# Find and process all shell scripts
find_and_process_scripts() {
    local search_path="$1"
    
    echo "Searching for shell scripts in: $search_path"
    echo "=============================================="
    
    # Find all .sh files, excluding certain directories
    while IFS= read -r -d '' file; do
        # Skip certain directories
        if [[ "$file" =~ /(\.git|node_modules|vendor|tmp|cache)/ ]]; then
            continue
        fi
        
        # Skip non-shell scripts
        if ! file "$file" | grep -q "shell script\|bash script\|Bourne-Again shell script" 2>/dev/null; then
            if ! head -1 "$file" 2>/dev/null | grep -q "^#!/.*sh"; then
                continue
            fi
        fi
        
        process_file "$file"
        
    done < <(find "$search_path" -name "*.sh" -type f -print0 2>/dev/null)
}

# Main function
main() {
    echo "Shell Script Header Standardization"
    echo "==================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Running in DRY RUN mode - no files will be modified"
    fi
    
    echo ""
    
    # Validate target path
    if [[ ! -d "$TARGET_PATH" ]]; then
        echo "Error: Target path does not exist: $TARGET_PATH" >&2
        exit 1
    fi
    
    # Process scripts
    find_and_process_scripts "$TARGET_PATH"
    
    # Summary
    echo ""
    echo "Summary"
    echo "======="
    echo "Files processed: $FILES_PROCESSED"
    echo "Files updated:   $FILES_UPDATED"
    echo "Files skipped:   $FILES_SKIPPED"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "This was a dry run. Use without --dry-run to apply changes."
    fi
}

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

# Parse arguments
parse_arguments "$@"

# Run main function
main

# Exit successfully
exit 0