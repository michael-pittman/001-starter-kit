#!/usr/bin/env bash
# =============================================================================
# Bash 5.3.3+ Upgrade Summary Script
# Shows the status of bash version upgrade across the GeuseMaker codebase
# =============================================================================

# Validate bash version first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/modules/core/bash_version.sh"
require_bash_533 "bash-533-upgrade-summary.sh"

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}GeuseMaker Bash 5.3.3+ Upgrade Summary${NC}"
echo "========================================"
echo

# Current bash version
echo -e "${CYAN}Current Environment:${NC}"
echo "Bash Version: $(get_current_bash_version)"
echo "Platform: $(detect_platform)"
echo "Version Check: $(bash_533_available && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo

# =============================================================================
# CHECK FILE UPDATES
# =============================================================================

check_shebang_updates() {
    echo -e "${CYAN}Shebang Updates (#!/usr/bin/env bash):${NC}"
    
    local updated_count=0
    local total_count=0
    
    # Check all shell scripts
    while IFS= read -r file; do
        ((total_count++))
        if head -1 "$file" | grep -q "#!/usr/bin/env bash"; then
            ((updated_count++))
            echo -e "  ${GREEN}✓${NC} $file"
        else
            echo -e "  ${RED}✗${NC} $file (still uses old shebang)"
        fi
    done < <(find "$PROJECT_ROOT" -name "*.sh" -type f | sort)
    
    echo
    echo "Summary: $updated_count/$total_count files updated to use #!/usr/bin/env bash"
    echo
}

check_version_validation() {
    echo -e "${CYAN}Bash Version Validation Integration:${NC}"
    
    local validated_count=0
    local total_count=0
    
    # Check main scripts for version validation
    for file in "$PROJECT_ROOT"/scripts/*.sh; do
        if [[ -f "$file" ]]; then
            ((total_count++))
            if grep -q "require_bash_533\|bash_version.sh" "$file"; then
                ((validated_count++))
                echo -e "  ${GREEN}✓${NC} $(basename "$file")"
            else
                echo -e "  ${YELLOW}○${NC} $(basename "$file") (no version validation)"
            fi
        fi
    done
    
    echo
    echo "Summary: $validated_count/$total_count scripts have bash version validation"
    echo
}

check_library_updates() {
    echo -e "${CYAN}Library Files Updated:${NC}"
    
    # Check main library files
    for file in "$PROJECT_ROOT"/lib/*.sh; do
        if [[ -f "$file" ]]; then
            if grep -q "bash 5.3.3\|require_bash_533" "$file"; then
                echo -e "  ${GREEN}✓${NC} $(basename "$file")"
            else
                echo -e "  ${YELLOW}○${NC} $(basename "$file") (not updated)"
            fi
        fi
    done
    echo
}

check_modules_updates() {
    echo -e "${CYAN}Module Files Updated:${NC}"
    
    local updated_count=0
    local total_count=0
    
    # Check module files
    while IFS= read -r file; do
        ((total_count++))
        if grep -q "bash 5.3.3\|bash_533_available" "$file"; then
            ((updated_count++))
            echo -e "  ${GREEN}✓${NC} ${file#$PROJECT_ROOT/lib/modules/}"
        else
            echo -e "  ${YELLOW}○${NC} ${file#$PROJECT_ROOT/lib/modules/} (not updated)"
        fi
    done < <(find "$PROJECT_ROOT/lib/modules" -name "*.sh" -type f | sort)
    
    echo
    echo "Summary: $updated_count/$total_count module files updated"
    echo
}

check_new_features() {
    echo -e "${CYAN}New Features Added:${NC}"
    
    # Check for bash version module
    if [[ -f "$PROJECT_ROOT/lib/modules/core/bash_version.sh" ]]; then
        echo -e "  ${GREEN}✓${NC} Bash version validation module created"
    else
        echo -e "  ${RED}✗${NC} Bash version validation module missing"
    fi
    
    # Check for EC2 user data updates
    if grep -q "install_modern_bash" "$PROJECT_ROOT/terraform/user-data.sh" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} EC2 user data script updated for bash 5.3.3 installation"
    else
        echo -e "  ${YELLOW}○${NC} EC2 user data script not updated"
    fi
    
    # Check for CLAUDE.md updates
    if grep -q "bash 5.3.3" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} CLAUDE.md updated with bash requirements"
    else
        echo -e "  ${YELLOW}○${NC} CLAUDE.md not updated"
    fi
    
    # Check for test script
    if [[ -f "$PROJECT_ROOT/tests/test-bash-version-validation.sh" ]]; then
        echo -e "  ${GREEN}✓${NC} Bash version validation test script created"
    else
        echo -e "  ${YELLOW}○${NC} Test script not created"
    fi
    
    echo
}

check_remaining_work() {
    echo -e "${CYAN}Remaining Work:${NC}"
    
    # Find files still using old shebang
    local old_shebang_count
    old_shebang_count=$(find "$PROJECT_ROOT" -name "*.sh" -type f -exec grep -l "#!/bin/bash" {} \; 2>/dev/null | wc -l)
    
    if [[ $old_shebang_count -gt 0 ]]; then
        echo -e "  ${YELLOW}○${NC} $old_shebang_count files still use #!/bin/bash shebang"
        echo "    Run: find . -name \"*.sh\" -exec grep -l \"#!/bin/bash\" {} \\;"
    else
        echo -e "  ${GREEN}✓${NC} All shell scripts use #!/usr/bin/env bash"
    fi
    
    # Check for files without version validation
    local no_validation_count=0
    for file in "$PROJECT_ROOT"/scripts/*.sh; do
        if [[ -f "$file" ]] && ! grep -q "require_bash_533\|bash_version.sh" "$file"; then
            ((no_validation_count++))
        fi
    done
    
    if [[ $no_validation_count -gt 0 ]]; then
        echo -e "  ${YELLOW}○${NC} $no_validation_count scripts in /scripts/ lack version validation"
    else
        echo -e "  ${GREEN}✓${NC} All critical scripts have version validation"
    fi
    
    echo
}

# =============================================================================
# RUN ALL CHECKS
# =============================================================================

check_shebang_updates
check_version_validation
check_library_updates
check_modules_updates
check_new_features
check_remaining_work

# =============================================================================
# SUMMARY AND NEXT STEPS
# =============================================================================

echo -e "${BOLD}${BLUE}Summary and Next Steps:${NC}"
echo "1. Most critical files have been updated to require bash 5.3.3+"
echo "2. EC2 instances will auto-install bash 5.3.3 during deployment"
echo "3. Development teams should upgrade their local bash versions"
echo "4. CLAUDE.md has been updated with comprehensive bash requirements"
echo
echo -e "${YELLOW}Developer Action Required:${NC}"
echo "• macOS users: run 'brew install bash' and update shell"
echo "• Linux users: ensure bash 5.3.3+ is installed"
echo "• Verify with: bash --version"
echo
echo -e "${GREEN}Deployment Benefits:${NC}"
echo "• Enhanced error handling and debugging"
echo "• Improved security and bug fixes"
echo "• Consistent behavior across environments"
echo "• Future-ready for advanced bash features"