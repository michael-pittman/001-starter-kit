#!/usr/bin/env bash
# Test script to validate proper library system usage across all shell scripts
# Exit codes:
# 0 - All scripts use libraries correctly
# 1 - Scripts found bypassing library system
# 2 - Configuration/setup error

# Compatible with bash 3.x+

set -euo pipefail

# Script identification
SCRIPT_NAME="test-library-system-usage"
SCRIPT_VERSION="1.0.0"

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Define library paths
LIB_DIR="$PROJECT_ROOT/lib"
MODULES_DIR="$LIB_DIR/modules"

# Test configuration
# Declare associative arrays for test results and tracking
declare -A TEST_RESULTS
declare -A SCRIPT_ISSUES
declare -A VIOLATION_COUNTS
TOTAL_SCRIPTS=0
TOTAL_VIOLATIONS=0
TOTAL_WARNINGS=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Approved library files that scripts should source
declare -A APPROVED_LIBRARIES=(
    ["aws-deployment-common.sh"]=1
    ["error-handling.sh"]=1
    ["modern-error-handling.sh"]=1
    ["associative-arrays.sh"]=1
    ["aws-cli-v2.sh"]=1
    ["config-management.sh"]=1
    ["aws-resource-manager.sh"]=1
    ["deployment-state-manager.sh"]=1
    ["aws-config.sh"]=1
    ["aws-quota-checker.sh"]=1
    ["deployment-validation.sh"]=1
    ["deployment-health.sh"]=1
    ["error-recovery.sh"]=1
    ["variable-management.sh"]=1
    ["enhanced-test-framework.sh"]=1
    ["docker-compose-installer.sh"]=1
    ["spot-instance.sh"]=1
    ["ondemand-instance.sh"]=1
    ["simple-instance.sh"]=1
    ["test-helpers.sh"]=1
)

# Patterns that indicate direct module sourcing (violations)
# These patterns catch direct sourcing of module files instead of using top-level libraries
declare -a VIOLATION_PATTERNS=(
    # source commands with /lib/modules/ paths
    'source[[:space:]]+["\047]*[^"]*\/lib\/modules\/'
    'source[[:space:]]+\$[A-Z_]*\/modules\/'
    '\.[[:space:]]+["\047]*[^"]*\/lib\/modules\/'
    '\.[[:space:]]+\$[A-Z_]*\/modules\/'
    # Specific module paths
    'source.*modules/core/'
    'source.*modules/infrastructure/'
    'source.*modules/compute/'
    'source.*modules/application/'
    'source.*modules/cleanup/'
    'source.*modules/errors/'
    'source.*modules/deployment/'
    'source.*modules/monitoring/'
    '\. .*modules/core/'
    '\. .*modules/infrastructure/'
    '\. .*modules/compute/'
    '\. .*modules/application/'
    '\. .*modules/cleanup/'
    '\. .*modules/errors/'
    '\. .*modules/deployment/'
    '\. .*modules/monitoring/'
)

# Patterns for proper library usage
declare -a APPROVED_PATTERNS=(
    'source.*PROJECT_ROOT.*/lib/[^/]+\.sh'
    'source.*LIB_DIR/[^/]+\.sh'
    '\. .*PROJECT_ROOT.*/lib/[^/]+\.sh'
    '\. .*LIB_DIR/[^/]+\.sh'
)

# Scripts to exclude from checks (test files, examples, etc.)
declare -A EXCLUDED_SCRIPTS=(
    ["test-library-system-usage.sh"]=1
    ["template.sh"]=1
    ["test-library-system-usage-quick.sh"]=1
)

# Initialize violation counts
init_violation_counts() {
    VIOLATION_COUNTS["direct_module_source"]=0
    VIOLATION_COUNTS["missing_library_usage"]=0
    VIOLATION_COUNTS["incorrect_source_order"]=0
    VIOLATION_COUNTS["hardcoded_paths"]=0
    VIOLATION_COUNTS["missing_project_root"]=0
}

# Print header
print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}       Library System Usage Test - v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e "Project Root: ${CYAN}$PROJECT_ROOT${NC}"
    echo -e "Library Dir:  ${CYAN}$LIB_DIR${NC}"
    echo -e "Modules Dir:  ${CYAN}$MODULES_DIR${NC}"
    echo ""
    echo -e "${YELLOW}What This Test Checks:${NC}"
    echo -e "- Scripts in /scripts/, /tests/, /tools/ must use library loader pattern"
    echo -e "- Scripts must NOT directly source files from /lib/modules/"
    echo -e "- Scripts must source from /lib/ top-level libraries instead"
    echo ""
    echo -e "${GREEN}Excluded from checks:${NC}"
    echo -e "- ALL files in /lib/ directory (they are part of the library system)"
    echo -e "- Backup files, .git directory, node_modules, etc."
    echo ""
}

