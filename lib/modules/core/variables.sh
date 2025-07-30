#!/usr/bin/env bash
# Compatibility wrapper for modules/core/variables.sh
# Redirects to variable-management.sh

# Source the new module
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/variable-management.sh"

# Compatibility note
: # This module has been consolidated into lib/variable-management.sh