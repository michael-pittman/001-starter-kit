#!/bin/bash
# =============================================================================
# Documentation Update Validation Test
# Tests documentation accuracy and validates links
# =============================================================================

set -euo pipefail

# Test configuration
TEST_NAME="Documentation Update Validation"
TEST_DESCRIPTION="Validates documentation accuracy and link integrity"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_test_start() {
    local test_name="$1"
    local test_description="$2"
    echo -e "\n${CYAN}${test_name}${NC}"
    echo -e "${CYAN}Description: ${test_description}${NC}"
}

log_test_pass() {
    local test_name="$1"
    local message="$2"
    echo -e "${GREEN}✓ PASS${NC} ${test_name}: ${message}"
    ((PASSED_TESTS++))
}

log_test_fail() {
    local test_name="$1"
    local message="$2"
    echo -e "${RED}✗ FAIL${NC} ${test_name}: ${message}"
    ((FAILED_TESTS++))
}

# Test functions
test_documentation_links() {
    local test_name="Documentation Links Validation"
    local test_description="Validates all internal documentation links"
    
    log_test_start "$test_name" "$test_description"
    ((TOTAL_TESTS++))
    
    local broken_links=0
    local total_links=0
    
    # Find all markdown files
    while IFS= read -r -d '' file; do
        # Extract links from markdown files
        while IFS= read -r line; do
            # Extract markdown links [text](url)
            if [[ $line =~ \[([^\]]+)\]\(([^)]+)\) ]]; then
                local link_text="${BASH_REMATCH[1]}"
                local link_url="${BASH_REMATCH[2]}"
                ((total_links++))
                
                # Skip external links
                if [[ $link_url =~ ^https?:// ]]; then
                    continue
                fi
                
                # Handle relative links
                local target_file=""
                if [[ $link_url =~ ^# ]]; then
                    # Anchor link, skip for now
                    continue
                elif [[ $link_url =~ ^/ ]]; then
                    # Absolute path from root
                    target_file="$link_url"
                else
                    # Relative path
                    local file_dir="$(dirname "$file")"
                    target_file="$file_dir/$link_url"
                fi
                
                # Check if target file exists
                if [[ ! -f "$target_file" ]]; then
                    log_error "Broken link in $file: $link_text -> $link_url (target: $target_file)"
                    ((broken_links++))
                fi
            fi
        done < "$file"
    done < <(find docs -name "*.md" -print0)
    
    if [[ $broken_links -eq 0 ]]; then
        log_test_pass "$test_name" "All $total_links links are valid"
        return 0
    else
        log_test_fail "$test_name" "Found $broken_links broken links out of $total_links total links"
        return 1
    fi
}

test_documentation_structure() {
    local test_name="Documentation Structure Validation"
    local test_description="Validates documentation structure reflects current architecture"
    
    log_test_start "$test_name" "$test_description"
    ((TOTAL_TESTS++))
    
    local errors=0
    
    # Check README.md structure
    if ! grep -q "10 major functional modules" README.md; then
        log_error "README.md does not reflect consolidated module structure (10 modules)"
        ((errors++))
    fi
    
    # Check for obsolete module references
    if grep -q "aws-deployment-v2-simple.sh" README.md; then
        log_error "README.md contains references to obsolete scripts"
        ((errors++))
    fi
    
    # Check deployment guide structure
    if ! grep -q "make deploy-spot" docs/guides/deployment.md; then
        log_error "Deployment guide does not reflect current make-based commands"
        ((errors++))
    fi
    
    # Check troubleshooting guide structure
    if ! grep -q "make health" docs/guides/troubleshooting.md; then
        log_error "Troubleshooting guide does not reflect current make-based commands"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_test_pass "$test_name" "Documentation structure is current"
        return 0
    else
        log_test_fail "$test_name" "Found $errors documentation structure issues"
        return 1
    fi
}

test_module_documentation() {
    local test_name="Module Documentation Validation"
    local test_description="Validates module documentation reflects current structure"
    
    log_test_start "$test_name" "$test_description"
    ((TOTAL_TESTS++))
    
    local errors=0
    
    # Check that all current modules are documented
    local current_modules=(
        "core"
        "infrastructure" 
        "compute"
        "application"
        "deployment"
        "monitoring"
        "errors"
        "config"
        "instances"
        "cleanup"
    )
    
    for module in "${current_modules[@]}"; do
        if ! grep -q "$module" README.md; then
            log_error "Module '$module' not documented in README.md"
            ((errors++))
        fi
    done
    
    # Check for obsolete module references
    local obsolete_modules=(
        "aws-deployment-v2-simple"
        "aws-deployment-modular"
        "health-check-advanced"
        "check-instance-status"
    )
    
    for module in "${obsolete_modules[@]}"; do
        if grep -q "$module" README.md; then
            log_error "README.md contains obsolete module reference: $module"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_test_pass "$test_name" "Module documentation is current"
        return 0
    else
        log_test_fail "$test_name" "Found $errors module documentation issues"
        return 1
    fi
}

test_examples_accuracy() {
    local test_name="Documentation Examples Validation"
    local test_description="Validates that documentation examples use current commands"
    
    log_test_start "$test_name" "$test_description"
    ((TOTAL_TESTS++))
    
    local errors=0
    
    # Check for obsolete command examples
    local obsolete_commands=(
        "aws-deployment-v2-simple.sh"
        "aws-deployment-modular.sh"
        "health-check-advanced.sh"
        "check-instance-status.sh"
        "fix-deployment-issues.sh"
        "cleanup-consolidated.sh"
    )
    
    for cmd in "${obsolete_commands[@]}"; do
        if grep -q "$cmd" docs/guides/deployment.md; then
            log_error "Deployment guide contains obsolete command: $cmd"
            ((errors++))
        fi
        
        if grep -q "$cmd" docs/guides/troubleshooting.md; then
            log_error "Troubleshooting guide contains obsolete command: $cmd"
            ((errors++))
        fi
    done
    
    # Check for current command examples
    local current_commands=(
        "make deploy-spot"
        "make deploy-alb"
        "make deploy-cdn"
        "make deploy-full"
        "make health"
        "make status"
        "make destroy"
    )
    
    for cmd in "${current_commands[@]}"; do
        if ! grep -q "$cmd" docs/guides/deployment.md; then
            log_error "Deployment guide missing current command: $cmd"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_test_pass "$test_name" "Documentation examples are current"
        return 0
    else
        log_test_fail "$test_name" "Found $errors example accuracy issues"
        return 1
    fi
}

test_consistency() {
    local test_name="Documentation Consistency Validation"
    local test_description="Validates consistency across documentation files"
    
    log_test_start "$test_name" "$test_description"
    ((TOTAL_TESTS++))
    
    local errors=0
    
    # Check for consistent module count references
    local module_count_10
    module_count_10=$(grep -c "10.*modules\|10 major functional modules" README.md || echo "0")
    local module_count_8
    module_count_8=$(grep -c "8.*modules\|8 major functional modules" README.md || echo "0")
    
    if [[ $module_count_8 -gt 0 ]]; then
        log_error "README.md contains outdated 8-module references"
        ((errors++))
    fi
    
    if [[ $module_count_10 -eq 0 ]]; then
        log_error "README.md missing current 10-module references"
        ((errors++))
    fi
    
    # Check for consistent command patterns
    local make_patterns
    make_patterns=$(grep -c "make [a-z-]*" docs/guides/deployment.md || echo "0")
    local script_patterns
    script_patterns=$(grep -c "\./scripts/" docs/guides/deployment.md || echo "0")
    
    if [[ $script_patterns -gt $make_patterns ]]; then
        log_error "Deployment guide has more script references than make commands"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_test_pass "$test_name" "Documentation is consistent"
        return 0
    else
        log_test_fail "$test_name" "Found $errors consistency issues"
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}${TEST_NAME}${NC}"
    echo -e "${CYAN}${TEST_DESCRIPTION}${NC}"
    echo -e "${CYAN}Started at: $(date)${NC}\n"
    
    local test_results=()
    
    # Run all tests
    test_documentation_links
    test_results+=($?)
    
    test_documentation_structure
    test_results+=($?)
    
    test_module_documentation
    test_results+=($?)
    
    test_examples_accuracy
    test_results+=($?)
    
    test_consistency
    test_results+=($?)
    
    # Final summary
    echo -e "\n${BLUE}=== Test Results Summary ===${NC}"
    echo -e "${CYAN}Total Tests: $TOTAL_TESTS${NC}"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo -e "${CYAN}Completed at: $(date)${NC}"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All documentation validation tests passed"
        return 0
    else
        log_error "$FAILED_TESTS documentation validation tests failed"
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi