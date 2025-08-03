#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Validation Engine
# Advanced validation rules with business logic for GeuseMaker configurations
# Compatible with bash 3.x+ and enterprise deployment patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL CONSTANTS
# =============================================================================

readonly VALIDATION_ENGINE_VERSION="1.0.0"
readonly VALIDATION_RULES_DIR="${CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../config" && pwd)}/validation-rules"
readonly VALIDATION_CACHE_DIR="${CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../config" && pwd)}/.cache/validation"

# Business constraints
readonly AWS_REGIONS=(
    "us-east-1" "us-east-2" "us-west-1" "us-west-2"
    "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1"
    "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2"
    "ap-south-1" "ca-central-1" "sa-east-1"
)

readonly GPU_INSTANCE_TYPES=(
    "g4dn.xlarge" "g4dn.2xlarge" "g4dn.4xlarge" "g4dn.8xlarge" "g4dn.12xlarge" "g4dn.16xlarge"
    "g5.xlarge" "g5.2xlarge" "g5.4xlarge" "g5.8xlarge" "g5.12xlarge" "g5.16xlarge" "g5.24xlarge"
    "g5g.xlarge" "g5g.2xlarge" "g5g.4xlarge" "g5g.8xlarge" "g5g.16xlarge"
    "p3.2xlarge" "p3.8xlarge" "p3.16xlarge" "p3dn.24xlarge"
    "p4d.24xlarge" "p4de.24xlarge"
)

readonly CPU_INSTANCE_TYPES=(
    "t3.micro" "t3.small" "t3.medium" "t3.large" "t3.xlarge" "t3.2xlarge"
    "t3a.micro" "t3a.small" "t3a.medium" "t3a.large" "t3a.xlarge" "t3a.2xlarge"
    "m5.large" "m5.xlarge" "m5.2xlarge" "m5.4xlarge" "m5.8xlarge" "m5.12xlarge" "m5.16xlarge" "m5.24xlarge"
    "m5a.large" "m5a.xlarge" "m5a.2xlarge" "m5a.4xlarge" "m5a.8xlarge" "m5a.12xlarge" "m5a.16xlarge" "m5a.24xlarge"
    "c5.large" "c5.xlarge" "c5.2xlarge" "c5.4xlarge" "c5.9xlarge" "c5.12xlarge" "c5.18xlarge" "c5.24xlarge"
    "r5.large" "r5.xlarge" "r5.2xlarge" "r5.4xlarge" "r5.8xlarge" "r5.12xlarge" "r5.16xlarge" "r5.24xlarge"
)

# =============================================================================
# VALIDATION RULE DEFINITIONS
# =============================================================================

# Business rule validation functions
validate_spot_instance_constraints() {
    local config_file="$1"
    local validation_report="$2"
    
    local deployment_type=$(get_yaml_value "$config_file" ".deployment_variables.deployment_type" "spot")
    local spot_price=$(get_yaml_value "$config_file" ".deployment_variables.spot_price" "")
    local instance_type=$(get_yaml_value "$config_file" ".deployment_variables.instance_type" "g4dn.xlarge")
    local environment=$(get_yaml_value "$config_file" ".deployment_variables.environment" "development")
    
    if [[ "$deployment_type" == "spot" ]]; then
        # Validate spot price is reasonable
        if [[ -n "$spot_price" ]] && [[ "$spot_price" != "null" ]]; then
            if (( $(echo "$spot_price > 5.0" | bc -l 2>/dev/null || echo "0") )); then
                add_validation_error "$validation_report" "spot_constraints" \
                    "Spot price $spot_price is too high (max recommended: $5.00)"
            fi
        fi
        
        # GPU instances have higher spot interruption rates
        if [[ " ${GPU_INSTANCE_TYPES[*]} " == *" $instance_type "* ]]; then
            if [[ "$environment" == "production" ]]; then
                add_validation_warning "$validation_report" "spot_constraints" \
                    "GPU spot instances in production have higher interruption risk"
            fi
        fi
        
        # Validate spot fallback is enabled for critical workloads
        local spot_fallback=$(get_yaml_value "$config_file" ".deployment_variables.enable_spot_fallback" "true")
        if [[ "$environment" == "production" ]] && [[ "$spot_fallback" != "true" ]]; then
            add_validation_error "$validation_report" "spot_constraints" \
                "Spot fallback must be enabled for production workloads"
        fi
    fi
}

