#!/bin/bash
# Makefile compatibility layer for Unity
# Translates legacy make commands to Unity CLI

set -euo pipefail

# Default stack name
STACK_NAME="${STACK_NAME:-geusemaker-dev}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# Show usage
show_usage() {
    cat << 'USAGE'
Unity Make Compatibility

This is a compatibility wrapper that translates Makefile targets to Unity commands.

Legacy Targets:
  make deploy-spot      → ./unity deploy spot [stack]
  make deploy-alb       → ./unity deploy alb [stack]
  make deploy-cdn       → ./unity deploy cdn [stack]
  make deploy-full      → ./unity deploy full [stack]
  make destroy          → ./unity destroy [stack]
  make test             → ./unity test
  make test-unity       → ./unity test
  make clean            → ./unity maintain cleanup
  make help             → ./unity help

Environment Variables:
  STACK_NAME    - Stack name for deployment (default: geusemaker-dev)
  ENVIRONMENT   - Environment (dev/staging/prod) (default: dev)
  AWS_REGION    - AWS region (default: us-east-1)

Examples:
  make deploy-spot
  STACK_NAME=prod make deploy-alb
  make test

For full Unity CLI documentation:
  ./unity help
USAGE
}

# Main execution
case "${1:-help}" in
    deploy-spot)
        echo "Redirecting to Unity: ./unity deploy spot $STACK_NAME"
        exec ./unity deploy spot "$STACK_NAME"
        ;;
    deploy-alb)
        echo "Redirecting to Unity: ./unity deploy alb $STACK_NAME"
        exec ./unity deploy alb "$STACK_NAME"
        ;;
    deploy-cdn)
        echo "Redirecting to Unity: ./unity deploy cdn $STACK_NAME"
        exec ./unity deploy cdn "$STACK_NAME"
        ;;
    deploy-full)
        echo "Redirecting to Unity: ./unity deploy full $STACK_NAME"
        exec ./unity deploy full "$STACK_NAME"
        ;;
    destroy)
        echo "Redirecting to Unity: ./unity destroy $STACK_NAME"
        exec ./unity destroy "$STACK_NAME"
        ;;
    test|test-unity)
        echo "Redirecting to Unity: ./unity test"
        exec ./unity test
        ;;
    test-integration)
        echo "Redirecting to Unity: ./tests/unity/test-unity-complete-system.sh"
        exec ./tests/unity/test-unity-complete-system.sh
        ;;
    clean|cleanup)
        echo "Redirecting to Unity: ./unity maintain cleanup"
        exec ./scripts/unity-cli.sh maintain cleanup
        ;;
    status)
        echo "Redirecting to Unity: ./unity status $STACK_NAME"
        exec ./unity status "$STACK_NAME"
        ;;
    monitor)
        echo "Redirecting to Unity: ./unity monitor $STACK_NAME"
        exec ./unity monitor "$STACK_NAME"
        ;;
    help|--help|-h|"")
        show_usage
        ;;
    *)
        echo "Unknown target: $1"
        echo "Use './make help' for available targets"
        echo "Or use Unity directly: ./unity help"
        exit 1
        ;;
esac
