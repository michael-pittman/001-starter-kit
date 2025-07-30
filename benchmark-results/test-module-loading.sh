#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Time module loading
start=$(date +%s.%N 2>/dev/null || date +%s)

# Load core modules
for module in variables errors logging validation; do
    if [[ -f "$LIB_DIR/modules/core/$module.sh" ]]; then
        source "$LIB_DIR/modules/core/$module.sh"
    fi
done

end=$(date +%s.%N 2>/dev/null || date +%s)
duration=$(echo "$end - $start" | bc 2>/dev/null || echo "0.1")
echo "Module loading time: ${duration}s"