validate_instance_type_compatibility() {
    local config_file="$1"
    local validation_report="$2"
    
    local instance_type=$(get_yaml_value "$config_file" ".deployment_variables.instance_type" "g4dn.xlarge")
    local region=$(get_yaml_value "$config_file" ".deployment_variables.aws_region" "us-east-1")
    local deployment_type=$(get_yaml_value "$config_file" ".deployment_variables.deployment_type" "spot")
    
    # Validate instance type exists
    local valid_instance=false
    for valid_type in "${GPU_INSTANCE_TYPES[@]}" "${CPU_INSTANCE_TYPES[@]}"; do
        if [[ "$instance_type" == "$valid_type" ]]; then
            valid_instance=true
            break
        fi
    done
    
    if [[ "$valid_instance" != "true" ]]; then
        add_validation_error "$validation_report" "instance_compatibility" \
            "Unknown instance type: $instance_type"
    fi
    
    # GPU instances require specific configurations
    if [[ " ${GPU_INSTANCE_TYPES[*]} " == *" $instance_type "* ]]; then
        local ollama_enable=$(get_yaml_value "$config_file" ".deployment_variables.ollama_enable" "true")
        if [[ "$ollama_enable" != "true" ]]; then
            add_validation_warning "$validation_report" "instance_compatibility" \
                "GPU instance $instance_type selected but Ollama is disabled"
        fi
        
        # Check GPU-optimized Docker configuration
        local gpu_runtime=$(get_yaml_value "$config_file" ".docker.gpu.runtime" "nvidia")
        if [[ "$gpu_runtime" != "nvidia" ]]; then
            add_validation_error "$validation_report" "instance_compatibility" \
                "GPU instance requires nvidia runtime configuration"
        fi
    fi
    
    # Regional availability check (simplified)
    case "$region" in
        "cn-north-1"|"cn-northwest-1")
            if [[ " ${GPU_INSTANCE_TYPES[*]} " == *" $instance_type "* ]]; then
                add_validation_warning "$validation_report" "instance_compatibility" \
                    "GPU instances may have limited availability in China regions"
            fi
            ;;
        "af-south-1"|"me-south-1")
            if [[ "$instance_type" == p* ]]; then
                add_validation_warning "$validation_report" "instance_compatibility" \
                    "P-series instances may not be available in all newer regions"
            fi
            ;;
    esac
}