# Check if file should be excluded
should_exclude() {
    local file="$1"
    local basename=$(basename "$file")
    local relative_path="${file#$PROJECT_ROOT/}"
    
    # IMPORTANT: Exclude all files in /lib/ directory from checks
    # The entire /lib/ directory is part of the library system infrastructure
    # Only scripts OUTSIDE of /lib/ need to follow the library loading pattern
    if [[ "$relative_path" =~ ^lib/ ]]; then
        return 0
    fi
    
    # Exclude third-party integration scripts
    if [[ "$relative_path" =~ ^(ollama|crawl4ai)/ ]]; then
        return 0
    fi
    
    # Check exclusion list
    [[ -n "${EXCLUDED_SCRIPTS[$basename]:-}" ]] && return 0
    
    # Exclude backup files
    [[ "$file" =~ \.bak$ ]] && return 0
    [[ "$file" =~ ~$ ]] && return 0
    
    # Exclude .git directory
    [[ "$file" =~ \.git/ ]] && return 0
    
    # Exclude node_modules
    [[ "$file" =~ node_modules/ ]] && return 0
    
    # Exclude flattened-codebase.xml
    [[ "$file" =~ flattened-codebase\.xml ]] && return 0
    
    # Exclude .bmad-core directory
    [[ "$file" =~ \.bmad-core/ ]] && return 0
    
    # Exclude web-bundles directory
    [[ "$file" =~ web-bundles/ ]] && return 0
    
    return 1
}

# Check for direct module sourcing
check_direct_module_source() {
    local file="$1"
    local violations=0
    local line_num=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        for pattern in "${VIOLATION_PATTERNS[@]}"; do
            if [[ "$line" =~ $pattern ]]; then
                echo -e "${RED}  ✗ Direct module source found at line $line_num:${NC}" >&2
                echo -e "    ${YELLOW}$line${NC}" >&2
                ((violations++))
                SCRIPT_ISSUES["$file"]+="Direct module source at line $line_num|"
            fi
        done
    done < "$file"
    
    # Return number of violations
    echo "$violations"
}

# Check for proper library usage pattern
check_library_usage_pattern() {
    local file="$1"
    local has_project_root=0
    local has_lib_source=0
    local first_source_line=0
    local issues=""
    
    # Check for PROJECT_ROOT setup
    if grep -q 'PROJECT_ROOT.*dirname.*BASH_SOURCE' "$file"; then
        has_project_root=1
    fi
    
    # Check for library sourcing
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Check for approved library sourcing
        for pattern in "${APPROVED_PATTERNS[@]}"; do
            if [[ "$line" =~ $pattern ]]; then
                has_lib_source=1
                if [[ $first_source_line -eq 0 ]]; then
                    first_source_line=$line_num
                fi
                
                # Extract library name
                local lib_name=""
                if [[ "$line" =~ lib/([^/]+\.sh) ]]; then
                    lib_name="${BASH_REMATCH[1]}"
                    if [[ -z "${APPROVED_LIBRARIES[$lib_name]:-}" ]]; then
                        issues+="Sourcing unapproved library '$lib_name' at line $line_num|"
                    fi
                fi
            fi
        done
    done < "$file"
    
    # Report issues
    if [[ $has_project_root -eq 0 ]] && [[ $has_lib_source -eq 1 ]]; then
        issues+="Missing PROJECT_ROOT setup|"
        ((VIOLATION_COUNTS["missing_project_root"]++))
    fi
    
    if [[ -n "$issues" ]]; then
        SCRIPT_ISSUES["$file"]+="$issues"
        return 1
    fi
    
    return 0
}

