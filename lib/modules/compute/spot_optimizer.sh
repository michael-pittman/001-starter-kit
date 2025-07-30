#!/usr/bin/env bash
#
# Compatibility wrapper for compute/spot_optimizer.sh
# This file is DEPRECATED and will be removed in a future version.
# Please use lib/modules/compute/spot.sh instead.
#

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Show deprecation warning
echo "WARNING: lib/modules/compute/spot_optimizer.sh is deprecated." >&2
echo "         Please update your scripts to use lib/modules/compute/spot.sh instead." >&2
echo "         Called from: ${BASH_SOURCE[1]:-unknown}" >&2

# Source the new module
source "${MODULE_ROOT}/compute/spot.sh"