validate_vpc_networking_configuration() {
    local config_file="$1"
    local validation_report="$2"
    
    local vpc_cidr=$(get_yaml_value "$config_file" ".infrastructure.networking.vpc_cidr" "10.0.0.0/16")
    local public_subnet_count=$(get_yaml_value "$config_file" ".infrastructure.networking.public_subnet_count" "2")
    local private_subnet_count=$(get_yaml_value "$config_file" ".infrastructure.networking.private_subnet_count" "2")
    local enable_nat_gateway=$(get_yaml_value "$config_file" ".infrastructure.networking.enable_nat_gateway" "true")
    local enable_multi_az=$(get_yaml_value "$config_file" ".deployment_variables.enable_multi_az" "false")
    
    # Validate CIDR format
    if ! [[ "$vpc_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        add_validation_error "$validation_report" "vpc_networking" \
            "Invalid VPC CIDR format: $vpc_cidr"
    fi
    
    # Check CIDR size is appropriate
    local cidr_prefix=$(echo "$vpc_cidr" | cut -d'/' -f2)
    if [[ "$cidr_prefix" -gt "24" ]]; then
        add_validation_warning "$validation_report" "vpc_networking" \
            "VPC CIDR /$cidr_prefix may be too small for multiple subnets"
    fi
    
    # Validate subnet counts
    if [[ "$public_subnet_count" -lt "1" ]]; then
        add_validation_error "$validation_report" "vpc_networking" \
            "At least one public subnet is required"
    fi
    
    if [[ "$enable_multi_az" == "true" ]] && [[ "$public_subnet_count" -lt "2" ]]; then
        add_validation_error "$validation_report" "vpc_networking" \
            "Multi-AZ deployment requires at least 2 public subnets"
    fi
    
    # Private subnets require NAT gateway for internet access
    if [[ "$private_subnet_count" -gt "0" ]] && [[ "$enable_nat_gateway" != "true" ]]; then
        add_validation_warning "$validation_report" "vpc_networking" \
            "Private subnets without NAT gateway will not have internet access"
    fi
    
    # Cost optimization: NAT gateway in multi-AZ
    if [[ "$enable_nat_gateway" == "true" ]] && [[ "$enable_multi_az" == "true" ]]; then
        add_validation_warning "$validation_report" "vpc_networking" \
            "Multi-AZ NAT gateways increase costs ($45+/month per AZ)"
    fi
}

validate_application_resource_allocation() {
    local config_file="$1"
    local validation_report="$2"
    
    local instance_type=$(get_yaml_value "$config_file" ".deployment_variables.instance_type" "g4dn.xlarge")
    
    # Get instance specifications (simplified mapping)
    local instance_vcpus=4
    local instance_memory_gb=16
    case "$instance_type" in
        "g4dn.xlarge") instance_vcpus=4; instance_memory_gb=16 ;;
        "g4dn.2xlarge") instance_vcpus=8; instance_memory_gb=32 ;;
        "g5.xlarge") instance_vcpus=4; instance_memory_gb=16 ;;
        "g5.2xlarge") instance_vcpus=8; instance_memory_gb=32 ;;
        "t3.large") instance_vcpus=2; instance_memory_gb=8 ;;
        "t3.xlarge") instance_vcpus=4; instance_memory_gb=16 ;;
        "m5.large") instance_vcpus=2; instance_memory_gb=8 ;;
        "m5.xlarge") instance_vcpus=4; instance_memory_gb=16 ;;
    esac
    
    # Calculate total resource requirements
    local total_cpu_limit=0
    local total_memory_gb=0
    
    # Check each application
    local apps=("postgres" "n8n" "ollama" "qdrant" "crawl4ai")
    for app in "${apps[@]}"; do
        local app_enabled=$(get_yaml_value "$config_file" ".deployment_variables.${app}_enable" "true")
        if [[ "$app_enabled" == "true" ]]; then
            local cpu_limit=$(get_yaml_value "$config_file" ".applications.$app.resources.cpu_limit" "1.0")
            local memory_limit=$(get_yaml_value "$config_file" ".applications.$app.resources.memory_limit" "2G")
            
            # Convert CPU limit to number
            local cpu_num=$(echo "$cpu_limit" | sed 's/[^0-9.]//g')
            total_cpu_limit=$(echo "$total_cpu_limit + $cpu_num" | bc -l 2>/dev/null || echo "$total_cpu_limit")
            
            # Convert memory to GB
            local memory_num=$(echo "$memory_limit" | sed 's/[^0-9.]//g')
            if [[ "$memory_limit" == *"M"* ]]; then
                memory_num=$(echo "$memory_num / 1024" | bc -l 2>/dev/null || echo "0")
            fi
            total_memory_gb=$(echo "$total_memory_gb + $memory_num" | bc -l 2>/dev/null || echo "$total_memory_gb")
        fi
    done
    
    # Validate CPU over-allocation
    if (( $(echo "$total_cpu_limit > $instance_vcpus" | bc -l 2>/dev/null || echo "0") )); then
        add_validation_warning "$validation_report" "resource_allocation" \
            "CPU over-allocation: ${total_cpu_limit} vCPUs requested, ${instance_vcpus} available"
    fi
    
    # Validate memory over-allocation (leave 1GB for system)
    local available_memory=$((instance_memory_gb - 1))
    if (( $(echo "$total_memory_gb > $available_memory" | bc -l 2>/dev/null || echo "0") )); then
        add_validation_warning "$validation_report" "resource_allocation" \
            "Memory over-allocation: ${total_memory_gb}GB requested, ${available_memory}GB available"
    fi
    
    # Ollama GPU memory validation
    local ollama_enabled=$(get_yaml_value "$config_file" ".deployment_variables.ollama_enable" "true")
    if [[ "$ollama_enabled" == "true" ]] && [[ " ${GPU_INSTANCE_TYPES[*]} " == *" $instance_type "* ]]; then
        local gpu_memory_fraction=$(get_yaml_value "$config_file" ".applications.ollama.resources.gpu_memory_fraction" "0.80")
        if (( $(echo "$gpu_memory_fraction > 0.95" | bc -l 2>/dev/null || echo "0") )); then
            add_validation_warning "$validation_report" "resource_allocation" \
                "GPU memory fraction $gpu_memory_fraction is very high, may cause OOM"
        fi
    fi
}