# Check for hardcoded paths
check_hardcoded_paths() {
    local file="$1"
    local violations=0
    local line_num=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Check for hardcoded module paths
        if [[ "$line" =~ /lib/modules/ ]] && ! [[ "$line" =~ \$[A-Z_]+.*modules ]]; then
            echo -e "${YELLOW}  ⚠ Potential hardcoded path at line $line_num:${NC}" >&2
            echo -e "    ${YELLOW}$line${NC}" >&2
            ((violations++))
            SCRIPT_ISSUES["$file"]+="Hardcoded path at line $line_num|"
        fi
    done < "$file"
    
    if [[ $violations -gt 0 ]]; then
        ((VIOLATION_COUNTS["hardcoded_paths"]+=$violations))
    fi
    
    # Return number of violations
    echo "$violations"
}

# Analyze a single script
analyze_script() {
    local file="$1"
    local basename=$(basename "$file")
    local relative_path="${file#$PROJECT_ROOT/}"
    local has_violations=0
    local has_warnings=0
    local direct_violations=0
    local hardcoded_warnings=0
    
    # Determine script location type
    local location_type=""
    if [[ "$relative_path" =~ ^scripts/ ]]; then
        location_type="[SCRIPT]"
    elif [[ "$relative_path" =~ ^tests/ ]]; then
        location_type="[TEST]"
    elif [[ "$relative_path" =~ ^tools/ ]]; then
        location_type="[TOOL]"
    elif [[ "$relative_path" =~ ^lib/ ]]; then
        location_type="[LIB]"
    else
        location_type="[ROOT]"
    fi
    
    echo -e "${CYAN}Analyzing $location_type: $relative_path${NC}"
    
    # Check for direct module sourcing
    direct_violations=$(check_direct_module_source "$file")
    if [[ $direct_violations -gt 0 ]]; then
        ((VIOLATION_COUNTS["direct_module_source"]+=$direct_violations))
        ((TOTAL_VIOLATIONS+=$direct_violations))
        ((has_violations+=$direct_violations))
    fi
    
    # Check library usage pattern
    if ! check_library_usage_pattern "$file"; then
        ((has_violations++))
        ((TOTAL_VIOLATIONS++))
    fi
    
    # Check for hardcoded paths
    hardcoded_warnings=$(check_hardcoded_paths "$file")
    if [[ $hardcoded_warnings -gt 0 ]]; then
        ((TOTAL_WARNINGS+=$hardcoded_warnings))
        ((has_warnings+=$hardcoded_warnings))
    fi
    
    # Store results
    if [[ $has_violations -gt 0 ]]; then
        TEST_RESULTS["$relative_path"]="FAIL"
        echo -e "${RED}  ✗ Script has violations${NC}"
    elif [[ $has_warnings -gt 0 ]]; then
        TEST_RESULTS["$relative_path"]="WARN"
        echo -e "${YELLOW}  ⚠ Script has warnings${NC}"
    else
        TEST_RESULTS["$relative_path"]="PASS"
        echo -e "${GREEN}  ✓ Script follows library conventions${NC}"
    fi
    
    echo ""
}

# Find all shell scripts in the project with limited depth
find_shell_scripts() {
    local scripts=()
    
    # Find all .sh files with limited depth to avoid hanging
    while IFS= read -r file; do
        if ! should_exclude "$file"; then
            scripts+=("$file")
        fi
    done < <(find "$PROJECT_ROOT" -maxdepth 5 -type f -name "*.sh" 2>/dev/null | sort)
    
    # Find all shell scripts without .sh extension with limited depth
    while IFS= read -r file; do
        if [[ -f "$file" ]] && [[ -x "$file" ]]; then
            if head -n 1 "$file" 2>/dev/null | grep -q '^#!/.*sh$'; then
                if ! should_exclude "$file"; then
                    scripts+=("$file")
                fi
            fi
        fi
    done < <(find "$PROJECT_ROOT" -maxdepth 5 -type f ! -name "*.sh" 2>/dev/null | sort)
    
    printf '%s\n' "${scripts[@]}" | sort -u
}

