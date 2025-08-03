#!/bin/bash
# Port Makefile targets to Unity CLI
# Creates Unity-compatible commands for all legacy Makefile targets

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log function
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Create Unity make compatibility script
create_unity_make_compatibility() {
    log "Creating Unity make compatibility script..."
    
    cat > "$PROJECT_ROOT/make" << 'EOF'
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
EOF
    
    chmod +x "$PROJECT_ROOT/make"
    log "Created Unity make compatibility script"
}

# Create make-to-unity migration guide
create_migration_guide() {
    log "Creating make-to-unity migration guide..."
    
    cat > "$PROJECT_ROOT/docs/unity/make-to-unity-migration.md" << 'EOF'
# Make to Unity Migration Guide

This guide helps you transition from Makefile commands to Unity CLI commands.

## Command Translation Table

| Makefile Target | Unity Command | Description |
|-----------------|---------------|-------------|
| `make deploy-spot` | `./unity deploy spot [stack]` | Deploy spot instance (70% savings) |
| `make deploy-alb` | `./unity deploy alb [stack]` | Deploy with Application Load Balancer |
| `make deploy-cdn` | `./unity deploy cdn [stack]` | Deploy with CloudFront CDN |
| `make deploy-full` | `./unity deploy full [stack]` | Deploy complete stack |
| `make destroy` | `./unity destroy [stack]` | Destroy all resources |
| `make test` | `./unity test` | Run Unity tests |
| `make test-integration` | `./tests/unity/test-unity-complete-system.sh` | Run integration tests |
| `make clean` | `./unity maintain cleanup` | Clean up resources |
| `make help` | `./unity help` | Show help |

## Environment Variables

### Legacy Makefile Variables
```bash
STACK_NAME=prod-stack make deploy-spot
ENVIRONMENT=production make deploy-alb
AWS_REGION=eu-west-1 make deploy-full
```

### Unity Equivalents
```bash
./unity deploy spot prod-stack --environment production
./unity deploy alb prod-stack --region eu-west-1
./unity deploy full prod-stack --strategy blue-green
```

## Advanced Unity Features

Unity provides many features not available in the Makefile:

### Deployment Strategies
```bash
./unity deploy spot my-stack --strategy rolling
./unity deploy alb my-stack --strategy blue-green
./unity deploy full my-stack --strategy canary
```

### Service Management
```bash
./unity service list                    # List all services
./unity service status aws              # Check AWS service
./unity service restart docker          # Restart Docker service
```

### Configuration Management
```bash
./unity config show                     # Show all configuration
./unity config get aws.region           # Get specific value
./unity config set aws.region us-west-2 # Set configuration
./unity config validate                 # Validate configuration
```

### Monitoring and Logs
```bash
./unity monitor my-stack                # Real-time monitoring
./unity logs my-stack                   # View deployment logs
./unity monitor health                  # System health check
```

### Plugin Management
```bash
./unity plugin list                     # List available plugins
./unity plugin enable spot-optimizer    # Enable plugin
./unity plugin config cost-analyzer     # Configure plugin
```

## Migration Steps

1. **Use the compatibility script** (optional):
   ```bash
   ./make deploy-spot  # Works like before, redirects to Unity
   ```

2. **Transition to Unity directly**:
   ```bash
   ./unity deploy spot my-stack
   ```

3. **Explore Unity features**:
   ```bash
   ./unity help
   ./unity help deploy
   ```

## Benefits of Unity

1. **Event-Driven**: All operations emit events for monitoring
2. **Service Architecture**: Modular, maintainable services
3. **Better Error Handling**: Comprehensive error recovery
4. **Cost Optimization**: Built-in spot instance optimization
5. **Unified Interface**: Single CLI for all operations
6. **Advanced Features**: Deployment strategies, monitoring, plugins

## Compatibility Mode

For teams transitioning gradually, the `./make` compatibility script provides a bridge:

```bash
# Old way (still works)
make deploy-spot

# New way (recommended)
./unity deploy spot my-stack
```

Both commands achieve the same result, but Unity provides more options and better feedback.

## Getting Help

- Unity help: `./unity help`
- Unity docs: `docs/unity/`
- Test Unity: `./unity test`
- Unity status: `./unity status`
EOF
    
    log "Created migration guide"
}

