# Library System Fix Guide

## Overview

This guide provides a quick reference for fixing the library system violations identified in the QA review of Story 3.1. The comprehensive action plan has been implemented as an automated script to ensure consistent and reliable fixes.

## Quick Start

### 1. Run the Fix Script (Recommended)

```bash
# Show what would be done without making changes
./scripts/fix-library-system-violations.sh --dry-run all

# Run all phases with backup and validation
./scripts/fix-library-system-violations.sh --backup --validate all

# Run specific phases
./scripts/fix-library-system-violations.sh --backup 1  # Fix core library violations
./scripts/fix-library-system-violations.sh 2           # Standardize library loader paths
```

### 2. Manual Fixes (If Needed)

For critical violations that require manual intervention:

#### Core Library Violations
```bash
# Check for violations
grep -r "source.*modules/" lib/

# Fix lib/deployment-health.sh
# Replace: source "$PROJECT_ROOT/lib/modules/core/errors.sh"
# With:   Use library loader pattern instead
```

#### Direct Source Violations
```bash
# Find scripts with direct source commands
grep -r "source.*lib/[^u]" scripts/ tests/ tools/

# Replace direct source with library loader
# Before: source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
# After:  source "$PROJECT_ROOT/lib/utils/library-loader.sh"
```

## Phase-by-Phase Guide

### Phase 1: Fix Core Library Violations (CRITICAL)
**Objective**: Fix violations in core library files that affect the entire system.

**Files to Check**:
- `lib/deployment-health.sh`
- `lib/deployment-validation.sh`
- `lib/error-recovery.sh`

**Command**:
```bash
./scripts/fix-library-system-violations.sh --backup 1
```

### Phase 2: Standardize Library Loader Paths (HIGH PRIORITY)
**Objective**: Ensure all scripts use `lib/utils/library-loader.sh` consistently.

**Files Affected**: 15+ scripts using `lib/lib-loader.sh`

**Command**:
```bash
./scripts/fix-library-system-violations.sh 2
```

### Phase 3: Complete Test Directory Coverage (HIGH PRIORITY)
**Objective**: Update all remaining test files to use the library system.

**Files to Update**:
- `tests/unit/test-library-system-usage-simple.sh`
- `tests/lib/test-aws-deployment-common.sh`
- `tests/lib/test-aws-config.sh`
- `tests/lib/test-spot-instance.sh`
- `tests/lib/test-docker-compose-installer.sh`
- `tests/lib/test-instance-libraries.sh`

**Command**:
```bash
./scripts/fix-library-system-violations.sh 3
```

### Phase 4: Complete Tools Directory Coverage (MEDIUM PRIORITY)
**Objective**: Update all remaining tools files to use the library system.

**Files to Update**:
- `tools/validate-config.sh`
- `tools/monitoring-setup.sh`
- `tools/install-deps.sh`
- `tools/validate-improvements.sh`

**Command**:
```bash
./scripts/fix-library-system-violations.sh 4
```

### Phase 5: Fix Direct Source Violations (HIGH PRIORITY)
**Objective**: Remove all direct source commands that bypass the library system.

**Files with Violations**:
- `scripts/check-dependencies.sh`
- `scripts/simple-update-images.sh`
- `scripts/test-intelligent-selection.sh`
- `scripts/cleanup-consolidated.sh`
- `scripts/validate-environment.sh`

**Command**:
```bash
./scripts/fix-library-system-violations.sh 5
```

### Phase 6: Comprehensive Testing and Validation (CRITICAL)
**Objective**: Ensure all changes work correctly and no new violations are introduced.

**Tests to Run**:
- Library system usage tests
- Individual script tests
- Validation tests

**Command**:
```bash
./scripts/fix-library-system-violations.sh --validate 6
```

### Phase 7: Documentation and File List Updates (MEDIUM PRIORITY)
**Objective**: Complete documentation and update the story with all changes.

