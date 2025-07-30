# Backup Procedures Guide

This document provides comprehensive guidance for using the backup system implemented in Story 1.4.

## Overview

The backup system provides comprehensive backup and restoration capabilities for the AWS Deployment System, ensuring data safety during system enhancements and maintenance.

## Backup System Components

### Core Scripts

1. **`scripts/backup-system.sh`** - Main backup orchestration script
2. **`scripts/verify-backup.sh`** - Backup integrity verification
3. **`scripts/restore-backup.sh`** - Backup restoration

### Backup Structure

```
backup/
├── 20241219_143022/           # Timestamped backup directory
│   ├── backup-20241219_143022.tar.gz  # Compressed backup archive
│   ├── backup-checksum.sha256         # Integrity checksum
│   └── backup-metadata.json           # Backup metadata
└── pre-restore-20241219_150000/       # Pre-restore backup
    ├── pre-restore-20241219_150000.tar.gz
    ├── pre-restore-checksum.sha256
    └── pre-restore-metadata.json
```

## Backup Scope

The backup system includes:

- **Scripts**: All deployment and utility scripts
- **Libraries**: Core library modules and functions
- **Configuration**: Environment and deployment configurations
- **Documentation**: Project documentation and guides
- **Tests**: Test suites and validation scripts
- **Project Files**: README, Makefile, and other project files

## Usage Guide

### Creating Backups

#### Basic Backup Creation
```bash
# Create a new backup
./scripts/backup-system.sh create

# This will:
# 1. Initialize backup system
# 2. Create compressed archive
# 3. Generate checksum for integrity
# 4. Create metadata with system information
# 5. Verify backup integrity
```

#### Backup with Custom Scope
```bash
# Backup specific components only
BACKUP_SCOPE=("scripts/" "lib/") ./scripts/backup-system.sh create
```

### Verifying Backups

#### Verify Latest Backup
```bash
# Verify the most recent backup
./scripts/backup-system.sh verify
```

#### Verify Specific Backup
```bash
# Verify a specific backup by timestamp
./scripts/verify-backup.sh 20241219_143022
```

#### Verify All Backups
```bash
# Verify all available backups
./scripts/verify-backup.sh
```

### Listing Backups

#### List Available Backups
```bash
# List all available backups with details
./scripts/backup-system.sh list

# Output example:
# Available backups:
#   20241219_143022 (15.2M)
#   20241219_150000 (14.8M)
```

### Restoring from Backups

#### List Available Backups for Restoration
```bash
# List backups available for restoration
./scripts/restore-backup.sh list
```

#### Restore from Backup
```bash
# Restore from a specific backup
./scripts/restore-backup.sh restore 20241219_143022

# This will:
# 1. Verify backup integrity
# 2. Create backup of current state
# 3. Extract backup archive
# 4. Verify restoration
```

### Backup Maintenance

#### Clean Up Old Backups
```bash
# Remove backups older than 7 days (default)
./scripts/backup-system.sh cleanup

# Remove backups older than 30 days
./scripts/backup-system.sh cleanup 30
```

## Backup Metadata

Each backup includes comprehensive metadata:

```json
{
    "backup_timestamp": "20241219_143022",
    "backup_version": "1.0",
    "project_root": "/path/to/project",
    "backup_scope": ["scripts/", "lib/", "config/", "docs/"],
    "system_info": {
        "hostname": "deployment-server",
        "user": "deploy-user",
        "bash_version": "3.x+",
        "os": "Linux",
        "os_version": "5.15.0"
    },
    "backup_checksum": "sha256:abc123...",
    "backup_size": 15923456,
    "compression_ratio": 0.85
}
```

## Safety Features

### Pre-Restore Backups
- Automatic creation of current state backup before restoration
- Prevents data loss during restoration process
- Allows rollback if restoration fails

### Integrity Verification
- SHA256 checksums for all backup archives
- Archive extraction testing
- Metadata validation
- Size verification

### Confirmation Prompts
- User confirmation required for restoration
- Clear warnings about data overwrite
- Backup information display before restoration

## Best Practices

### Regular Backups
```bash
# Create daily backups
0 2 * * * /path/to/project/scripts/backup-system.sh create

# Clean up old backups weekly
0 3 * * 0 /path/to/project/scripts/backup-system.sh cleanup 7
```

### Before Major Changes
```bash
# Always create backup before system changes
./scripts/backup-system.sh create

# Verify backup integrity
./scripts/verify-backup.sh

# Proceed with changes
```

