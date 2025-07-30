#!/usr/bin/env bash
# =============================================================================
# Core Dependency Groups Module
# Defines and manages common dependency groups for the modular system
# Provides optimized dependency loading with circular dependency detection
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CORE_DEPENDENCY_GROUPS_SH_LOADED:-}" ] && return 0
declare -gr _CORE_DEPENDENCY_GROUPS_SH_LOADED=1

# Get the modules directory
MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# =============================================================================
# DEPENDENCY GROUP DEFINITIONS
# =============================================================================

# Base dependencies - Required by all modules
declare -ga DEPENDENCY_GROUP_BASE=(
    "core/errors.sh"
    "core/registry.sh"
)

# Core dependencies - Common core functionality
declare -ga DEPENDENCY_GROUP_CORE=(
    "core/errors.sh"
    "core/registry.sh"
    "core/variables.sh"
)

# Infrastructure dependencies - For infrastructure modules
declare -ga DEPENDENCY_GROUP_INFRASTRUCTURE=(
    "core/errors.sh"
    "core/registry.sh"
    "core/variables.sh"
)

# Compute dependencies - For compute-related modules
declare -ga DEPENDENCY_GROUP_COMPUTE=(
    "core/errors.sh"
    "core/registry.sh"
    "core/variables.sh"
    "config/variables.sh"
    "instances/ami.sh"
)

# Application dependencies - For application modules
declare -ga DEPENDENCY_GROUP_APPLICATION=(
    "core/errors.sh"
    "core/registry.sh"
    "core/variables.sh"
    "config/variables.sh"
)

# Monitoring dependencies - For monitoring modules
declare -ga DEPENDENCY_GROUP_MONITORING=(
    "core/errors.sh"
    "core/registry.sh"
    "core/variables.sh"
    "monitoring/metrics.sh"
)

# Deployment dependencies - For deployment modules
declare -ga DEPENDENCY_GROUP_DEPLOYMENT=(
    "core/errors.sh"
    "core/registry.sh"
    "core/variables.sh"
    "config/variables.sh"
    "deployment/state.sh"
)

# =============================================================================
# LEGACY COMPATIBILITY FUNCTIONS
# =============================================================================

# Group 1: Error handling only
# Used by: monitoring/health.sh, errors/clear_messages.sh
source_error_handling() {
    load_module_dependency "core/errors.sh" "$MODULES_DIR"
}

# Group 2: Resource management (registry + errors)
# Used by: infrastructure modules, compute modules
source_resource_management() {
    load_dependency_group "BASE" "$MODULES_DIR"
}

# Group 3: Full application stack (registry + errors + variables)
# Used by: all application modules
source_application_stack() {
    load_dependency_group "APPLICATION" "$MODULES_DIR"
}

# Group 4: Configuration dependent (variables + errors)
# Used by: deployment/userdata.sh, instances/ami.sh
source_configuration_stack() {
    load_module_dependency "core/errors.sh" "$MODULES_DIR"
    load_module_dependency "config/variables.sh" "$MODULES_DIR"
}

# Group 5: Full instance management (all core + ami)
# Used by: instances/launch.sh
source_instance_management() {
    load_dependency_group "COMPUTE" "$MODULES_DIR"
}

# =============================================================================
# DEPENDENCY LOADING FUNCTIONS
# =============================================================================

# Load a dependency group
load_dependency_group() {
    local group_name="$1"
    local module_dir="${2:-$MODULES_DIR}"
    
    # Validate group name
    local group_var="DEPENDENCY_GROUP_${group_name^^}"
    if [[ ! -v "$group_var" ]]; then
        echo "ERROR: Unknown dependency group: $group_name" >&2
        return 1
    fi
    
    # Get dependencies array
    local -n dependencies="$group_var"
    
    # Load each dependency
    for dependency in "${dependencies[@]}"; do
        load_module_dependency "$dependency" "$module_dir"
    done
}

# Load a single module dependency
load_module_dependency() {
    local dependency="$1"
    local module_dir="${2:-$MODULES_DIR}"
    
    # Build full path
    local dep_path="${module_dir}/${dependency}"
    
    # Check if dependency already loaded
    local loaded_var="_$(basename "${dependency%.sh}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_SH_LOADED"
    if [[ -n "${!loaded_var:-}" ]]; then
        return 0
    fi
    
    # Check if dependency exists
    if [[ ! -f "$dep_path" ]]; then
        echo "ERROR: Dependency not found: $dep_path" >&2
        return 1
    fi
    
    # Source the dependency
    source "$dep_path" || {
        echo "ERROR: Failed to load dependency: $dependency" >&2
        return 1
    }
}

# Lazy loading helper for optional dependencies
load_if_available() {
    local module="$1"
    local module_path="${MODULES_DIR}/${module}"
    
    if [ -f "$module_path" ]; then
        load_module_dependency "$module" "$MODULES_DIR"
        return 0
    fi
    return 1
}

