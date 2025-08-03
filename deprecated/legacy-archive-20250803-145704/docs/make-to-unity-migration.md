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