### Testing Restoration
```bash
# Test restoration in safe environment
# 1. Create test directory
mkdir test-restore
cd test-restore

# 2. Restore backup to test location
./scripts/restore-backup.sh restore 20241219_143022

# 3. Verify restored system
./scripts/validate-environment.sh
```

## Troubleshooting

### Common Issues

#### Backup Creation Fails
```bash
# Check disk space
df -h

# Check file permissions
ls -la scripts/backup-system.sh

# Check dependencies
which tar jq sha256sum
```

#### Verification Fails
```bash
# Check backup files exist
ls -la backup/20241219_143022/

# Verify checksum manually
cd backup/20241219_143022/
sha256sum -c backup-checksum.sha256
```

#### Restoration Fails
```bash
# Check backup integrity first
./scripts/verify-backup.sh 20241219_143022

# Check disk space for restoration
df -h

# Verify file permissions
ls -la scripts/restore-backup.sh
```

### Recovery Procedures

#### Corrupted Backup
```bash
# Remove corrupted backup
rm -rf backup/20241219_143022/

# Create new backup
./scripts/backup-system.sh create
```

#### Failed Restoration
```bash
# Use pre-restore backup to recover
./scripts/restore-backup.sh restore pre-restore-20241219_150000
```

## Monitoring and Alerting

### Backup Monitoring
```bash
# Check backup status
./scripts/backup-system.sh list

# Monitor backup directory size
du -sh backup/

# Check for failed backups
find backup/ -name "*.log" -exec grep -l "ERROR" {} \;
```

### Automated Alerts
```bash
#!/bin/bash
# backup-monitor.sh

# Check if recent backup exists
latest_backup=$(ls -t backup/*/ 2>/dev/null | head -1)
if [[ -z "${latest_backup}" ]]; then
    echo "ALERT: No backups found"
    exit 1
fi

# Check backup age (older than 24 hours)
backup_time=$(basename "${latest_backup}")
current_time=$(date +%Y%m%d_%H%M%S)
# Add logic to compare timestamps and alert if too old
```

## Integration with Deployment

### Pre-Deployment Backup
```bash
#!/bin/bash
# pre-deployment.sh

# Create backup before deployment
./scripts/backup-system.sh create

# Verify backup
./scripts/verify-backup.sh

# Proceed with deployment
./scripts/aws-deployment-modular.sh "$@"
```

### Post-Deployment Verification
```bash
#!/bin/bash
# post-deployment.sh

# Verify system after deployment
./scripts/validate-environment.sh

# If verification fails, restore from backup
if [[ $? -ne 0 ]]; then
    echo "Deployment verification failed, restoring from backup..."
    ./scripts/restore-backup.sh restore $(ls -t backup/*/ | head -1 | xargs basename)
fi
```

## Security Considerations

### Backup Security
- Backups contain sensitive configuration data
- Store backups in secure location
- Encrypt backups for sensitive environments
- Implement access controls for backup directory

### Access Control
```bash
# Restrict backup directory access
chmod 750 backup/
chown deploy-user:deploy-group backup/

# Secure backup scripts
chmod 750 scripts/backup-system.sh
chmod 750 scripts/restore-backup.sh
```

## Performance Considerations

### Backup Performance
- Compression reduces backup size by ~85%
- Incremental backups not implemented (future enhancement)
- Parallel processing for large file sets (future enhancement)

### Storage Optimization
```bash
# Monitor backup storage usage
du -sh backup/*/

# Clean up old backups automatically
./scripts/backup-system.sh cleanup 7

# Compress old backups (if needed)
find backup/ -name "*.tar.gz" -mtime +30 -exec gzip -9 {} \;
```

## Future Enhancements

### Planned Features
1. **Incremental Backups**: Only backup changed files
2. **Remote Storage**: Backup to S3 or other cloud storage
3. **Encryption**: Encrypt backup archives
4. **Scheduling**: Built-in backup scheduling
5. **Monitoring**: Integration with monitoring systems

### Enhancement Scripts
```bash
# Future: Incremental backup
./scripts/backup-system.sh incremental

# Future: Remote backup
./scripts/backup-system.sh remote s3://backup-bucket/

# Future: Encrypted backup
./scripts/backup-system.sh encrypted --key-file backup.key
```

---

**Document Version**: 1.0  
**Last Updated**: $(date +%Y-%m-%d)  
**Story**: 1.4 - Backup Strategy Implementation 