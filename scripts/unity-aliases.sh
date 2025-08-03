#!/bin/bash
# Unity aliases for common operations
# Source this file to use shortcuts: source scripts/unity-aliases.sh

# Deployment aliases
alias uds='./unity deploy spot'
alias uda='./unity deploy alb'
alias udc='./unity deploy cdn'
alias udf='./unity deploy full'
alias udd='./unity destroy'

# Service management
alias usl='./unity service list'
alias uss='./unity service status'
alias usr='./unity service restart'

# Monitoring
alias um='./unity monitor'
alias ul='./unity logs'
alias us='./unity status'

# Configuration
alias ucg='./unity config get'
alias ucs='./unity config set'
alias ucv='./unity config validate'

# Help
alias uh='./unity help'

echo "Unity aliases loaded! Examples:"
echo "  uds my-stack     # Deploy spot instance"
echo "  us my-stack      # Check status"
echo "  usl              # List services"
echo "  uh               # Get help"
