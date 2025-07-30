#!/usr/bin/env bash
# Open monitoring dashboard

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "open-monitoring.sh" "core/variables" "core/logging"

# Get AWS region
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"

# Open CloudWatch dashboard
log "Opening CloudWatch dashboard for region: $AWS_REGION"
open "https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:"

success "CloudWatch dashboard opened in browser"