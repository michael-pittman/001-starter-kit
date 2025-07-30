# Shell Script Coding Standards

This document defines the coding standards for all shell scripts in the GeuseMaker project.

## Table of Contents
- [General Principles](#general-principles)
- [File Structure](#file-structure)
- [Naming Conventions](#naming-conventions)
- [Code Style](#code-style)
- [Error Handling](#error-handling)
- [Documentation](#documentation)
- [Testing](#testing)
- [Module Development](#module-development)

## General Principles

1. **Bash Compatibility**: All scripts must work with any bash version (3.x+)
2. **Modularity**: Break large scripts into focused modules
3. **Reusability**: Write functions that can be easily reused
4. **Safety**: Use strict error handling and input validation
5. **Clarity**: Prioritize readability over cleverness

## File Structure

### Script Template

All scripts should follow this structure:

```bash
#!/usr/bin/env bash
# ==============================================================================
# Script: [script-name]
# Description: [Brief description]
# 
# Usage: [script-name.sh] [options] [arguments]
#   Options:
#     -h, --help        Show this help message
#     -v, --verbose     Enable verbose output
#
# Dependencies:
#   - [List required tools/libraries]
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
#   3 - Missing dependencies
# ==============================================================================

set -euo pipefail

# Constants and globals
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Library loading
source "$SCRIPT_DIR/../lib/utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Initialize with required modules
initialize_script "$SCRIPT_NAME" \
    "core/logging" \
    "core/errors"

# Functions
# ...

# Main logic
main() {
    # Implementation
}

# Script execution
trap 'error_handler $? $LINENO' ERR
parse_arguments "$@"
main
```

### Module Template

Modules should follow this structure:

```bash
#!/usr/bin/env bash
# ==============================================================================
# Module: [module-name]
# Description: [Brief description]
# 
# Functions:
#   - function_name()     [Brief description]
#
# Dependencies:
#   - [module_name]       [Why needed]
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__MODULE_NAME_LOADED:-}" ]] && return 0
readonly __MODULE_NAME_LOADED=1

# Dependencies
source "${LIB_DIR}/modules/core/logging.sh" || return 1

# Constants
readonly MODULE_CONSTANT="value"

# Private functions (prefix with _)
_module_private_function() {
    # Implementation
}

# Public functions
module_public_function() {
    # Implementation
}
```

## Naming Conventions

### Files
- Scripts: `lowercase-with-hyphens.sh`
- Modules: `lowercase_with_underscores.sh`
- Tests: `test-[script-name].sh`
- Documentation: `UPPERCASE.md` for major docs, `lowercase.md` for others

### Variables
- Constants: `UPPERCASE_WITH_UNDERSCORES`
- Global variables: `UPPERCASE_WITH_UNDERSCORES`
- Local variables: `lowercase_with_underscores`
- Environment variables: `UPPERCASE_WITH_UNDERSCORES`

### Functions
- Public functions: `lowercase_with_underscores()`
- Private functions: `_lowercase_with_underscores()`
- Test functions: `test_description_of_test()`

## Code Style

### Indentation
- Use 4 spaces (no tabs)
- Indent case statements:
```bash
case "$variable" in
    pattern1)
        action1
        ;;
    pattern2)
        action2
        ;;
esac
```

### Line Length
- Maximum 100 characters per line
- Break long commands with backslashes:
```bash
long_command \
    --option1 value1 \
    --option2 value2 \
    --option3 value3
```

### Quotes
- Always quote variables: `"$variable"`
- Use single quotes for literal strings: `'literal'`
- Use double quotes for strings with variables: `"String with $variable"`

### Command Substitution
- Use `$()` instead of backticks
- Good: `result=$(command)`
- Bad: `result=\`command\``

### Conditionals
```bash
# Good
if [[ -n "$variable" ]]; then
    action
fi

# Also good for simple cases
[[ -n "$variable" ]] && action

# Bad (avoid single brackets)
if [ -n "$variable" ]; then
    action
fi
```

### Arrays
```bash
# Declare arrays
declare -a indexed_array=("item1" "item2")
declare -A associative_array=(["key1"]="value1" ["key2"]="value2")

# Iterate arrays
for item in "${indexed_array[@]}"; do
    echo "$item"
done
```

## Error Handling

### Basic Error Handling
```bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Error handler
error_handler() {
    local exit_code=$1
    local line_number=$2
    echo "Error on line $line_number: Command exited with status $exit_code" >&2
    exit "$exit_code"
}

trap 'error_handler $? $LINENO' ERR
```

### Function Error Handling
```bash
function_name() {
    local input="${1:-}"
    
    # Input validation
    if [[ -z "$input" ]]; then
        log_error "Missing required parameter"
        return 1
    fi
    
    # Use error context wrapper
    with_error_context "function_name" \
        _function_implementation "$input"
}
```

### Error Codes
Standard exit codes:
- 0: Success
- 1: General error
- 2: Invalid arguments
- 3: Missing dependencies
- 4: Configuration error
- 5: Runtime error
- 10-19: Application-specific errors

## Documentation

### Function Documentation
```bash
# Main processing function
# Arguments:
#   $1 - Input file path (required)
#   $2 - Output directory (optional, default: current)
# Returns:
#   0 - Success
#   1 - Input file not found
#   2 - Processing error
# Output:
#   Processed file path to stdout
# Example:
#   process_file "/path/to/input.txt" "/output/dir"
process_file() {
    # Implementation
}
```

### Inline Comments
- Explain WHY, not WHAT
- Place comments above the code they describe
- Keep comments up-to-date with code changes

## Testing

### Test Structure
```bash
#!/usr/bin/env bash
# Test for [module/script]

# Test fixtures
setup() {
    # Create test environment
}

teardown() {
    # Clean up
}

# Test functions
test_basic_functionality() {
    # Test implementation
    assert_equals "expected" "$actual"
}

# Run tests
run_test "basic functionality" test_basic_functionality
```

### Test Guidelines
- One test file per module/script
- Test both success and failure cases
- Test edge cases and boundary conditions
- Use descriptive test names
- Clean up after tests

## Module Development

### Module Guidelines

1. **Single Responsibility**: Each module should have one clear purpose
2. **Size Limits**: Keep modules under 500 lines
3. **Dependencies**: Minimize and clearly document dependencies
4. **Namespace**: Prefix functions with module name to avoid conflicts
5. **State**: Avoid global state; prefer function parameters

### Module Categories

- **Core Modules** (`lib/modules/core/`): Essential functionality
  - logging.sh, errors.sh, validation.sh
- **Infrastructure** (`lib/modules/infrastructure/`): AWS resources
  - vpc.sh, security.sh, iam.sh
- **Application** (`lib/modules/application/`): Application services
  - docker.sh, ollama.sh, n8n.sh
- **Utility** (`lib/modules/utils/`): Helper functions
  - strings.sh, arrays.sh, files.sh

### Module Refactoring Process

When refactoring large modules:

1. **Analyze**: Identify logical components
2. **Plan**: Design module boundaries
3. **Extract**: Move related functions to new modules
4. **Wrapper**: Create compatibility wrapper if needed
5. **Test**: Ensure backward compatibility
6. **Document**: Update documentation

### Example Module Refactoring

Original large module:
```bash
# ai_services.sh (1700+ lines)
# - Ollama functions
# - n8n functions  
# - Qdrant functions
# - Crawl4AI functions
# - Integration functions
```

Refactored modules:
```bash
# ollama.sh (300 lines)
# n8n.sh (400 lines)
# qdrant.sh (350 lines)
# crawl4ai.sh (450 lines)
# ai_integration.sh (200 lines)
# ai_services.sh (compatibility wrapper, 150 lines)
```

## Best Practices

### DO:
- ✓ Use meaningful variable names
- ✓ Check return values
- ✓ Validate inputs
- ✓ Clean up resources (temp files, etc.)
- ✓ Use readonly for constants
- ✓ Quote all variable expansions
- ✓ Use local variables in functions
- ✓ Follow the DRY principle

### DON'T:
- ✗ Use eval unless absolutely necessary
- ✗ Parse ls output
- ✗ Use deprecated syntax (backticks, etc.)
- ✗ Modify global variables in functions
- ✗ Ignore error conditions
- ✗ Use magic numbers without explanation
- ✗ Write overly clever code

## Code Review Checklist

Before submitting code:

- [ ] Follows naming conventions
- [ ] Includes proper error handling
- [ ] Has adequate documentation
- [ ] Passes shellcheck
- [ ] Includes tests
- [ ] Handles edge cases
- [ ] No hardcoded values
- [ ] Proper cleanup on exit
- [ ] Compatible with bash 3.x+
- [ ] Under 500 lines (for modules)

## Tools and Utilities

### Required Tools
- **shellcheck**: Static analysis tool
- **bats**: Bash testing framework
- **shfmt**: Shell script formatter

### Validation Commands
```bash
# Lint all scripts
make lint

# Run tests
make test

# Format code
shfmt -i 4 -w script.sh

# Check specific script
shellcheck -x script.sh
```

## Version History

- v1.0.0 (2024-01-30): Initial coding standards
- v1.1.0 (TBD): Added module refactoring guidelines