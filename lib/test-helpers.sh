#!/usr/bin/env bash
# =============================================================================
# Test Helper Functions
# Provides mock functions for testing intelligent selection and pricing
# =============================================================================

# Mock function to get list of instance types
get_instance_type_list() {
    echo "g4dn.xlarge g4dn.2xlarge g4dn.4xlarge g5.xlarge g5.2xlarge"
}

# Mock function to get GPU configuration
get_gpu_config() {
    local key="$1"
    case "$key" in
        "g4dn.xlarge_primary")
            echo "ami-0abcdef1234567890"  # Mock Deep Learning AMI
            ;;
        "g4dn.xlarge_secondary")
            echo "ami-0123456789abcdef0"  # Mock Ubuntu GPU AMI
            ;;
        "g4dn.2xlarge_primary")
            echo "ami-0abcdef1234567890"
            ;;
        "g4dn.2xlarge_secondary")
            echo "ami-0123456789abcdef0"
            ;;
        "g4dn.4xlarge_primary")
            echo "ami-0abcdef1234567890"
            ;;
        "g4dn.4xlarge_secondary")
            echo "ami-0123456789abcdef0"
            ;;
        "g5.xlarge_primary")
            echo "ami-0fedcba9876543210"
            ;;
        "g5.xlarge_secondary")
            echo "ami-0123456789abcdef0"
            ;;
        "g5.2xlarge_primary")
            echo "ami-0fedcba9876543210"
            ;;
        "g5.2xlarge_secondary")
            echo "ami-0123456789abcdef0"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Mock function to verify AMI availability
verify_ami_availability() {
    local ami_id="$1"
    local region="$2"
    
    # For testing, randomly return success or failure
    if [[ "$ami_id" == "ami-0abcdef1234567890" ]]; then
        return 0  # Primary AMIs always available
    elif [[ "$region" == "us-east-1" ]]; then
        return 0  # Everything available in us-east-1
    else
        # 70% chance of availability in other regions
        [ $((RANDOM % 10)) -lt 7 ]
    fi
}

# Mock function to get comprehensive spot pricing
get_comprehensive_spot_pricing() {
    local instance_types="$1"
    local region="$2"
    
    # Return mock pricing data in JSON format
    cat <<EOF
[
    {
        "instance_type": "g4dn.xlarge",
        "price": "0.1578",
        "az": "${region}a"
    },
    {
        "instance_type": "g4dn.xlarge",
        "price": "0.1612",
        "az": "${region}b"
    },
    {
        "instance_type": "g5.xlarge",
        "price": "0.2134",
        "az": "${region}a"
    }
]
EOF
}

# Mock function to analyze cost performance matrix
analyze_cost_performance_matrix() {
    local pricing_data="$1"
    
    # Return mock analysis
    cat <<EOF
[
    {
        "instance_type": "g4dn.xlarge",
        "performance_score": 85,
        "avg_spot_price": "0.1595"
    },
    {
        "instance_type": "g5.xlarge",
        "performance_score": 95,
        "avg_spot_price": "0.2134"
    }
]
EOF
}

# Mock function for optimal configuration selection
select_optimal_configuration() {
    local budget="$1"
    local cross_region="$2"
    
    # Simple logic based on budget
    if (( $(echo "$budget < 0.20" | bc -l) )); then
        echo "g4dn.xlarge:ami-0abcdef1234567890:primary:0.1578:us-east-1"
    elif (( $(echo "$budget < 0.25" | bc -l) )); then
        echo "g5.xlarge:ami-0fedcba9876543210:primary:0.2134:us-east-1"
    else
        echo "g4dn.2xlarge:ami-0abcdef1234567890:primary:0.3156:us-east-1"
    fi
}