validate_security_configuration() {
    local config_file="$1"
    local validation_report="$2"
    
    local environment=$(get_yaml_value "$config_file" ".deployment_variables.environment" "development")
    local encryption_at_rest=$(get_yaml_value "$config_file" ".security.secrets_management.encryption_at_rest" "true")
    local encryption_in_transit=$(get_yaml_value "$config_file" ".compliance.encryption_in_transit" "true")
    local audit_logging=$(get_yaml_value "$config_file" ".compliance.audit_logging" "false")
    local use_secrets_manager=$(get_yaml_value "$config_file" ".security.secrets_management.use_aws_secrets_manager" "true")
    local cors_strict_mode=$(get_yaml_value "$config_file" ".security.network_security.cors_strict_mode" "true")
    
    # Production security requirements
    if [[ "$environment" == "production" ]]; then
        if [[ "$encryption_at_rest" != "true" ]]; then
            add_validation_error "$validation_report" "security_config" \
                "Production environment must have encryption at rest enabled"
        fi
        
        if [[ "$encryption_in_transit" != "true" ]]; then
            add_validation_error "$validation_report" "security_config" \
                "Production environment must have encryption in transit enabled"
        fi
        
        if [[ "$audit_logging" != "true" ]]; then
            add_validation_warning "$validation_report" "security_config" \
                "Production environment should have audit logging enabled"
        fi
        
        if [[ "$use_secrets_manager" != "true" ]]; then
            add_validation_warning "$validation_report" "security_config" \
                "Production environment should use AWS Secrets Manager"
        fi
        
        if [[ "$cors_strict_mode" != "true" ]]; then
            add_validation_warning "$validation_report" "security_config" \
                "Production environment should use strict CORS mode"
        fi
    fi
    
    # Development environment security relaxation warnings
    if [[ "$environment" == "development" ]]; then
        local run_as_non_root=$(get_yaml_value "$config_file" ".security.container_security.run_as_non_root" "false")
        if [[ "$run_as_non_root" == "false" ]]; then
            add_validation_warning "$validation_report" "security_config" \
                "Development containers running as root - ensure this is intentional"
        fi
    fi
    
    # Validate SSL/TLS configuration
    local enable_alb=$(get_yaml_value "$config_file" ".deployment_variables.enable_alb" "false")
    local enable_cloudfront=$(get_yaml_value "$config_file" ".deployment_variables.enable_cloudfront" "false")
    
    if [[ "$enable_alb" == "true" ]] || [[ "$enable_cloudfront" == "true" ]]; then
        if [[ "$encryption_in_transit" != "true" ]]; then
            add_validation_warning "$validation_report" "security_config" \
                "Load balancer/CDN deployment should use encryption in transit"
        fi
    fi
}

validate_backup_and_recovery_configuration() {
    local config_file="$1"
    local validation_report="$2"
    
    local environment=$(get_yaml_value "$config_file" ".deployment_variables.environment" "development")
    local automated_backups=$(get_yaml_value "$config_file" ".backup.automated_backups" "true")
    local backup_retention_days=$(get_yaml_value "$config_file" ".backup.backup_retention_days" "30")
    local cross_region_replication=$(get_yaml_value "$config_file" ".backup.cross_region_replication" "false")
    local point_in_time_recovery=$(get_yaml_value "$config_file" ".backup.point_in_time_recovery" "false")
    local enable_efs=$(get_yaml_value "$config_file" ".deployment_variables.enable_efs" "true")
    
    # Production backup requirements
    if [[ "$environment" == "production" ]]; then
        if [[ "$automated_backups" != "true" ]]; then
            add_validation_error "$validation_report" "backup_config" \
                "Production environment must have automated backups enabled"
        fi
        
        if [[ "$backup_retention_days" -lt "30" ]]; then
            add_validation_warning "$validation_report" "backup_config" \
                "Production backup retention should be at least 30 days"
        fi
        
        if [[ "$cross_region_replication" != "true" ]]; then
            add_validation_warning "$validation_report" "backup_config" \
                "Production should consider cross-region backup replication"
        fi
    fi
    
    # Backup retention validation
    if [[ "$backup_retention_days" -gt "365" ]]; then
        add_validation_warning "$validation_report" "backup_config" \
            "Backup retention $backup_retention_days days may increase storage costs significantly"
    fi
    
    if [[ "$backup_retention_days" -lt "1" ]]; then
        add_validation_error "$validation_report" "backup_config" \
            "Backup retention must be at least 1 day"
    fi
    
    # EFS backup dependency
    if [[ "$enable_efs" == "true" ]] && [[ "$automated_backups" != "true" ]]; then
        add_validation_warning "$validation_report" "backup_config" \
            "EFS is enabled but automated backups are disabled - data may be at risk"
    fi
    
    # Cost implications
    if [[ "$point_in_time_recovery" == "true" ]]; then
        add_validation_warning "$validation_report" "backup_config" \
            "Point-in-time recovery increases backup storage costs"
    fi
}

