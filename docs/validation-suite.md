# Validation Suite Documentation

## Overview

The Validation Suite is a consolidated validation framework that combines four previously separate validation scripts into a single, efficient system. It provides parameter-based execution, parallel processing, caching, retry mechanisms, and structured logging.

## Features

- **Consolidated Validation Types**: Dependencies, Environment, Modules, Network
- **Parallel Processing**: Execute multiple validations concurrently
- **Caching System**: Reduce redundant validation operations
- **Retry Mechanisms**: Automatic retry with exponential backoff
- **Structured Logging**: JSON-formatted logs for better monitoring
- **Backward Compatibility**: Existing scripts continue to work seamlessly

## Usage

### Basic Command Structure

```bash
./lib/modules/validation/validation-suite.sh --type TYPE [OPTIONS]
```

### Available Options

- `--type TYPE`: Validation type (required)
  - `dependencies`: Check system dependencies
  - `environment`: Validate environment variables
  - `modules`: Verify module consolidation
  - `network`: Test network connectivity
  - `all`: Run all validations
- `--parallel`: Enable parallel processing for multiple validations
- `--cache`: Enable caching of validation results
- `--retry`: Enable retry mechanisms for failed validations
- `--verbose, -v`: Enable verbose output
- `--help, -h`: Show help message

### Examples

#### Run Single Validation

```bash
# Check dependencies
./lib/modules/validation/validation-suite.sh --type dependencies

# Validate environment with caching
./lib/modules/validation/validation-suite.sh --type environment --cache

# Test network with retries
./lib/modules/validation/validation-suite.sh --type network --retry
```

#### Run All Validations

```bash
# Sequential execution
./lib/modules/validation/validation-suite.sh --type all

# Parallel execution with caching
./lib/modules/validation/validation-suite.sh --type all --parallel --cache
```

#### Verbose Mode

```bash
# See detailed logging
./lib/modules/validation/validation-suite.sh --type all --verbose
```

## Validation Types

### Dependencies Validation

Checks for required system dependencies:
- AWS CLI (>= 2.0.0)
- jq (>= 1.5)
- Docker (>= 20.10.0)
- curl
- git

### Environment Validation

Validates critical environment variables:
- `POSTGRES_PASSWORD`
- `N8N_ENCRYPTION_KEY`
- `N8N_USER_MANAGEMENT_JWT_SECRET`

Also checks:
- System resources (memory, disk space)
- Network connectivity (optional in development mode)

### Modules Validation

Verifies that module consolidation was successful:
- Consolidated modules exist
- Compatibility wrappers are in place
- Key functions are properly migrated
- Documentation is updated

### Network Validation

Tests connectivity to critical endpoints:
- aws.amazon.com:443
- registry.docker.io:443
- github.com:443

## Configuration

### Environment Variables

- `VALIDATION_CACHE_DIR`: Cache directory (default: `$PROJECT_ROOT/.cache/validation`)
- `VALIDATION_CACHE_TTL`: Cache time-to-live in seconds (default: 3600)
- `VALIDATION_MAX_RETRIES`: Maximum retry attempts (default: 3)
- `VALIDATION_RETRY_DELAY`: Initial retry delay in seconds (default: 2)
- `VALIDATION_LOG_FILE`: Log file location (default: `/tmp/validation-suite.log`)
- `VALIDATION_MAX_PARALLEL`: Maximum parallel jobs (default: 4)

### Development Mode

Set any of these to enable development mode with relaxed requirements:
- `ENVIRONMENT=development`
- `ENVIRONMENT=dev`
- `DEPLOYMENT_MODE=development`
- `DEVELOPMENT_MODE=true`

### Skip Network Checks

To skip network validation:
- `SKIP_NETWORK_CHECK=true`
- `SKIP_NETWORK_VALIDATION=true`

## Output Format

The validation suite returns structured JSON output:

```json
{
  "status": "passed|failed",
  "output": "Detailed validation output",
  "timestamp": 1234567890
}
```

For `--type all`, the output includes all validation results:

```json
{
  "dependencies": {
    "status": "passed",
    "output": "...",
    "timestamp": 1234567890
  },
  "environment": {
    "status": "passed",
    "output": "...",
    "timestamp": 1234567890
  },
  "modules": {
    "status": "passed",
    "output": "...",
    "timestamp": 1234567890
  },
  "network": {
    "status": "passed",
    "output": "...",
    "timestamp": 1234567890
  }
}
```

