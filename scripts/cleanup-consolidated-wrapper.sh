#!/bin/bash
#
# Wrapper script for cleanup-consolidated.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: 
#   ./cleanup-consolidated-wrapper.sh [--force] [--dry-run] STACK_NAME
#   ./cleanup-consolidated-wrapper.sh --mode efs "pattern-*"
#   ./cleanup-consolidated-wrapper.sh --mode failed-deployments
#   ./cleanup-consolidated-wrapper.sh --mode specific --efs --instances STACK_NAME
#   ./cleanup-consolidated-wrapper.sh --mode codebase
#

set -euo pipefail

# Handle benchmark mode
if [[ "${1:-}" == "--benchmark-mode" ]]; then
    export BENCHMARK_MODE=1
    shift
    # For benchmarking, run with minimal output and quick execution
    exec >/dev/null 2>&1
fi

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the maintenance suite
source "$LIB_DIR/modules/maintenance/maintenance-suite.sh"

# Parse arguments - maintain backward compatibility
FORCE=false
DRY_RUN=false
MODE="stack"
STACK_NAME=""
PATTERN=""
SPECIFIC_RESOURCES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --efs)
            SPECIFIC_RESOURCES+=("efs")
            shift
            ;;
        --instances)
            SPECIFIC_RESOURCES+=("ec2")
            shift
            ;;
        --security-groups)
            SPECIFIC_RESOURCES+=("security-groups")
            shift
            ;;
        --load-balancers)
            SPECIFIC_RESOURCES+=("alb")
            shift
            ;;
        --cloudfront)
            SPECIFIC_RESOURCES+=("cloudfront")
            shift
            ;;
        --iam)
            SPECIFIC_RESOURCES+=("iam")
            shift
            ;;
        --volumes)
            SPECIFIC_RESOURCES+=("ebs")
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options] [STACK_NAME|PATTERN]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Options:"
            echo "  --force              Skip confirmation prompts"
            echo "  --dry-run            Show what would be cleaned without doing it"
            echo "  --mode MODE          Cleanup mode: stack|efs|failed-deployments|specific|codebase"
            echo ""
            echo "Specific resources (with --mode specific):"
            echo "  --efs               Clean EFS resources"
            echo "  --instances         Clean EC2 instances"
            echo "  --security-groups   Clean security groups"
            echo "  --load-balancers    Clean ALBs"
            echo "  --cloudfront        Clean CloudFront distributions"
            echo "  --iam               Clean IAM resources"
            echo "  --volumes           Clean EBS volumes"
            echo ""
            echo "Examples:"
            echo "  $0 my-stack                                    # Clean all resources for stack"
            echo "  $0 --mode efs 'test-*'                         # Clean EFS by pattern"
            echo "  $0 --mode failed-deployments                   # Clean failed deployment EFS"
            echo "  $0 --mode specific --efs --instances my-stack  # Clean specific resources"
            echo "  $0 --mode codebase                             # Clean local files"
            exit 0
            ;;
        *)
            if [[ -z "$STACK_NAME" && -z "$PATTERN" ]]; then
                if [[ "$MODE" == "efs" ]]; then
                    PATTERN="$1"
                else
                    STACK_NAME="$1"
                fi
            fi
            shift
            ;;
    esac
done

# Build maintenance suite arguments
MAINTENANCE_ARGS=(
    "--operation=cleanup"
)

# Add mode-specific arguments
case "$MODE" in
    stack)
        if [[ -z "$STACK_NAME" ]]; then
            echo "ERROR: Stack name required for stack mode" >&2
            exit 1
        fi
        MAINTENANCE_ARGS+=("--scope=stack" "--stack-name=$STACK_NAME")
        ;;
    efs)
        if [[ -z "$PATTERN" ]]; then
            echo "ERROR: Pattern required for EFS mode" >&2
            exit 1
        fi
        MAINTENANCE_ARGS+=("--scope=efs" "--pattern=$PATTERN")
        ;;
    failed-deployments)
        MAINTENANCE_ARGS+=("--scope=failed-deployments")
        ;;
    specific)
        if [[ -z "$STACK_NAME" ]]; then
            echo "ERROR: Stack name required for specific mode" >&2
            exit 1
        fi
        MAINTENANCE_ARGS+=("--scope=specific" "--stack-name=$STACK_NAME")
        for resource in "${SPECIFIC_RESOURCES[@]}"; do
            MAINTENANCE_ARGS+=("--resource=$resource")
        done
        ;;
    codebase)
        MAINTENANCE_ARGS+=("--scope=codebase")
        ;;
    *)
        echo "ERROR: Invalid mode: $MODE" >&2
        exit 1
        ;;
esac

# Add optional flags
[[ "$FORCE" == "true" ]] && MAINTENANCE_ARGS+=("--force")
[[ "$DRY_RUN" == "true" ]] && MAINTENANCE_ARGS+=("--dry-run")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-cleanup' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Cleanup operation failed" >&2
    exit 1
}