**Actions**:
- Generate comprehensive file list
- Create validation script
- Update story documentation

**Command**:
```bash
./scripts/fix-library-system-violations.sh 7
```

### Phase 8: Final Validation and Approval (CRITICAL)
**Objective**: Ensure all acceptance criteria are met and the story can be approved.

**Validation**:
- Verify all acceptance criteria
- Run final comprehensive tests
- Update story status

**Command**:
```bash
./scripts/fix-library-system-violations.sh 8
```

## Validation Commands

### Check Current Status
```bash
# Run library system test
bash tests/unit/test-library-system-usage-simple.sh

# Check for violations
grep -r "source.*modules/" lib/ scripts/ tests/ tools/

# Find scripts not using library system
find scripts/ tests/ tools/ -name "*.sh" -exec grep -L "source.*lib/" {} \;
```

### Acceptance Criteria Validation
```bash
# AC1: All scripts in scripts/ directory use library modules
find scripts/ -name "*.sh" -exec grep -L "source.*lib/" {} \; | wc -l

# AC2: All scripts in tests/ directory use library modules
find tests/ -name "*.sh" -exec grep -L "source.*lib/" {} \; | wc -l

# AC3: All scripts in tools/ directory use library modules
find tools/ -name "*.sh" -exec grep -L "source.*lib/" {} \; | wc -l

# AC4: deploy.sh uses library modules
grep -q "source.*lib/" deploy.sh && echo "PASS" || echo "FAIL"

# AC5: No scripts bypass the library system
grep -r "source.*lib/[^u]" scripts/ tests/ tools/ | grep -v "library-loader" | wc -l

# AC6: All scripts follow standard library loading pattern
grep -r "lib/lib-loader.sh" scripts/ tests/ tools/ | wc -l
```

## Troubleshooting

### Common Issues

1. **Script Permission Denied**
   ```bash
   chmod +x scripts/fix-library-system-violations.sh
   ```

2. **Backup Creation Failed**
   ```bash
   mkdir -p backup/
   ```

3. **Library System Test Fails**
   ```bash
   # Check for specific violations
   bash tests/unit/test-library-system-usage-simple.sh
   ```

4. **Scripts Break After Changes**
   ```bash
   # Restore from backup
   cp -r backup/library-system-fix-YYYYMMDD-HHMMSS/* .
   ```

### Manual Fixes

If the automated script cannot fix certain violations:

1. **Core Library Violations**: These require manual review and careful fixes
2. **Complex Direct Source Violations**: May need context-aware replacements
3. **Test-Specific Issues**: Some test files may have unique requirements

### Rollback Plan

```bash
# If issues arise, restore from backup
BACKUP_DIR="backup/library-system-fix-$(date +%Y%m%d-%H%M%S)"
if [[ -d "$BACKUP_DIR" ]]; then
    cp -r "$BACKUP_DIR"/* .
    echo "Restored from backup: $BACKUP_DIR"
fi
```

## Success Criteria

The library system fix is complete when:

1. ✅ All core library violations are fixed
2. ✅ All scripts use consistent library loader paths
3. ✅ 100% of scripts in scripts/, tests/, and tools/ directories use the library system
4. ✅ No direct source commands bypass the library system
5. ✅ All library system tests pass
6. ✅ File List is complete and accurate
7. ✅ All acceptance criteria are met

## Next Steps

After completing the library system fixes:

1. **Update Story 3.1**: Mark all tasks as completed
2. **Update File List**: Include all modified files
3. **Run Final Tests**: Ensure everything works correctly
4. **Submit for Review**: Ready for QA approval

## Support

For issues or questions about the library system fix:

1. Check the detailed action plan in `docs/stories/3.1.update-all-scripts-to-use-library-system.story.md`
2. Review the QA results for specific violation details
3. Use the validation commands to identify remaining issues
4. Consult the troubleshooting section for common problems