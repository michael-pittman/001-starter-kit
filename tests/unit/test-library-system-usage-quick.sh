#!/usr/bin/env bash
# Quick test script to validate proper library system usage
# Exit codes: 0=pass, 1=violations found, 2=error

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_SCRIPTS=0
VIOLATIONS=0
WARNINGS=0

# Report file
REPORT_FILE="$PROJECT_ROOT/test-reports/library-usage-quick.txt"
mkdir -p "$PROJECT_ROOT/test-reports"

echo -e "${BLUE}Library System Usage Test (Quick)${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""

# Initialize report
{
    echo "Library System Usage Test Report (Quick Scan)"
    echo "============================================"
    echo "Generated: $(date)"
    echo ""
    echo "Checking for direct module sourcing violations..."
    echo ""
} > "$REPORT_FILE"

# Find shell scripts in key directories only
echo "Scanning shell scripts in key directories..."
for dir in "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/lib" "$PROJECT_ROOT/tests" "$PROJECT_ROOT/tools"; do
    [[ -d "$dir" ]] || continue
    
    while IFS= read -r script; do
        # Skip template and test files
        [[ "$(basename "$script")" == "template.sh" ]] && continue
        [[ "$(basename "$script")" == "test-library-system-usage.sh" ]] && continue
        [[ "$(basename "$script")" == "test-library-system-usage-quick.sh" ]] && continue
        
        ((TOTAL_SCRIPTS++))
        
        # Get relative path
        relative="${script#$PROJECT_ROOT/}"
        
        # Check for direct module sourcing (excluding comments)
        violations=$(grep -E '(source|\.).*["/]modules/(core|infrastructure|compute|application|compatibility|cleanup|errors|deployment|monitoring)/' "$script" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
        
        if [[ -n "$violations" ]]; then
            echo -e "${RED}✗ $relative${NC}"
            echo "✗ $relative" >> "$REPORT_FILE"
            echo "$violations" | nl -s ': ' | sed 's/^/    Line /' >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            ((VIOLATIONS++))
        else
            # Quick check for library usage
            if grep -q 'source.*lib/[^/]*\.sh' "$script" 2>/dev/null; then
                echo -e "${GREEN}✓ $relative${NC} - Uses library system"
            else
                # Module files don't need to source libraries
                if [[ "$script" =~ /modules/ ]]; then
                    echo -e "${GREEN}✓ $relative${NC} - Module file"
                else
                    echo -e "${GREEN}✓ $relative${NC}"
                fi
            fi
        fi
        
    done < <(find "$dir" -maxdepth 3 -type f -name "*.sh" 2>/dev/null)
done

# Summary
echo ""
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}-------${NC}"
echo -e "Total scripts analyzed: ${TOTAL_SCRIPTS}"
echo -e "Scripts with violations: ${RED}${VIOLATIONS}${NC}"

# Add summary to report
{
    echo ""
    echo "Summary"
    echo "-------"
    echo "Total scripts analyzed: $TOTAL_SCRIPTS"
    echo "Scripts with violations: $VIOLATIONS"
    echo ""
    if [[ $VIOLATIONS -eq 0 ]]; then
        echo "✓ All scripts follow library system conventions!"
    else
        echo "✗ Found $VIOLATIONS scripts violating library conventions"
        echo ""
        echo "To fix violations:"
        echo "1. Scripts should source from /lib/*.sh, not from /lib/modules/*/*.sh"
        echo "2. Modules are accessed through their parent libraries"
        echo "3. Use the library loading pattern documented in CLAUDE.md"
    fi
} >> "$REPORT_FILE"

echo ""
echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"

# Exit code
if [[ $VIOLATIONS -gt 0 ]]; then
    exit 1
else
    exit 0
fi