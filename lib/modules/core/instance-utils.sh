#!/usr/bin/env bash
# =============================================================================
# Instance Utilities Module
# Common instance-related functions to avoid cross-layer dependencies
# =============================================================================

# Prevent multiple sourcing
[ -n "${_INSTANCE_UTILS_SH_LOADED:-}" ] && return 0
_INSTANCE_UTILS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/errors.sh"

# =============================================================================
# CORE INSTANCE FUNCTIONS
# =============================================================================

# Get instance details - centralized to avoid duplication
get_instance_details() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0]' \
        --output json 2>&1 || {
        throw_error $ERROR_AWS_API "Failed to get instance details for $instance_id"
    }
}

# Get instance state
get_instance_state() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>&1 || {
        throw_error $ERROR_AWS_API "Failed to get instance state for $instance_id"
    }
}

# Get instance public IP
get_instance_public_ip() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>&1 || {
        throw_error $ERROR_AWS_API "Failed to get instance public IP for $instance_id"
    }
}

# Get instance private IP
get_instance_private_ip() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text 2>&1 || {
        throw_error $ERROR_AWS_API "Failed to get instance private IP for $instance_id"
    }
}

# Check if instance exists
instance_exists() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text &>/dev/null
}

# Wait for instance state
wait_for_instance_state() {
    local instance_id="$1"
    local desired_state="$2"
    local timeout="${3:-300}"  # Default 5 minutes
    
    echo "Waiting for instance $instance_id to reach state: $desired_state" >&2
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local current_state
        current_state=$(get_instance_state "$instance_id")
        
        if [ "$current_state" = "$desired_state" ]; then
            echo "Instance reached desired state: $desired_state" >&2
            return 0
        fi
        
        echo "Current state: $current_state, waiting..." >&2
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    throw_error $ERROR_TIMEOUT "Instance did not reach state $desired_state within ${timeout}s"
}

export _INSTANCE_UTILS_SH_LOADED