validate_monitoring_and_alerting_configuration() {
    local config_file="$1"
    local validation_report="$2"
    
    local environment=$(get_yaml_value "$config_file" ".deployment_variables.environment" "development")
    local metrics_enabled=$(get_yaml_value "$config_file" ".monitoring.metrics.enabled" "true")
    local alerting_enabled=$(get_yaml_value "$config_file" ".monitoring.alerting.enabled" "true")
    local health_checks_enabled=$(get_yaml_value "$config_file" ".monitoring.health_checks.enabled" "true")
    local centralized_logging=$(get_yaml_value "$config_file" ".monitoring.logging.centralized" "true")
    local log_retention_days=$(get_yaml_value "$config_file" ".monitoring.logging.retention_days" "30")
    local enable_alb=$(get_yaml_value "$config_file" ".deployment_variables.enable_alb" "false")
    
    # Production monitoring requirements
    if [[ "$environment" == "production" ]]; then
        if [[ "$metrics_enabled" != "true" ]]; then
            add_validation_error "$validation_report" "monitoring_config" \
                "Production environment must have metrics enabled"
        fi
        
        if [[ "$alerting_enabled" != "true" ]]; then
            add_validation_error "$validation_report" "monitoring_config" \
                "Production environment must have alerting enabled"
        fi
        
        if [[ "$health_checks_enabled" != "true" ]]; then
            add_validation_error "$validation_report" "monitoring_config" \
                "Production environment must have health checks enabled"
        fi
        
        if [[ "$centralized_logging" != "true" ]]; then
            add_validation_warning "$validation_report" "monitoring_config" \
                "Production should use centralized logging"
        fi
    fi
    
    # Load balancer health check dependency
    if [[ "$enable_alb" == "true" ]] && [[ "$health_checks_enabled" != "true" ]]; then
        add_validation_error "$validation_report" "monitoring_config" \
            "Application Load Balancer requires health checks to be enabled"
    fi
    
    # Log retention validation
    if [[ "$log_retention_days" -lt "7" ]]; then
        add_validation_warning "$validation_report" "monitoring_config" \
            "Log retention less than 7 days may hinder troubleshooting"
    fi
    
    if [[ "$log_retention_days" -gt "90" ]] && [[ "$environment" != "production" ]]; then
        add_validation_warning "$validation_report" "monitoring_config" \
            "Long log retention in non-production may increase costs"
    fi
    
    # Metrics retention vs environment
    local metrics_retention=$(get_yaml_value "$config_file" ".monitoring.metrics.retention_days" "30")
    if [[ "$environment" == "production" ]] && [[ "$metrics_retention" -lt "30" ]]; then
        add_validation_warning "$validation_report" "monitoring_config" \
            "Production metrics retention should be at least 30 days"
    fi
}