# Update README to mention Unity
update_readme() {
    log "Updating README to emphasize Unity..."
    
    # Check if README exists
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        # Create backup
        cp "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/README.md.bak"
        
        # Add Unity section at the top if not already present
        if ! grep -q "Unity Deployment System" "$PROJECT_ROOT/README.md"; then
            cat > "$PROJECT_ROOT/README.md.tmp" << 'EOF'
# GeuseMaker - AI Stack on AWS

## 🚀 Unity Deployment System

GeuseMaker now uses the Unity event-driven deployment system for all operations.

### Quick Start

```bash
# Deploy with 70% cost savings
./unity deploy spot my-ai-stack

# Deploy with load balancer
./unity deploy alb prod-stack

# Full deployment
./unity deploy full prod-stack
```

### Legacy Makefile Support

For backward compatibility, you can still use make commands:
```bash
make deploy-spot  # Redirects to: ./unity deploy spot
```

See the [Unity Documentation](docs/unity/) for complete details.

---

EOF
            
            # Append the rest of the original README
            grep -v "^# GeuseMaker" "$PROJECT_ROOT/README.md" >> "$PROJECT_ROOT/README.md.tmp"
            mv "$PROJECT_ROOT/README.md.tmp" "$PROJECT_ROOT/README.md"
            
            log "Updated README with Unity information"
        fi
    fi
}

# Create Unity aliases for common operations
create_unity_aliases() {
    log "Creating Unity command aliases..."
    
    cat > "$PROJECT_ROOT/scripts/unity-aliases.sh" << 'EOF'
#!/bin/bash
# Unity aliases for common operations
# Source this file to use shortcuts: source scripts/unity-aliases.sh

# Deployment aliases
alias uds='./unity deploy spot'
alias uda='./unity deploy alb'
alias udc='./unity deploy cdn'
alias udf='./unity deploy full'
alias udd='./unity destroy'

# Service management
alias usl='./unity service list'
alias uss='./unity service status'
alias usr='./unity service restart'

# Monitoring
alias um='./unity monitor'
alias ul='./unity logs'
alias us='./unity status'

# Configuration
alias ucg='./unity config get'
alias ucs='./unity config set'
alias ucv='./unity config validate'

# Help
alias uh='./unity help'

echo "Unity aliases loaded! Examples:"
echo "  uds my-stack     # Deploy spot instance"
echo "  us my-stack      # Check status"
echo "  usl              # List services"
echo "  uh               # Get help"
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/unity-aliases.sh"
    log "Created Unity aliases script"
}

# Summary report
create_summary() {
    log "Creating porting summary..."
    
    cat > "$PROJECT_ROOT/MAKEFILE_PORTING_COMPLETE.txt" << EOF
Makefile to Unity Porting Complete!
===================================

Date: $(date)

What was done:
1. Created Unity make compatibility script: ./make
2. Created migration guide: docs/unity/make-to-unity-migration.md
3. Updated README with Unity information
4. Created Unity aliases: scripts/unity-aliases.sh

How to use:
- Old way: make deploy-spot (still works, redirects to Unity)
- New way: ./unity deploy spot my-stack (recommended)

All Makefile functionality is now available through Unity CLI.

For help:
- ./make help (shows translation table)
- ./unity help (full Unity documentation)

Unity is now the primary deployment interface for GeuseMaker!
EOF
    
    cat "$PROJECT_ROOT/MAKEFILE_PORTING_COMPLETE.txt"
}

# Main execution
main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Makefile to Unity Porting Tool                     ║"
    echo "║          Creating Compatibility and Migration                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Execute porting steps
    create_unity_make_compatibility
    create_migration_guide
    update_readme
    create_unity_aliases
    create_summary
    
    echo ""
    echo -e "${GREEN}✓ Makefile porting completed successfully!${NC}"
    echo ""
    echo "You can now use:"
    echo "  - ./make deploy-spot (compatibility mode)"
    echo "  - ./unity deploy spot my-stack (recommended)"
    echo ""
}

# Run main
main "$@"