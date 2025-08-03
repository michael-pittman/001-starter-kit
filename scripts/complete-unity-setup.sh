#!/bin/bash
# Unity Setup Completion Script
# Run this after copying artifact content to files

set -euo pipefail

echo "🔧 Completing Unity setup..."

# Make scripts executable
chmod +x scripts/unity-*.sh

# Verify file contents
echo "📋 Verifying file contents..."

if grep -q "PLACEHOLDER" config/unity-agents.yml; then
    echo "❌ config/unity-agents.yml still contains placeholder content"
    echo "   Copy content from 'Unity Subagents Configuration' artifact"
    exit 1
fi

if grep -q "SETUP REQUIRED" scripts/unity-orchestrate.sh; then
    echo "❌ scripts/unity-orchestrate.sh still contains placeholder content"
    echo "   Copy content from 'Subagent Chaining Workflow Implementation' artifact"
    exit 1
fi

if grep -q "SETUP REQUIRED" scripts/unity-agent-utils.sh; then
    echo "❌ scripts/unity-agent-utils.sh still contains placeholder content"
    echo "   Copy content from 'Unity Agent Utilities' artifact"
    exit 1
fi

# Test YAML validity
if ! python3 -c "import yaml; yaml.safe_load(open('config/unity-agents.yml'))" 2>/dev/null; then
    echo "❌ config/unity-agents.yml contains invalid YAML"
    exit 1
fi

echo "✅ All files verified"

# Test script execution
if ./scripts/unity-orchestrate.sh help &>/dev/null; then
    echo "✅ Unity orchestration script working"
else
    echo "❌ Unity orchestration script has issues"
    exit 1
fi

echo ""
echo "🎉 Unity setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run: ./scripts/unity-orchestrate.sh check-prerequisites"
echo "2. Run: ./scripts/unity-orchestrate.sh orchestrate"
echo ""