validate_cost_optimization_configuration() {
    local config_file="$1"
    local validation_report="$2"
    
    local deployment_type=$(get_yaml_value "$config_file" ".deployment_variables.deployment_type" "spot")
    local spot_enabled=$(get_yaml_value "$config_file" ".cost_optimization.spot_instances.enabled" "false")
    local auto_scaling_enabled=$(get_yaml_value "$config_file" ".cost_optimization.auto_scaling.scale_down_enabled" "true")
    local environment=$(get_yaml_value "$config_file" ".deployment_variables.environment" "development")
    local instance_type=$(get_yaml_value "$config_file" ".deployment_variables.instance_type" "g4dn.xlarge")
    local enable_multi_az=$(get_yaml_value "$config_file" ".deployment_variables.enable_multi_az" "false")
    local enable_nat_gateway=$(get_yaml_value "$config_file" ".infrastructure.networking.enable_nat_gateway" "true")
    
    # Spot instance configuration consistency
    if [[ "$deployment_type" == "spot" ]] && [[ "$spot_enabled" != "true" ]]; then
        add_validation_warning "$validation_report" "cost_optimization" \
            "Deployment type is 'spot' but spot instances are not enabled in cost optimization"
    fi
    
    # GPU instance cost warnings
    if [[ " ${GPU_INSTANCE_TYPES[*]} " == *" $instance_type "* ]]; then
        if [[ "$environment" == "development" ]] && [[ "$deployment_type" != "spot" ]]; then
            add_validation_warning "$validation_report" "cost_optimization" \
                "GPU instance $instance_type in development should use spot pricing for cost savings"
        fi
    fi
    
    # Multi-AZ cost implications
    if [[ "$enable_multi_az" == "true" ]]; then
        add_validation_warning "$validation_report" "cost_optimization" \
            "Multi-AZ deployment increases costs (multiple instances, NAT gateways, data transfer)"
    fi
    
    # NAT Gateway cost optimization
    if [[ "$enable_nat_gateway" == "true" ]] && [[ "$environment" == "development" ]]; then
        add_validation_warning "$validation_report" "cost_optimization" \
            "NAT Gateway in development environment adds ~$45/month - consider if necessary"
    fi
    
    # Auto-scaling for cost optimization
    if [[ "$environment" == "development" ]] && [[ "$auto_scaling_enabled" != "true" ]]; then
        add_validation_warning "$validation_report" "cost_optimization" \
            "Development environment should enable auto-scaling down for cost savings"
    fi
    
    # Idle timeout validation
    local idle_timeout=$(get_yaml_value "$config_file" ".cost_optimization.auto_scaling.idle_timeout_minutes" "30")
    if [[ "$environment" == "development" ]] && [[ "$idle_timeout" -gt "60" ]]; then
        add_validation_warning "$validation_report" "cost_optimization" \
            "Development idle timeout $idle_timeout minutes may increase costs"
    fi
    
    # Budget alerts
    local cost_alerts_enabled=$(get_yaml_value "$config_file" ".cost_optimization.resource_optimization.cost_alerts_enabled" "false")
    if [[ "$environment" == "production" ]] && [[ "$cost_alerts_enabled" != "true" ]]; then
        add_validation_warning "$validation_report" "cost_optimization" \
            "Production should enable cost alerts to monitor spending"
    fi
}

