# Maintenance Suite Guide

## Overview

The GeuseMaker Maintenance Suite provides a unified interface for all maintenance operations, consolidating previously scattered maintenance scripts into a single, parameter-driven system. This guide covers the new maintenance suite and migration from legacy scripts.

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Architecture](#architecture)
4. [Operations Reference](#operations-reference)
5. [Migration Guide](#migration-guide)
6. [Examples](#examples)
7. [Troubleshooting](#troubleshooting)

## Introduction

### What's New

The maintenance suite consolidates 8+ individual maintenance scripts into a single, modular system:

- **Unified Interface**: Single entry point for all maintenance operations
- **Parameter-Driven**: Consistent parameter syntax across all operations
- **Modular Design**: Operations are organized into logical modules
- **Safety Features**: Built-in dry-run, backup, and rollback capabilities
- **Comprehensive Logging**: Structured logging with operation tracking
- **Backward Compatibility**: Wrapper scripts ensure existing workflows continue to work

### Key Benefits

1. **Consistency**: Same parameter syntax for all operations
2. **Safety**: Automatic backups and validation before destructive operations
3. **Flexibility**: Mix and match operations as needed
4. **Observability**: Comprehensive logging and state tracking
5. **Extensibility**: Easy to add new operations

## Quick Start

### Using Make Commands

The easiest way to use the maintenance suite is through Make commands:

```bash
# Fix deployment issues
make maintenance-fix STACK_NAME=my-stack

# Clean up resources
make maintenance-cleanup STACK_NAME=my-stack

# Create backup
make maintenance-backup

# Health check
make maintenance-health STACK_NAME=my-stack

# Update Docker images
make maintenance-update
```

### Direct Usage

For more control, use the maintenance suite directly:

```bash
# Source the maintenance suite
source lib/modules/maintenance/maintenance-suite.sh

# Run operations
run_maintenance --operation=fix --target=deployment --stack-name=my-stack
run_maintenance --operation=cleanup --scope=all --dry-run
run_maintenance --operation=backup --backup-type=full --compress
```

## Architecture

### Module Structure

```
lib/modules/maintenance/
├── maintenance-suite.sh              # Main entry point
├── maintenance-utilities.sh          # Common utilities
├── maintenance-fix-operations.sh     # Fix operations
├── maintenance-cleanup-operations.sh # Cleanup operations
├── maintenance-update-operations.sh  # Update operations
├── maintenance-health-operations.sh  # Health check operations
├── maintenance-backup-operations.sh  # Backup/restore operations
├── maintenance-optimization-operations.sh # Performance optimization
├── maintenance-safety-operations.sh  # Safety checks and validation
└── maintenance-notifications.sh      # Notification system
```

### Operation Flow

1. **Parameter Parsing**: Validates and parses input parameters
2. **Safety Checks**: Pre-operation validation and backups
3. **Operation Execution**: Runs the requested operation
4. **State Management**: Updates operation state
5. **Notifications**: Sends notifications if configured
6. **Logging**: Records all actions for audit

## Operations Reference

### Fix Operations

Fix common deployment and infrastructure issues.

```bash
# Fix all deployment issues
run_maintenance --operation=fix --target=deployment --stack-name=my-stack

# Fix specific issues
run_maintenance --operation=fix --target=disk-space
run_maintenance --operation=fix --target=efs-mount --stack-name=my-stack
run_maintenance --operation=fix --target=parameter-store --stack-name=my-stack
run_maintenance --operation=fix --target=docker-optimization
```

**Parameters:**
- `--target`: What to fix (deployment, disk-space, efs-mount, parameter-store, docker-optimization)
- `--stack-name`: AWS stack name (required for some targets)
- `--region`: AWS region (default: us-east-1)
- `--auto-detect`: Automatically detect and fix issues

### Cleanup Operations

Clean up AWS resources and local files.

```bash
# Clean up stack resources
run_maintenance --operation=cleanup --scope=stack --stack-name=my-stack

# Clean up by pattern
run_maintenance --operation=cleanup --scope=efs --pattern="test-*"

# Clean up failed deployments
run_maintenance --operation=cleanup --scope=failed-deployments

# Clean up specific resources
run_maintenance --operation=cleanup --scope=specific --stack-name=my-stack \
  --resource=ec2 --resource=efs --resource=iam

# Clean up local files
run_maintenance --operation=cleanup --scope=codebase
```

**Parameters:**
- `--scope`: Cleanup scope (stack, efs, failed-deployments, specific, codebase)
- `--stack-name`: AWS stack name
- `--pattern`: Pattern for resource matching
- `--resource`: Specific resource types (ec2, efs, iam, alb, cloudfront, ebs, security-groups)
- `--force`: Skip confirmation prompts
- `--dry-run`: Show what would be cleaned without doing it

### Update Operations

Update Docker images and system components.

```bash
# Update Docker images to latest
run_maintenance --operation=update --component=docker --use-latest

# Update to environment-specific versions
run_maintenance --operation=update --component=docker --environment=production

# Show current versions
run_maintenance --operation=update --component=docker --action=show

# Test image availability
run_maintenance --operation=update --component=docker --action=test
```

**Parameters:**
- `--component`: Component to update (docker, system, dependencies)
- `--environment`: Target environment (development, production, testing)
- `--use-latest`: Use latest versions instead of pinned
- `--action`: Specific action (update, show, test, restore)
- `--backup-file`: Backup file for restore action

### Health Operations

Perform comprehensive health checks.

```bash
# Full health check
run_maintenance --operation=health --stack-name=my-stack

# Specific health checks
run_maintenance --operation=health --check-type=services --stack-name=my-stack
run_maintenance --operation=health --check-type=resources
run_maintenance --operation=health --check-type=network --stack-name=my-stack

# Auto-fix detected issues
run_maintenance --operation=health --stack-name=my-stack --auto-fix
```

**Parameters:**
- `--stack-name`: AWS stack name
- `--check-type`: Specific check (services, resources, network, database, all)
- `--auto-fix`: Attempt to fix detected issues
- `--verbose`: Show detailed health information

### Backup Operations

Create and manage backups.

```bash
# Create full backup
run_maintenance --operation=backup --backup-type=full

# Create config-only backup
run_maintenance --operation=backup --backup-type=config

# Create data backup with compression
run_maintenance --operation=backup --backup-type=data --compress

# Restore from backup
run_maintenance --operation=restore --backup-file=backup/backup-20240115.tar.gz

# Verify backup
run_maintenance --operation=verify --backup-file=backup/backup-20240115.tar.gz
```

**Parameters:**
- `--backup-type`: Type of backup (full, config, data)
- `--compress`: Compress backup archive
- `--backup-file`: Backup file for restore/verify
- `--verify`: Verify backup before restore
- `--dry-run`: Show what would be restored

### Optimization Operations

Optimize system performance.

```bash
# Optimize all components
run_maintenance --operation=optimize --target=all

# Optimize specific components
run_maintenance --operation=optimize --target=docker
run_maintenance --operation=optimize --target=database
run_maintenance --operation=optimize --target=network
```

**Parameters:**
- `--target`: Optimization target (all, docker, database, network, storage)
- `--profile`: Performance profile (balanced, performance, efficiency)

### Validation Operations

Validate system configuration and integrity.

```bash
# Validate everything
run_maintenance --operation=validate --validation-type=all

# Validate specific components
run_maintenance --operation=validate --validation-type=config
run_maintenance --operation=validate --validation-type=network
run_maintenance --operation=validate --validation-type=security
run_maintenance --operation=validate --validation-type=docker-compose
```

**Parameters:**
- `--validation-type`: What to validate (all, config, network, security, docker-compose)
- `--comprehensive`: Run extended validation tests
- `--fix-issues`: Attempt to fix validation failures

## Migration Guide

### From Legacy Scripts

All legacy scripts now have wrapper scripts that call the new maintenance suite:

| Legacy Script | Wrapper Script | New Command |
|--------------|----------------|-------------|
| `fix-deployment-issues.sh` | `fix-deployment-issues-wrapper.sh` | `make maintenance-fix` |
| `cleanup-consolidated.sh` | `cleanup-consolidated-wrapper.sh` | `make maintenance-cleanup` |
| `backup-system.sh` | `backup-system-wrapper.sh` | `make maintenance-backup` |
| `restore-backup.sh` | `restore-backup-wrapper.sh` | `make maintenance-restore` |
| `verify-backup.sh` | `verify-backup-wrapper.sh` | `make maintenance-verify` |
| `health-check-advanced.sh` | `health-check-advanced-wrapper.sh` | `make maintenance-health` |
| `update-image-versions.sh` | `update-image-versions-wrapper.sh` | `make maintenance-update` |
| `simple-update-images.sh` | `simple-update-images-wrapper.sh` | `make maintenance-update-simple` |

### Migration Steps

1. **Test with Wrappers**: Use wrapper scripts to ensure compatibility
2. **Update Scripts**: Gradually update your scripts to use the new interface
3. **Update Documentation**: Update runbooks and documentation
4. **Remove Wrappers**: Once migrated, remove dependency on wrappers

### Example Migration

**Before (Legacy):**
```bash
# Fix deployment issues
./scripts/fix-deployment-issues.sh my-stack us-west-2

# Cleanup resources
./scripts/cleanup-consolidated.sh --force --dry-run my-stack

# Update images
./scripts/update-image-versions.sh update production false
```

**After (New):**
```bash
# Fix deployment issues
make maintenance-fix STACK_NAME=my-stack REGION=us-west-2

# Cleanup resources
make maintenance-cleanup STACK_NAME=my-stack FORCE=true DRY_RUN=true

# Update images
make maintenance-update ENV=production USE_LATEST=false
```

## Examples

### Common Workflows

#### Daily Maintenance
```bash
# Morning health check
make maintenance-health STACK_NAME=prod-stack

# Update development environment
make maintenance-update ENV=development USE_LATEST=true

# Evening backup
make maintenance-backup TYPE=full COMPRESS=true
```

#### Deployment Recovery
```bash
# 1. Check health
make maintenance-health STACK_NAME=my-stack

# 2. Fix issues
make maintenance-fix STACK_NAME=my-stack

# 3. Verify fixes
make maintenance-health STACK_NAME=my-stack

# 4. Clean up failed resources
make maintenance-cleanup SCOPE=failed-deployments
```

#### System Optimization
```bash
# 1. Create backup
make maintenance-backup TYPE=full

# 2. Run optimization
make maintenance-optimize TARGET=all

# 3. Validate changes
make maintenance-validate TYPE=all

# 4. Test performance
make maintenance-health STACK_NAME=my-stack VERBOSE=true
```

### Advanced Usage

#### Custom Operation Chains
```bash
# Source the suite
source lib/modules/maintenance/maintenance-suite.sh

# Chain operations
run_maintenance --operation=backup --backup-type=config && \
run_maintenance --operation=update --component=docker --use-latest && \
run_maintenance --operation=validate --validation-type=docker-compose && \
run_maintenance --operation=health --check-type=services
```

#### Conditional Operations
```bash
# Only cleanup if health check fails
if ! run_maintenance --operation=health --stack-name=my-stack; then
    run_maintenance --operation=fix --target=deployment --stack-name=my-stack
    run_maintenance --operation=cleanup --scope=failed-deployments
fi
```

#### Scheduled Maintenance
```bash
# Add to crontab
# Daily health check at 6 AM
0 6 * * * cd /path/to/project && make maintenance-health STACK_NAME=prod

# Weekly backup on Sunday at 2 AM
0 2 * * 0 cd /path/to/project && make maintenance-backup TYPE=full COMPRESS=true

# Nightly cleanup of failed deployments
0 3 * * * cd /path/to/project && make maintenance-cleanup SCOPE=failed-deployments
```

## Troubleshooting

### Common Issues

#### Operation Fails with "Library not found"
```bash
# Ensure you're in the project root
cd /path/to/project

# Use absolute paths
$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh
```

#### Permission Denied
```bash
# Make scripts executable
chmod +x scripts/*-wrapper.sh
chmod +x lib/modules/maintenance/*.sh
```

#### AWS Credentials Not Found
```bash
# Set AWS credentials
export AWS_PROFILE=your-profile
# or
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Enable debug mode
export MAINTENANCE_DEBUG=true

# Run with verbose output
run_maintenance --operation=fix --target=deployment --verbose --debug
```

### Getting Help

```bash
# Show available operations
run_maintenance --help

# Show operation-specific help
run_maintenance --operation=fix --help
run_maintenance --operation=cleanup --help

# Check suite version
run_maintenance --version
```

## Best Practices

1. **Always Use Dry-Run First**: Test destructive operations with `--dry-run`
2. **Create Backups**: Use `--backup` flag for critical operations
3. **Monitor Logs**: Check logs in `logs/maintenance/`
4. **Use Make Commands**: Prefer Make commands for common operations
5. **Validate After Updates**: Always validate after making changes
6. **Schedule Regular Maintenance**: Set up cron jobs for routine tasks

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review logs in `logs/maintenance/`
3. Run validation: `make maintenance-validate TYPE=all`
4. Report issues at: https://github.com/anthropics/claude-code/issues