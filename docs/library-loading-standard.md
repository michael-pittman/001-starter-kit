# Library Loading Standard

This document defines the standardized approach for loading libraries across all GeuseMaker scripts, ensuring consistency, reliability, and maintainability.

## Table of Contents

1. [Overview](#overview)
2. [Template Usage and Patterns](#template-usage-and-patterns)
3. [Standard Source Patterns](#standard-source-patterns)
4. [Path Resolution Logic](#path-resolution-logic)
5. [Error Handling](#error-handling)
6. [Dependency Resolution](#dependency-resolution)
7. [Best Practices](#best-practices)
8. [Migration Guide](#migration-guide)

## Overview

The library loading standard ensures consistent behavior across all scripts by:
- Providing reliable path resolution regardless of script location
- Implementing proper error handling for missing dependencies
- Optimizing loading order based on dependencies
- Supporting bash 3.x+ compatibility

## Template Usage and Patterns

### Basic Template

Every script must start with this standard header:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Core libraries (always load first)
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/error-handling.sh"

# Additional libraries as needed
# source "$PROJECT_ROOT/lib/config-management.sh"
# source "$PROJECT_ROOT/lib/aws-resource-manager.sh"
```

### Enhanced Script Template

For scripts using enhanced features:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Core libraries
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/error-handling.sh"

# Enhanced libraries with bash 3.x+ compatibility
source "$PROJECT_ROOT/lib/associative-arrays.sh"
source "$PROJECT_ROOT/lib/aws-cli-v2.sh"
```

### Module Template

For library modules that may be sourced from other scripts:

```bash
#!/usr/bin/env bash
# Module: module_name
# Description: Brief description of module functionality
# Dependencies: List required libraries

# Prevent double sourcing
[[ -n "${MODULE_NAME_LOADED:-}" ]] && return 0
declare -r MODULE_NAME_LOADED=1

# Module initialization
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    echo "Error: PROJECT_ROOT not defined. Source from a properly initialized script." >&2
    return 1
fi

# Source dependencies
source "$PROJECT_ROOT/lib/dependency1.sh"
source "$PROJECT_ROOT/lib/dependency2.sh"

# Module code here
```

## Standard Source Patterns

### Core Library Loading Order

Always load libraries in this specific order:

```bash
# 1. Logging and prerequisites
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

# 2. Error handling
source "$PROJECT_ROOT/lib/error-handling.sh"

# 3. Modern bash features (if required)
source "$PROJECT_ROOT/lib/associative-arrays.sh"

# 4. AWS utilities
source "$PROJECT_ROOT/lib/aws-cli-v2.sh"

# 5. Configuration management
source "$PROJECT_ROOT/lib/config-management.sh"

# 6. Resource management
source "$PROJECT_ROOT/lib/aws-resource-manager.sh"

# 7. Specialized libraries
source "$PROJECT_ROOT/lib/spot-instance.sh"
source "$PROJECT_ROOT/lib/deployment-validation.sh"
```

### Conditional Loading

For optional features or environment-specific libraries:

```bash
# Load development utilities only in dev mode
if [[ "${ENVIRONMENT:-}" == "development" ]]; then
    source "$PROJECT_ROOT/lib/dev-utils.sh"
fi

# Load module if feature is enabled
if [[ "${ENABLE_MONITORING:-false}" == "true" ]]; then
    source "$PROJECT_ROOT/lib/modules/monitoring/metrics.sh"
fi
```

### Module Loading

When loading from the modular system:

```bash
# Load specific modules
source "$PROJECT_ROOT/lib/modules/core/variables.sh"
source "$PROJECT_ROOT/lib/modules/core/registry.sh"
source "$PROJECT_ROOT/lib/modules/infrastructure/vpc.sh"

# Load all modules in a category
for module in "$PROJECT_ROOT/lib/modules/infrastructure"/*.sh; do
    [[ -f "$module" ]] && source "$module"
done
```

## Path Resolution Logic

### Script Location Detection

The standard method for detecting script location:

```bash
# Most reliable method
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Alternative for compatibility (less reliable)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

### Project Root Detection

```bash
# For scripts in /scripts directory
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# For scripts in subdirectories
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# For scripts that might be symlinked
REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$REAL_SCRIPT")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
```

### Dynamic Path Resolution

For scripts that need to find the project root dynamically:

```bash
find_project_root() {
    local current_dir="$1"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/CLAUDE.md" ]] && [[ -d "$current_dir/lib" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    return 1
}

PROJECT_ROOT="$(find_project_root "$SCRIPT_DIR")" || {
    echo "Error: Could not find project root" >&2
    exit 1
}
```

## Error Handling

### Missing File Handling

Always check for library existence before sourcing:

```bash
# Basic check
if [[ ! -f "$PROJECT_ROOT/lib/required-library.sh" ]]; then
    echo "Error: Required library not found: $PROJECT_ROOT/lib/required-library.sh" >&2
    exit 1
fi
source "$PROJECT_ROOT/lib/required-library.sh"

# Function for multiple libraries
load_library() {
    local lib_path="$1"
    if [[ ! -f "$lib_path" ]]; then
        echo "Error: Cannot load library: $lib_path" >&2
        echo "Current directory: $(pwd)" >&2
        echo "Script directory: $SCRIPT_DIR" >&2
        echo "Project root: $PROJECT_ROOT" >&2
        return 1
    fi
    source "$lib_path"
}

# Usage
load_library "$PROJECT_ROOT/lib/aws-deployment-common.sh" || exit 1
```

### Graceful Degradation

For optional libraries:

```bash
# Try to load optional library
if [[ -f "$PROJECT_ROOT/lib/optional-feature.sh" ]]; then
    source "$PROJECT_ROOT/lib/optional-feature.sh"
    OPTIONAL_FEATURE_AVAILABLE=true
else
    echo "Warning: Optional feature not available (library not found)" >&2
    OPTIONAL_FEATURE_AVAILABLE=false
fi

# Later in script
if [[ "$OPTIONAL_FEATURE_AVAILABLE" == "true" ]]; then
    use_optional_feature
else
    use_fallback_method
fi
```

### Dependency Verification

```bash
# Check all dependencies before proceeding
check_dependencies() {
    local missing=0
    local deps=(
        "lib/aws-deployment-common.sh"
        "lib/error-handling.sh"
        "lib/config-management.sh"
    )
    
    for dep in "${deps[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$dep" ]]; then
            echo "Error: Missing dependency: $dep" >&2
            ((missing++))
        fi
    done
    
    return $missing
}

if ! check_dependencies; then
    echo "Error: Missing required dependencies" >&2
    exit 1
fi
```

## Dependency Resolution

### Explicit Dependencies

Each library should declare its dependencies:

```bash
# In lib/spot-instance.sh
# Dependencies: aws-deployment-common.sh, associative-arrays.sh

# Check dependencies
[[ -z "${AWS_COMMON_LOADED:-}" ]] && {
    echo "Error: aws-deployment-common.sh must be loaded first" >&2
    return 1
}

[[ -z "${ASSOCIATIVE_ARRAYS_LOADED:-}" ]] && {
    echo "Error: associative-arrays.sh must be loaded first" >&2
    return 1
}
```

### Loading Order Optimization

```bash
# Define dependency graph
declare -A LIBRARY_DEPS=(
    ["config-management.sh"]="aws-deployment-common.sh,associative-arrays.sh"
    ["spot-instance.sh"]="aws-deployment-common.sh,associative-arrays.sh,aws-cli-v2.sh"
    ["deployment-validation.sh"]="error-handling.sh,config-management.sh"
)

# Topological sort for correct loading order
load_libraries_in_order() {
    local libs=("$@")
    local loaded=()
    local loading=()
    
    # Implementation of dependency resolution
    # (See lib/utils/dependency-resolver.sh for full implementation)
}
```

### Circular Dependency Prevention

```bash
# In each library
declare -g LOADING_${LIBRARY_NAME}=1

# Check for circular dependencies
if [[ -n "${LOADING_OTHER_LIB:-}" ]]; then
    echo "Error: Circular dependency detected" >&2
    return 1
fi

# Clear loading flag after load
unset LOADING_${LIBRARY_NAME}
```

## Best Practices

### 1. Always Use Absolute Paths

```bash
# Good
source "$PROJECT_ROOT/lib/library.sh"

# Bad
source "../lib/library.sh"
source "lib/library.sh"
```

### 2. Declare Library Loaded State

```bash
# At the top of each library
[[ -n "${LIBRARY_NAME_LOADED:-}" ]] && return 0
declare -r LIBRARY_NAME_LOADED=1
```

### 3. Use Consistent Error Messages

```bash
# Standard error format
echo "Error: [Library: $LIBRARY_NAME] Description of error" >&2
```

### 4. Document Dependencies

```bash
#!/usr/bin/env bash
# Library: advanced-feature
# Description: Provides advanced feature X
# Dependencies: 
#   - aws-deployment-common.sh (logging functions)
#   - associative-arrays.sh (data structures)
#   - config-management.sh (configuration access)
# Bash: 3.x+ compatible
```

### 5. Implement Initialization Checks

```bash
# Verify environment before proceeding
init_library() {
    # Check required commands
    command -v jq >/dev/null 2>&1 || {
        echo "Error: jq is required but not installed" >&2
        return 1
    }
    
    # Initialize library state
    # Use function-based state management for bash 3.x compatibility
    init_library_state
}

# Call initialization
init_library || return 1
```

### 6. Provide Library Information

```bash
# Library version and info
declare -r LIBRARY_VERSION="1.0.0"
declare -r LIBRARY_AUTHOR="GeuseMaker Team"

# Provide library info function
library_info() {
    echo "Library: $LIBRARY_NAME"
    echo "Version: $LIBRARY_VERSION"
    echo "Description: $LIBRARY_DESCRIPTION"
    echo "Dependencies: ${LIBRARY_DEPS[*]}"
}
```

## Migration Guide

### Step 1: Audit Current Scripts

```bash
# Find all scripts that need migration
find scripts/ tests/ -name "*.sh" -type f | while read -r script; do
    if ! grep -q "PROJECT_ROOT=" "$script"; then
        echo "Needs migration: $script"
    fi
done
```

### Step 2: Update Path Resolution

Replace old patterns:

```bash
# Old pattern
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../lib/library.sh"

# New pattern
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/library.sh"
```

### Step 3: Add Error Handling

```bash
# Before
source ../lib/aws-deployment-common.sh

# After
if [[ ! -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]]; then
    echo "Error: Required library not found" >&2
    exit 1
fi
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
```

### Step 4: Update Library Headers

Add standard headers to all libraries:

```bash
#!/usr/bin/env bash
# Library: library-name
# Description: What this library does
# Dependencies: comma,separated,list
# Bash: minimum version required

# Prevent double sourcing
[[ -n "${LIBRARY_NAME_LOADED:-}" ]] && return 0
declare -r LIBRARY_NAME_LOADED=1
```

### Step 5: Test Migration

```bash
# Run validation script
./tools/validate-library-loading.sh

# Test individual scripts
for script in scripts/*.sh; do
    echo "Testing: $script"
    bash -n "$script" || echo "Syntax error in $script"
done
```

### Common Migration Issues

1. **Relative path dependencies**
   - Solution: Always use `$PROJECT_ROOT` prefix

2. **Missing error handling**
   - Solution: Add existence checks before sourcing

3. **Circular dependencies**
   - Solution: Implement loaded state checks

4. **Inconsistent loading order**
   - Solution: Follow standard loading order

5. **Hard-coded paths**
   - Solution: Use dynamic path resolution

### Validation Checklist

- [ ] All scripts use standard path resolution
- [ ] PROJECT_ROOT is defined before any source commands
- [ ] Error handling for missing libraries
- [ ] Libraries have loaded state guards
- [ ] Dependencies are documented
- [ ] Loading order follows standards
- [ ] No relative path imports
- [ ] Bash version checks where needed

## Examples

### Complete Script Example

```bash
#!/usr/bin/env bash
set -euo pipefail

# Script: deploy-production.sh
# Description: Deploy production environment with full validation
# Compatible with bash 3.x+

# Script compatible with bash 3.x+

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load required libraries with error handling
load_required_library() {
    local lib="$1"
    local lib_path="$PROJECT_ROOT/$lib"
    
    if [[ ! -f "$lib_path" ]]; then
        echo "Error: Required library not found: $lib" >&2
        echo "Expected at: $lib_path" >&2
        exit 1
    fi
    
    echo "Loading: $lib"
    source "$lib_path"
}

# Load core libraries in order
load_required_library "lib/aws-deployment-common.sh"
load_required_library "lib/error-handling.sh"
load_required_library "lib/associative-arrays.sh"
load_required_library "lib/aws-cli-v2.sh"
load_required_library "lib/config-management.sh"
load_required_library "lib/deployment-validation.sh"

# Script implementation
main() {
    log_info "Starting production deployment"
    
    # Validate environment
    validate_deployment_prerequisites || exit 1
    
    # Load configuration
    load_config "production" || exit 1
    
    # Deploy
    deploy_stack "$@"
}

# Run main function
main "$@"
```

This comprehensive guide ensures consistent, reliable library loading across all GeuseMaker scripts while supporting both modern and legacy environments.