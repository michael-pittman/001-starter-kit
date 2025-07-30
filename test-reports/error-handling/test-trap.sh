#!/usr/bin/env bash
source "$(dirname "$0")/../../deploy.sh" 2>/dev/null || true

# Trigger an error
false