# Generate detailed report
generate_report() {
    local report_file="$PROJECT_ROOT/test-reports/library-usage-report.txt"
    local json_report="$PROJECT_ROOT/test-reports/library-usage-report.json"
    
    # Create report directory
    mkdir -p "$PROJECT_ROOT/test-reports"
    
    # Generate text report
    {
        echo "Library System Usage Test Report"
        echo "================================"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_ROOT"
        echo ""
        echo "Summary:"
        echo "--------"
        echo "Total Scripts Analyzed: $TOTAL_SCRIPTS"
        echo "Scripts with Violations: $TOTAL_VIOLATIONS"
        echo "Scripts with Warnings: $TOTAL_WARNINGS"
        echo ""
        echo "Violation Breakdown:"
        echo "-------------------"
        for violation_type in "${!VIOLATION_COUNTS[@]}"; do
            echo "- ${violation_type//_/ }: ${VIOLATION_COUNTS[$violation_type]}"
        done
        echo ""
        echo "Detailed Results:"
        echo "-----------------"
        for script in "${!TEST_RESULTS[@]}"; do
            local status="${TEST_RESULTS[$script]}"
            echo -n "[$status] $script"
            if [[ -n "${SCRIPT_ISSUES[$script]:-}" ]]; then
                echo " - Issues:"
                IFS='|' read -ra issues <<< "${SCRIPT_ISSUES[$script]}"
                for issue in "${issues[@]}"; do
                    [[ -n "$issue" ]] && echo "    - $issue"
                done
            else
                echo ""
            fi
        done
    } > "$report_file"
    
    # Generate JSON report
    {
        echo "{"
        echo "  \"summary\": {"
        echo "    \"total_scripts\": $TOTAL_SCRIPTS,"
        echo "    \"violations\": $TOTAL_VIOLATIONS,"
        echo "    \"warnings\": $TOTAL_WARNINGS,"
        echo "    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
        echo "  },"
        echo "  \"violation_counts\": {"
        local first=true
        for violation_type in "${!VIOLATION_COUNTS[@]}"; do
            [[ "$first" == "true" ]] && first=false || echo ","
            printf '    "%s": %d' "$violation_type" "${VIOLATION_COUNTS[$violation_type]}"
        done
        echo ""
        echo "  },"
        echo "  \"scripts\": {"
        local first=true
        for script in "${!TEST_RESULTS[@]}"; do
            [[ "$first" == "true" ]] && first=false || echo ","
            printf '    "%s": {\n' "$script"
            printf '      "status": "%s"' "${TEST_RESULTS[$script]}"
            if [[ -n "${SCRIPT_ISSUES[$script]:-}" ]]; then
                echo ","
                echo '      "issues": ['
                IFS='|' read -ra issues <<< "${SCRIPT_ISSUES[$script]}"
                local issue_first=true
                for issue in "${issues[@]}"; do
                    if [[ -n "$issue" ]]; then
                        [[ "$issue_first" == "true" ]] && issue_first=false || echo ","
                        printf '        "%s"' "$issue"
                    fi
                done
                echo ""
                echo '      ]'
            else
                echo ""
            fi
            printf '    }'
        done
        echo ""
        echo "  }"
        echo "}"
    } > "$json_report"
    
    echo -e "${GREEN}Reports generated:${NC}"
    echo -e "  - Text: $report_file"
    echo -e "  - JSON: $json_report"
}

# Print summary
print_summary() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}                        Test Summary${NC}"
    echo -e "${BLUE}================================================================${NC}"
    
    echo -e "Directories Checked: /scripts/, /tests/, /tools/, and project root"
    echo -e "Total Scripts Analyzed: ${CYAN}$TOTAL_SCRIPTS${NC}"
    echo -e "Scripts with Violations: ${RED}$TOTAL_VIOLATIONS${NC}"
    echo -e "Scripts with Warnings: ${YELLOW}$TOTAL_WARNINGS${NC}"
    
    echo ""
    echo -e "${BLUE}Violation Breakdown:${NC}"
    for violation_type in "${!VIOLATION_COUNTS[@]}"; do
        local count="${VIOLATION_COUNTS[$violation_type]}"
        if [[ $count -gt 0 ]]; then
            echo -e "  ${YELLOW}${violation_type//_/ }:${NC} $count"
        fi
    done
    
    if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✓ All scripts follow library system conventions!${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}✗ Found $TOTAL_VIOLATIONS scripts violating library conventions${NC}"
        return 1
    fi
}

# Main test execution
main() {
    print_header
    init_violation_counts
    
    echo -e "${BLUE}Scanning for shell scripts...${NC}"
    local scripts=()
    while IFS= read -r script; do
        scripts+=("$script")
    done < <(find_shell_scripts)
    
    TOTAL_SCRIPTS=${#scripts[@]}
    echo -e "Found ${CYAN}$TOTAL_SCRIPTS${NC} scripts to analyze"
    echo ""
    
    # Analyze each script
    for script in "${scripts[@]}"; do
        analyze_script "$script"
    done
    
    # Generate reports
    generate_report
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [[ $TOTAL_VIOLATIONS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"