validate_compliance_and_regulatory_requirements() {
    local config_file="$1"
    local validation_report="$2"
    
    local environment=$(get_yaml_value "$config_file" ".deployment_variables.environment" "development")
    local gdpr_compliance=$(get_yaml_value "$config_file" ".compliance.gdpr_compliance" "false")
    local hipaa_compliance=$(get_yaml_value "$config_file" ".compliance.hipaa_compliance" "false")
    local sox_compliance=$(get_yaml_value "$config_file" ".compliance.sox_compliance" "false")
    local data_retention_policy=$(get_yaml_value "$config_file" ".compliance.data_retention_policy" "90")
    local audit_logging=$(get_yaml_value "$config_file" ".compliance.audit_logging" "false")
    local encryption_at_rest=$(get_yaml_value "$config_file" ".compliance.encryption_at_rest" "true")
    local encryption_in_transit=$(get_yaml_value "$config_file" ".compliance.encryption_in_transit" "true")
    local access_logging=$(get_yaml_value "$config_file" ".compliance.access_logging" "false")
    
    # GDPR compliance requirements
    if [[ "$gdpr_compliance" == "true" ]]; then
        if [[ "$encryption_at_rest" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "GDPR compliance requires encryption at rest"
        fi
        
        if [[ "$encryption_in_transit" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "GDPR compliance requires encryption in transit"
        fi
        
        if [[ "$audit_logging" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "GDPR compliance requires audit logging"
        fi
        
        if [[ "$data_retention_policy" -gt "2555" ]]; then  # ~7 years
            add_validation_warning "$validation_report" "compliance" \
                "GDPR requires data retention justification for periods > 7 years"
        fi
        
        if [[ "$access_logging" != "true" ]]; then
            add_validation_warning "$validation_report" "compliance" \
                "GDPR compliance should enable access logging for audit trails"
        fi
    fi
    
    # HIPAA compliance requirements
    if [[ "$hipaa_compliance" == "true" ]]; then
        if [[ "$encryption_at_rest" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "HIPAA compliance requires encryption at rest"
        fi
        
        if [[ "$encryption_in_transit" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "HIPAA compliance requires encryption in transit"
        fi
        
        if [[ "$audit_logging" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "HIPAA compliance requires comprehensive audit logging"
        fi
        
        if [[ "$access_logging" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "HIPAA compliance requires access logging"
        fi
        
        # HIPAA requires specific backup requirements
        local automated_backups=$(get_yaml_value "$config_file" ".backup.automated_backups" "false")
        if [[ "$automated_backups" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "HIPAA compliance requires automated backups"
        fi
    fi
    
    # SOX compliance requirements
    if [[ "$sox_compliance" == "true" ]]; then
        if [[ "$audit_logging" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "SOX compliance requires comprehensive audit logging"
        fi
        
        if [[ "$access_logging" != "true" ]]; then
            add_validation_error "$validation_report" "compliance" \
                "SOX compliance requires access logging"
        fi
        
        # SOX requires change management
        local change_tracking=$(get_yaml_value "$config_file" ".compliance.change_tracking" "false")
        if [[ "$change_tracking" != "true" ]]; then
            add_validation_warning "$validation_report" "compliance" \
                "SOX compliance should enable change tracking"
        fi
    fi
    
    # General compliance validation
    if [[ "$environment" == "production" ]]; then
        if [[ "$data_retention_policy" -lt "30" ]]; then
            add_validation_warning "$validation_report" "compliance" \
                "Production data retention policy should be at least 30 days"
        fi
    fi
}

# =============================================================================
# VALIDATION ORCHESTRATION
# =============================================================================

# Run all validation rules
run_comprehensive_validation() {
    local config_file="$1"
    local validation_report="$2"
    
    log_validation "INFO" "Running comprehensive validation suite..."
    
    # Business logic validation
    validate_spot_instance_constraints "$config_file" "$validation_report"
    validate_instance_type_compatibility "$config_file" "$validation_report"
    validate_vpc_networking_configuration "$config_file" "$validation_report"
    validate_application_resource_allocation "$config_file" "$validation_report"
    
    # Security and compliance validation
    validate_security_configuration "$config_file" "$validation_report"
    validate_backup_and_recovery_configuration "$config_file" "$validation_report"
    validate_monitoring_and_alerting_configuration "$config_file" "$validation_report"
    validate_compliance_and_regulatory_requirements "$config_file" "$validation_report"
    
    # Cost optimization validation
    validate_cost_optimization_configuration "$config_file" "$validation_report"
    
    log_validation "INFO" "Comprehensive validation completed"
}

# Generate validation rules documentation
generate_validation_rules_documentation() {
    local doc_file="$VALIDATION_RULES_DIR/validation-rules.md"
    
    mkdir -p "$VALIDATION_RULES_DIR"
    
    cat > "$doc_file" << 'EOF'
# Unity Configuration Validation Rules

This document describes all validation rules applied to Unity configuration files.

## Business Logic Rules

### Spot Instance Constraints
- Maximum spot price: $5.00
- GPU spot instances in production trigger warnings due to higher interruption rates
- Production workloads must have spot fallback enabled

### Instance Type Compatibility
- Instance types must be from approved list
- GPU instances require Ollama enabled and nvidia runtime
- Regional availability checks for specific instance types

### VPC Networking Configuration
- VPC CIDR must be valid format
- CIDR prefix should not exceed /24 for multiple subnets
- Multi-AZ requires at least 2 public subnets
- Private subnets without NAT gateway cannot access internet

### Application Resource Allocation
- CPU limits cannot exceed instance vCPU count
- Memory limits cannot exceed available instance memory (minus 1GB for system)
- GPU memory fraction should not exceed 0.95

## Security Rules

### Security Configuration
- Production must have encryption at rest and in transit
- Production should use AWS Secrets Manager
- Production should use strict CORS mode
- Development container security relaxation warnings

### Backup and Recovery
- Production must have automated backups
- Production backup retention should be at least 30 days
- EFS enabled without backups triggers warnings

## Monitoring Rules

### Monitoring and Alerting
- Production must have metrics, alerting, and health checks enabled
- ALB requires health checks
- Log retention validation based on environment

## Cost Optimization Rules

### Cost Optimization
- Spot deployment type should match cost optimization settings
- GPU instances in development should use spot pricing
- Multi-AZ deployment cost warnings
- NAT Gateway cost implications for development

## Compliance Rules

### GDPR Compliance
- Requires encryption at rest and in transit
- Requires audit logging
- Data retention policy validation
- Access logging recommendations

### HIPAA Compliance
- Requires encryption at rest and in transit
- Requires comprehensive audit and access logging
- Requires automated backups

### SOX Compliance
- Requires comprehensive audit and access logging
- Change tracking recommendations

## Rule Categories

- **ERROR**: Must be fixed before deployment
- **WARNING**: Should be reviewed but won't block deployment
- **INFO**: Informational notices for optimization

EOF
    
    log_validation "INFO" "Validation rules documentation generated: $doc_file"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Enhanced logging for validation
log_validation() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo "[$timestamp] [VALIDATION-ENGINE] ERROR: $message" >&2
            ;;
        "WARN")
            echo "[$timestamp] [VALIDATION-ENGINE] WARN: $message" >&2
            ;;
        "INFO")
            [[ "${VALIDATION_DEBUG:-false}" != "false" ]] && \
                echo "[$timestamp] [VALIDATION-ENGINE] INFO: $message" >&2
            ;;
        "DEBUG")
            [[ "${VALIDATION_DEBUG:-false}" == "true" ]] && \
                echo "[$timestamp] [VALIDATION-ENGINE] DEBUG: $message" >&2
            ;;
    esac
}

# Get YAML value with fallback
get_yaml_value() {
    local file="$1"
    local path="$2"
    local default="$3"
    
    if command -v yq >/dev/null 2>&1; then
        yq eval "$path" "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Add validation error (from migration service)
add_validation_error() {
    local report="$1"
    local category="$2"
    local message="$3"
    
    local error_entry=$(cat << EOF
{
  "category": "$category",
  "level": "error",
  "message": "$message",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
    )
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file="${report}.tmp"
        jq ".errors += [$error_entry]" "$report" > "$temp_file" && mv "$temp_file" "$report"
    fi
}

# Add validation warning (from migration service)
add_validation_warning() {
    local report="$1"
    local category="$2"
    local message="$3"
    
    local warning_entry=$(cat << EOF
{
  "category": "$category",
  "level": "warning",
  "message": "$message",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
    )
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file="${report}.tmp"
        jq ".warnings += [$warning_entry]" "$report" > "$temp_file" && mv "$temp_file" "$report"
    fi
}

# =============================================================================
# PUBLIC API
# =============================================================================

# Initialize validation engine
initialize_validation_engine() {
    log_validation "INFO" "Initializing Unity Configuration Validation Engine v$VALIDATION_ENGINE_VERSION"
    
    mkdir -p "$VALIDATION_RULES_DIR" "$VALIDATION_CACHE_DIR"
    
    # Generate validation rules documentation
    generate_validation_rules_documentation
    
    log_validation "INFO" "Validation engine initialized successfully"
}

# Validate configuration file with all rules
validate_config_file() {
    local config_file="$1"
    local output_report="${2:-$VALIDATION_CACHE_DIR/validation-report.json}"
    
    if [[ ! -f "$config_file" ]]; then
        log_validation "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    log_validation "INFO" "Validating configuration file: $config_file"
    
    # Initialize validation report
    mkdir -p "$(dirname "$output_report")"
    cat > "$output_report" << EOF
{
  "validation_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "config_file": "$config_file",
  "engine_version": "$VALIDATION_ENGINE_VERSION",
  "schema_valid": true,
  "business_rules_valid": true,
  "errors": [],
  "warnings": [],
  "suggestions": []
}
EOF
    
    # Run comprehensive validation
    run_comprehensive_validation "$config_file" "$output_report"
    
    # Update validation status
    local error_count=$(jq '.errors | length' "$output_report" 2>/dev/null || echo "0")
    if [[ "$error_count" -gt "0" ]]; then
        jq '.business_rules_valid = false' "$output_report" > "${output_report}.tmp" && \
            mv "${output_report}.tmp" "$output_report"
    fi
    
    log_validation "INFO" "Validation completed. Report: $output_report"
    echo "$output_report"
}

# Export functions
export -f initialize_validation_engine
export -f validate_config_file
export -f run_comprehensive_validation

log_validation "DEBUG" "Unity Configuration Validation Engine loaded successfully"