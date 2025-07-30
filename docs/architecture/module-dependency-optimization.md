# Module Dependency Optimization Guide

## Overview

This guide provides recommendations for optimizing module dependencies in the GeuseMaker project to reduce complexity and improve maintainability.

## Current State Analysis

### Dependency Statistics
- **Total Modules**: 35
- **Standalone Modules**: 20 (57%)
- **Modules with Dependencies**: 15 (43%)
- **Most Depended Upon**: `core/errors.sh` (12 dependents)
- **No Circular Dependencies**: ✅

### Dependency Layers
```
Layer 0: Foundation (No Dependencies)
├── core/errors.sh
├── core/registry.sh
├── config/variables.sh
├── core/logging.sh
├── core/validation.sh
└── core/variables.sh

Layer 1: Basic Dependencies
├── infrastructure/* → [registry, errors]
├── compute/* → [registry, errors]
└── deployment/* → [variables or errors]

Layer 2: Complex Dependencies
├── instances/launch.sh → [registry, errors, variables, ami]
├── application/* → [registry, errors, variables]
└── monitoring/health.sh → [errors, launch.sh]
```

## Optimization Strategies

### 1. Use Base Modules for Common Patterns

**Problem**: Repetitive dependency declarations across similar modules.

**Solution**: Create base modules that encapsulate common dependencies.

```bash
# Before (in every application module):
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../config/variables.sh"

# After:
source "${SCRIPT_DIR}/base.sh"  # Contains all three dependencies
```

**Implemented Base Modules**:
- `/lib/modules/application/base.sh` - For application modules
- `/lib/modules/infrastructure/base.sh` - For infrastructure modules

### 2. Use Dependency Groups

**Problem**: Different modules need different combinations of core dependencies.

**Solution**: Create standardized dependency groups.

```bash
# In your module:
source "${MODULES_DIR}/core/dependency-groups.sh"

# Then use appropriate group:
source_error_handling           # Just errors.sh
source_resource_management      # registry.sh + errors.sh
source_application_stack        # registry.sh + errors.sh + variables.sh
source_configuration_stack      # errors.sh + variables.sh
source_instance_management      # All core + ami.sh
```

**Location**: `/lib/modules/core/dependency-groups.sh`

### 3. Extract Shared Functionality

**Problem**: Cross-layer dependencies (e.g., monitoring depending on instances).

**Solution**: Extract common functions to core utilities.

```bash
# Before: monitoring/health.sh depends on instances/launch.sh
source "${SCRIPT_DIR}/../instances/launch.sh"  # Cross-layer dependency

# After: Both use core utilities
source "${SCRIPT_DIR}/../core/instance-utils.sh"  # Shared utilities
```

**Created**: `/lib/modules/core/instance-utils.sh` with common instance functions.

### 4. Implement Lazy Loading

**Problem**: Optional dependencies loaded unnecessarily.

**Solution**: Use the `load_if_available` helper.

```bash
# In your module:
source "${MODULES_DIR}/core/dependency-groups.sh"

# Load optional module only if available
if load_if_available "deployment/rollback.sh"; then
    echo "Rollback support enabled"
fi
```

### 5. Standardize External Dependencies

**Problem**: Inconsistent patterns for external library dependencies.

**Solution**: Move external libraries into the module structure.

```bash
# Before:
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# After: Move to modules structure
source "${MODULES_DIR}/core/library-loader.sh"
```

## Migration Guide

### Phase 1: Update Application Modules
1. Add `application/base.sh` to the repository
2. Update all application modules to use the base module
3. Test each module individually

### Phase 2: Update Infrastructure Modules
1. Add `infrastructure/base.sh` to the repository
2. Update infrastructure modules to use the base module
3. Validate infrastructure deployments

### Phase 3: Fix Cross-Layer Dependencies
1. Update `monitoring/health.sh` to use `core/instance-utils.sh`
2. Update `instances/launch.sh` to use `core/instance-utils.sh`
3. Remove duplicate `get_instance_details` functions

### Phase 4: Implement Dependency Groups
1. Update modules to use `dependency-groups.sh`
2. Remove direct source statements
3. Add lazy loading where appropriate

## Benefits

1. **Reduced Complexity**: Fewer direct dependencies to manage
2. **Better Maintainability**: Changes to dependencies in one place
3. **Clearer Architecture**: Explicit dependency groups
4. **Performance**: Lazy loading reduces unnecessary sourcing
5. **Consistency**: Standardized patterns across all modules

## Validation

After implementing optimizations:

```bash
# Check for remaining direct dependencies
find lib/modules -name "*.sh" -exec grep -l "source.*modules/" {} \; | wc -l

# Verify no circular dependencies
./tools/test-runner.sh unit

# Test module loading
for module in lib/modules/**/*.sh; do
    bash -n "$module" || echo "Syntax error in $module"
done
```

## Example: Optimized Module

```bash
#!/usr/bin/env bash
# Optimized module using dependency groups

# Prevent multiple sourcing
[ -n "${_MY_MODULE_LOADED:-}" ] && return 0
_MY_MODULE_LOADED=1

# Source dependency group
MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${MODULES_DIR}/core/dependency-groups.sh"

# Load appropriate dependencies
source_resource_management  # Gets registry + errors

# Optional dependency
load_if_available "monitoring/metrics.sh" && {
    echo "Metrics support enabled"
}

# Module implementation
my_function() {
    register_resource "my_resource" "active"
}

export _MY_MODULE_LOADED
```