## Exit Codes

- `0`: Validation passed
- `1`: Validation failed
- `2`: System error (invalid arguments, missing files, etc.)

## Backward Compatibility

The original validation scripts have been updated to delegate to the validation suite:

- `scripts/validate-environment.sh` → `--type environment`
- `scripts/check-dependencies.sh` → `--type dependencies`
- `scripts/test-network-validation.sh` → `--type network`
- `scripts/validate-module-consolidation.sh` → `--type modules`

These wrapper scripts maintain the same interface and behavior, ensuring existing workflows continue to function without modification.

## Logging

### Log Levels

- `ERROR`: Critical errors
- `WARN`: Warning messages
- `INFO`: Informational messages (verbose mode)
- `DEBUG`: Debug information (verbose mode)
- `SUCCESS`: Successful operations

### Log Format

Logs are written in structured JSON format:

```json
{
  "timestamp": "2024-01-20 12:34:56",
  "level": "INFO",
  "component": "dependencies",
  "message": "Starting dependency validation",
  "validation_type": "dependencies"
}
```

### Log Location

Default: `/tmp/validation-suite.log`

Override with: `VALIDATION_LOG_FILE=/path/to/custom.log`

## Performance

### Parallel Processing

When using `--type all --parallel`, validations run concurrently:
- Typical speedup: 2-3x faster than sequential
- Resource usage: Higher CPU and memory during execution
- Recommended for CI/CD pipelines

### Caching

Cache benefits:
- Subsequent runs are 10-100x faster
- Cache TTL: 1 hour (configurable)
- Cache key includes date for daily freshness
- Network validation is never cached

## Troubleshooting

### Common Issues

1. **Validation fails with "command not found"**
   - Ensure all dependencies are installed
   - Check PATH environment variable

2. **Caching doesn't seem to work**
   - Verify write permissions to cache directory
   - Check cache TTL hasn't expired
   - Network validation is never cached

3. **Parallel execution shows no speedup**
   - Some validations may be I/O bound
   - Check system resources (CPU cores)
   - Dependencies between validations may limit parallelism

4. **Structured logs not appearing**
   - Check log file permissions
   - Verify VALIDATION_LOG_FILE path is writable

### Debug Mode

For maximum debugging information:

```bash
VALIDATION_LOG_FILE=debug.log \
./lib/modules/validation/validation-suite.sh \
  --type all \
  --verbose \
  --parallel
```

## Integration

### CI/CD Pipeline

```yaml
# GitHub Actions example
- name: Validate deployment prerequisites
  run: |
    ./lib/modules/validation/validation-suite.sh \
      --type all \
      --parallel \
      --cache
```

### Pre-deployment Script

```bash
#!/bin/bash
# Pre-deployment validation

if ! ./lib/modules/validation/validation-suite.sh --type all --parallel; then
    echo "Validation failed! Aborting deployment."
    exit 1
fi

echo "All validations passed. Proceeding with deployment..."
```

### Monitoring Integration

Parse structured logs for monitoring:

```bash
# Extract validation metrics
jq -r 'select(.level == "SUCCESS") | "\(.timestamp) \(.component): \(.message)"' \
  /tmp/validation-suite.log
```

## Best Practices

1. **Use caching in development** to speed up iterative testing
2. **Enable parallel processing** for CI/CD pipelines
3. **Use retry mechanisms** for network-dependent validations
4. **Monitor structured logs** for validation trends
5. **Run with --verbose** when troubleshooting issues
6. **Set appropriate cache TTL** based on your environment stability

## Migration Guide

### From Individual Scripts

Replace individual script calls:

```bash
# Old way
./scripts/check-dependencies.sh
./scripts/validate-environment.sh
./scripts/test-network-validation.sh
./scripts/validate-module-consolidation.sh

# New way
./lib/modules/validation/validation-suite.sh --type all --parallel
```

### Custom Integration

If you have custom scripts calling the old validation scripts:

1. Update to use validation-suite.sh directly, OR
2. Keep using old scripts (they now delegate to validation-suite.sh)

### Environment Variables

No changes required. The validation suite uses the same environment variables as the original scripts.

## Future Enhancements

Planned improvements:
- Plugin system for custom validations
- Web UI for validation results
- Prometheus metrics export
- Validation result history tracking
- Conditional validation chains
- Remote validation execution