# Check if all dependencies in a group are loaded
check_dependency_group() {
    local group_name="$1"
    
    # Validate group name
    local group_var="DEPENDENCY_GROUP_${group_name^^}"
    if [[ ! -v "$group_var" ]]; then
        echo "ERROR: Unknown dependency group: $group_name" >&2
        return 1
    fi
    
    # Get dependencies array
    local -n dependencies="$group_var"
    
    # Check each dependency
    for dependency in "${dependencies[@]}"; do
        local loaded_var="_$(basename "${dependency%.sh}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_SH_LOADED"
        if [[ -z "${!loaded_var:-}" ]]; then
            echo "Dependency not loaded: $dependency" >&2
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# DEPENDENCY RESOLUTION FUNCTIONS
# =============================================================================

# Resolve module dependencies (with circular dependency detection)
resolve_module_dependencies() {
    local module="$1"
    local -A visited=()
    local -A in_stack=()
    local -a result=()
    
    _resolve_dependencies_dfs "$module" visited in_stack result || return 1
    
    # Print resolved dependencies in order
    printf '%s\n' "${result[@]}"
}

# DFS helper for dependency resolution
_resolve_dependencies_dfs() {
    local module="$1"
    local -n visited_ref=$2
    local -n in_stack_ref=$3
    local -n result_ref=$4
    
    # Check for circular dependency
    if [[ -n "${in_stack_ref[$module]:-}" ]]; then
        echo "ERROR: Circular dependency detected at module: $module" >&2
        return 1
    fi
    
    # Skip if already visited
    if [[ -n "${visited_ref[$module]:-}" ]]; then
        return 0
    fi
    
    # Mark as in current stack
    in_stack_ref[$module]=1
    
    # Get dependencies for this module
    local deps=()
    if ! get_module_dependencies "$module" deps; then
        return 1
    fi
    
    # Process each dependency
    for dep in "${deps[@]}"; do
        _resolve_dependencies_dfs "$dep" visited_ref in_stack_ref result_ref || return 1
    done
    
    # Mark as visited and remove from stack
    visited_ref[$module]=1
    unset in_stack_ref[$module]
    
    # Add to result
    result_ref+=("$module")
    
    return 0
}

# Get direct dependencies of a module
get_module_dependencies() {
    local module="$1"
    local -n deps_ref=$2
    
    # Extract module category and name
    local category="${module%/*}"
    local name="${module##*/}"
    
    # Determine dependency group based on category
    case "$category" in
        "core")
            deps_ref=()  # Core modules have no dependencies
            ;;
        "infrastructure")
            deps_ref=("${DEPENDENCY_GROUP_INFRASTRUCTURE[@]}")
            ;;
        "compute"|"instances")
            deps_ref=("${DEPENDENCY_GROUP_COMPUTE[@]}")
            ;;
        "application")
            deps_ref=("${DEPENDENCY_GROUP_APPLICATION[@]}")
            ;;
        "monitoring")
            deps_ref=("${DEPENDENCY_GROUP_MONITORING[@]}")
            ;;
        "deployment")
            deps_ref=("${DEPENDENCY_GROUP_DEPLOYMENT[@]}")
            ;;
        "config")
            deps_ref=("${DEPENDENCY_GROUP_BASE[@]}")
            ;;
        *)
            # Default to base dependencies
            deps_ref=("${DEPENDENCY_GROUP_BASE[@]}")
            ;;
    esac
    
    # Filter out self-references
    local filtered_deps=()
    for dep in "${deps_ref[@]}"; do
        if [[ "$dep" != "$module" ]]; then
            filtered_deps+=("$dep")
        fi
    done
    
    deps_ref=("${filtered_deps[@]}")
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# List all available dependency groups
list_dependency_groups() {
    echo "Available dependency groups:"
    compgen -v | grep "^DEPENDENCY_GROUP_" | sed 's/^DEPENDENCY_GROUP_/  - /' | tr '[:upper:]' '[:lower:]'
}

# Get dependencies for a group
get_dependency_group() {
    local group_name="$1"
    
    # Validate group name
    local group_var="DEPENDENCY_GROUP_${group_name^^}"
    if [[ ! -v "$group_var" ]]; then
        echo "ERROR: Unknown dependency group: $group_name" >&2
        return 1
    fi
    
    # Get dependencies array
    local -n dependencies="$group_var"
    
    # Print dependencies
    printf '%s\n' "${dependencies[@]}"
}

# Check if a module is loaded
is_module_loaded() {
    local module="$1"
    local loaded_var="_$(basename "${module%.sh}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_SH_LOADED"
    [[ -n "${!loaded_var:-}" ]]
}

# Get all loaded modules
get_loaded_modules() {
    compgen -v | grep "^_.*_SH_LOADED$" | sed 's/^_//; s/_SH_LOADED$//' | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

# Export for compatibility
export DEPENDENCY_GROUPS_LOADED=1