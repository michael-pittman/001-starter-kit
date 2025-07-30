# Maintenance Suite Safety Features Guide

## Overview

The GeuseMaker Maintenance Suite includes comprehensive safety features to protect your deployment from accidental damage during maintenance operations. This guide covers all safety mechanisms including backup, rollback, dry-run mode, destructive operation warnings, and notification systems.

## Table of Contents

1. [Safety Features Overview](#safety-features-overview)
2. [Dry-Run Mode](#dry-run-mode)
3. [Destructive Operation Warnings](#destructive-operation-warnings)
4. [Backup System](#backup-system)
5. [Rollback Mechanisms](#rollback-mechanisms)
6. [Notification System](#notification-system)
7. [Safety Validations](#safety-validations)
8. [Best Practices](#best-practices)

## Safety Features Overview

The maintenance suite provides multiple layers of protection:

- **Dry-Run Mode**: Preview changes without making them
- **Destructive Warnings**: Multi-step confirmation for dangerous operations
- **Automatic Backups**: Safety backups before changes
- **Rollback Support**: Restore to previous state on failure
- **Notifications**: Real-time alerts for operations
- **Safety Checks**: Pre-operation validation
- **Concurrent Lock**: Prevents multiple operations

## Dry-Run Mode

### Usage

Add `--dry-run` to any maintenance command to preview changes:

```bash
# Preview cleanup operations
run_maintenance --operation=cleanup --scope=all --dry-run

# Preview fix operations
run_maintenance --operation=fix --target=deployment --dry-run

# Preview update operations
run_maintenance --operation=update --component=docker --dry-run
```

### What Dry-Run Shows

- Files that would be deleted
- Services that would be restarted
- Resources that would be modified
- Estimated impact (space freed, etc.)
- Configuration changes

### Example Output

```
[DRY RUN] Would cleanup logs
Items to remove:
  - /var/log/app.log (2.5GB)
  - /var/log/debug.log (500MB)
  - 15 archived logs (3.2GB total)

Estimated space to be freed: 6.2GB
```

## Destructive Operation Warnings

### Destructive Operations

The following operations are considered destructive:

- `cleanup:aws` - Removes AWS resources
- `cleanup:all` - Removes all cleanup targets
- `fix:deployment` - Modifies deployment configuration
- `update:dependencies` - Updates system packages
- `update:scripts` - Updates deployment scripts
- `rollback:*` - Restores previous state
- `restore:*` - Restores from backup

### Warning Display

Destructive operations show prominent warnings:

```
╔══════════════════════════════════════════════════════════════╗
║                    ⚠️  DESTRUCTIVE OPERATION ⚠️                ║
╚══════════════════════════════════════════════════════════════╝

Operation: cleanup
Target: all

This operation will permanently delete resources.
Deleted data cannot be recovered without a backup.

Estimated Impact:
- Docker images: 15
- Containers: 3
- Volumes: 5

To proceed, you must:
1. Type the operation name: cleanup
2. Type the target name: all
3. Type 'CONFIRM' to proceed
```

### Bypassing Confirmations

For automation, use `--force` to skip confirmations:

```bash
# Force operation without confirmation (use with caution!)
run_maintenance --operation=cleanup --scope=all --force
```

## Backup System

### Automatic Backups

Backups are automatically created for:
- All destructive operations (unless disabled)
- When `--backup` flag is used
- Before rollback operations

### Manual Backup Operations

```bash
# Create full backup
run_maintenance --operation=backup --action=create

# Create compressed backup
run_maintenance --operation=backup --action=create --compress

# List available backups
run_maintenance --operation=backup --action=list

# Verify backup integrity
run_maintenance --operation=backup --action=verify

# Restore from backup
run_maintenance --operation=backup --action=restore --backup-id=20240120_143022

# Clean old backups (older than 7 days)
run_maintenance --operation=backup --action=cleanup
```

### Backup Structure

```
backup/
├── 20240120_143022/
│   ├── backup-metadata.json      # Backup information
│   ├── backup-checksum.sha256    # Integrity verification
│   ├── backup-manifest.txt       # File list
│   ├── backup-20240120_143022.tar.gz  # Actual backup
│   └── docker-volumes/           # Docker volume backups
└── latest -> 20240120_143022     # Symlink to latest backup
```

### Backup Metadata

Each backup includes metadata with:
- Timestamp and version
- System information
- Stack configuration
- File count and size
- Compression ratio

## Rollback Mechanisms

### Automatic Rollback

Enable automatic rollback on failure:

```bash
# Rollback on operation failure
run_maintenance --operation=update --component=docker --rollback
```

### Manual Rollback

Restore from a specific backup:

```bash
# Rollback to latest backup
run_maintenance --operation=backup --action=restore

# Rollback to specific backup
run_maintenance --operation=backup --action=restore --backup-id=20240120_143022
```

### Rollback Process

1. Verify backup integrity
2. Create pre-rollback backup
3. Stop affected services
4. Restore files and configurations
5. Restore Docker volumes (if present)
6. Fix permissions
7. Restart services

## Notification System

### Configuration

Set environment variables for notifications:

```bash
# Webhook notifications
export WEBHOOK_URL="https://your-webhook.com/endpoint"

# Email notifications
export MAINTENANCE_EMAIL="ops@example.com"

# Slack notifications
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

### Enabling Notifications

```bash
# Enable notifications for operation
run_maintenance --operation=cleanup --scope=all --notify

# Test notification system
run_maintenance --operation=backup --action=test-notifications
```

### Notification Types

1. **Operation Start**: When maintenance begins
2. **Progress Updates**: During long operations
3. **Completion Status**: Success/failure summary
4. **Safety Warnings**: When safety checks trigger
5. **Critical Errors**: System failures
6. **Backup Status**: Backup creation/restore
7. **Rollback Status**: Rollback progress

### Notification Format

```json
{
    "timestamp": "2024-01-20T14:30:22Z",
    "level": "info",
    "emoji": "🚀",
    "title": "Maintenance Operation Started",
    "message": "Starting cleanup operation on all",
    "details": "Operation: cleanup\nTarget: all\nDry Run: false",
    "host": "prod-server",
    "user": "admin",
    "stack": "prod-stack"
}
```

## Safety Validations

### Pre-Operation Checks

Before any operation, the system performs:

1. **Lock Check**: Ensures no concurrent operations
2. **System Load**: Verifies system isn't overloaded
3. **Critical Files**: Checks file integrity
4. **Running Services**: Identifies active containers
5. **Disk Space**: Ensures adequate free space
6. **Backup Availability**: Verifies rollback capability

### Critical File Protection

Protected files require extra confirmation:
- `.env`
- `docker-compose.yml`
- `docker-compose.gpu-optimized.yml`
- `config/production.yml`
- Core deployment scripts

### Resource Thresholds

- Maximum cleanup size: 10GB
- Maximum files to delete: 1000
- Minimum free space required: 5GB
- Backup retention: 30 days

## Best Practices

### 1. Always Use Dry-Run First

```bash
# Preview before executing
run_maintenance --operation=cleanup --scope=all --dry-run
# If satisfied, run without dry-run
run_maintenance --operation=cleanup --scope=all --backup
```

### 2. Enable Backups for Critical Operations

```bash
# Always backup before major changes
run_maintenance --operation=update --component=dependencies --backup --rollback
```

### 3. Set Up Notifications

```bash
# Configure webhooks for production
export WEBHOOK_URL="https://monitoring.example.com/webhook"
export MAINTENANCE_NOTIFY=true
```

### 4. Regular Backup Maintenance

```bash
# Weekly backup cleanup
run_maintenance --operation=backup --action=cleanup --days=7

# Verify backup integrity
run_maintenance --operation=backup --action=verify
```

### 5. Use Appropriate Flags

- `--dry-run`: Always preview first
- `--backup`: For any data modification
- `--rollback`: For critical updates
- `--notify`: For production operations
- `--verbose`: For troubleshooting

### 6. Monitor Operation State

Check operation status:
```bash
cat .maintenance-state | jq .
```

### 7. Review Logs

```bash
# Check maintenance logs
tail -f /var/log/GeuseMaker-maintenance.log

# Check notification logs
tail -f logs/maintenance-notifications.log
```

## Emergency Procedures

### Failed Operation Recovery

1. Check state file:
   ```bash
   cat .maintenance-state | jq .
   ```

2. Review logs for errors:
   ```bash
   grep ERROR /var/log/GeuseMaker-maintenance.log
   ```

3. Perform manual rollback if needed:
   ```bash
   run_maintenance --operation=backup --action=restore --force
   ```

### Stuck Operation

1. Remove lock file:
   ```bash
   rm -f .maintenance-state.lock
   ```

2. Update state:
   ```bash
   echo '{"status": "interrupted"}' > .maintenance-state
   ```

3. Verify system state:
   ```bash
   run_maintenance --operation=health --service=all
   ```

### Data Recovery

1. List available backups:
   ```bash
   run_maintenance --operation=backup --action=list
   ```

2. Verify backup integrity:
   ```bash
   run_maintenance --operation=backup --action=verify --backup-id=TIMESTAMP
   ```

3. Restore specific backup:
   ```bash
   run_maintenance --operation=backup --action=restore --backup-id=TIMESTAMP
   ```

## Testing Safety Features

Run the safety test suite:

```bash
./tests/test-maintenance-safety.sh
```

This tests:
- Dry-run mode functionality
- Destructive operation warnings
- Backup creation and restore
- Rollback mechanisms
- Notification delivery
- Safety validations
- Error handling

## Summary

The maintenance suite's safety features provide comprehensive protection against accidental damage. By following these guidelines and using the appropriate safety flags, you can confidently perform maintenance operations while minimizing risk to your production environment.

Remember: **When in doubt, use --dry-run first!**