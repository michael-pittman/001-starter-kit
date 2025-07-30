#!/bin/bash
#
# Wrapper script for fix-deployment-issues.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./fix-deployment-issues-wrapper.sh <stack-name> [aws-region]
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the maintenance suite
source "$LIB_DIR/modules/maintenance/maintenance-suite.sh"

# Parse arguments
STACK_NAME="${1:-}"
AWS_REGION="${2:-us-east-1}"

# Validate arguments
if [[ -z "$STACK_NAME" ]]; then
    echo "Usage: $0 <stack-name> [aws-region]"
    echo ""
    echo "This script fixes common deployment issues including:"
    echo "  - Disk space exhaustion"
    echo "  - EFS mount failures"
    echo "  - Parameter Store integration"
    echo "  - Docker optimization"
    exit 1
fi

# Run maintenance suite with fix operation
echo "Running deployment fixes for stack: $STACK_NAME in region: $AWS_REGION"
echo "This is a compatibility wrapper calling the new maintenance suite."
echo ""

# Execute maintenance operation
run_maintenance \
    --operation=fix \
    --target=deployment \
    --stack-name="$STACK_NAME" \
    --region="$AWS_REGION" \
    --auto-detect \
    --verbose \
    || {
        echo "ERROR: Failed to fix deployment issues" >&2
        exit 1
    }

echo ""
echo "Deployment fixes completed. Use 'make maintenance-fix' for the new interface."