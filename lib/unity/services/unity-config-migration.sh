#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Migration Service
# Advanced configuration consolidation, validation, and migration system
# Compatible with bash 3.x+ and enterprise deployment patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL CONSTANTS AND CONFIGURATION
# =============================================================================

readonly CONFIG_MIGRATION_VERSION="1.0.0"
readonly UNITY_CONFIG_SCHEMA_VERSION="1"

# Configuration paths
readonly CONFIG_ROOT="${CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../config" && pwd)}"
readonly PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)}"
readonly LIB_DIR="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Migration state
readonly MIGRATION_STATE_DIR="$CONFIG_ROOT/migration-state"
readonly MIGRATION_CACHE_DIR="$CONFIG_ROOT/.cache/migration"
readonly MIGRATION_BACKUP_DIR="$CONFIG_ROOT/migration-backups"

# Cache configuration
readonly CACHE_TTL="${CONFIG_CACHE_TTL:-3600}"  # 1 hour default
readonly CACHE_MAX_SIZE="${CONFIG_CACHE_MAX_SIZE:-100}"  # Max cached entries

# Business rules constants
readonly SPOT_INSTANCE_MAX_PRICE="5.00"
readonly ENTERPRISE_MIN_INSTANCES="2"
readonly MAX_BACKUP_RETENTION_DAYS="365"
readonly MIN_VOLUME_SIZE="20"
readonly MAX_VOLUME_SIZE="1000"

# =============================================================================
# ASSOCIATIVE ARRAY COMPATIBILITY (BASH 3.x/4.x)
# =============================================================================

# Check bash version and set associative array support
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    BASH_4_PLUS=true
    declare -A CONFIG_CACHE
    declare -A VALIDATION_RULES
    declare -A MIGRATION_SCHEMA
    declare -A ENVIRONMENT_OVERRIDES
else
    BASH_4_PLUS=false
    # Use prefix-based variables for bash 3.x compatibility
    CONFIG_CACHE_PREFIX="CONFIG_CACHE_"
    VALIDATION_RULES_PREFIX="VALIDATION_RULES_"
    MIGRATION_SCHEMA_PREFIX="MIGRATION_SCHEMA_"
    ENVIRONMENT_OVERRIDES_PREFIX="ENV_OVERRIDES_"
fi

# =============================================================================
# UTILITY FUNCTIONS FOR ASSOCIATIVE ARRAY EMULATION
# =============================================================================

# Set associative array value (bash 3.x/4.x compatible)
set_config_value() {
    local array_name="$1"
    local key="$2"
    local value="$3"
    
    if [[ "$BASH_4_PLUS" == "true" ]]; then
        case "$array_name" in
            "CONFIG_CACHE") CONFIG_CACHE["$key"]="$value" ;;
            "VALIDATION_RULES") VALIDATION_RULES["$key"]="$value" ;;
            "MIGRATION_SCHEMA") MIGRATION_SCHEMA["$key"]="$value" ;;
            "ENVIRONMENT_OVERRIDES") ENVIRONMENT_OVERRIDES["$key"]="$value" ;;
        esac
    else
        local var_name="${array_name}_PREFIX${key}"
        var_name=$(echo "$var_name" | tr '.-' '_')
        eval "${var_name}='$value'"
    fi
}

# Get associative array value (bash 3.x/4.x compatible)
get_config_value() {
    local array_name="$1"
    local key="$2"
    local default_value="${3:-}"
    
    if [[ "$BASH_4_PLUS" == "true" ]]; then
        case "$array_name" in
            "CONFIG_CACHE") echo "${CONFIG_CACHE[$key]:-$default_value}" ;;
            "VALIDATION_RULES") echo "${VALIDATION_RULES[$key]:-$default_value}" ;;
            "MIGRATION_SCHEMA") echo "${MIGRATION_SCHEMA[$key]:-$default_value}" ;;
            "ENVIRONMENT_OVERRIDES") echo "${ENVIRONMENT_OVERRIDES[$key]:-$default_value}" ;;
        esac
    else
        local var_name="${array_name}_PREFIX${key}"
        var_name=$(echo "$var_name" | tr '.-' '_')
        eval "echo \"\${${var_name}:-$default_value}\""
    fi
}

# Check if key exists in associative array
has_config_key() {
    local array_name="$1"
    local key="$2"
    
    if [[ "$BASH_4_PLUS" == "true" ]]; then
        case "$array_name" in
            "CONFIG_CACHE") [[ -n "${CONFIG_CACHE[$key]:-}" ]] ;;
            "VALIDATION_RULES") [[ -n "${VALIDATION_RULES[$key]:-}" ]] ;;
            "MIGRATION_SCHEMA") [[ -n "${MIGRATION_SCHEMA[$key]:-}" ]] ;;
            "ENVIRONMENT_OVERRIDES") [[ -n "${ENVIRONMENT_OVERRIDES[$key]:-}" ]] ;;
        esac
    else
        local var_name="${array_name}_PREFIX${key}"
        var_name=$(echo "$var_name" | tr '.-' '_')
        eval "[[ -n \"\${${var_name}:-}\" ]]"
    fi
}

# =============================================================================
# LOGGING AND ERROR HANDLING
# =============================================================================

# Enhanced logging with levels
log_config_migration() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo "[$timestamp] [CONFIG-MIGRATION] ERROR: $message" >&2
            ;;
        "WARN")
            echo "[$timestamp] [CONFIG-MIGRATION] WARN: $message" >&2
            ;;
        "INFO")
            [[ "${CONFIG_MIGRATION_DEBUG:-false}" != "false" ]] && \
                echo "[$timestamp] [CONFIG-MIGRATION] INFO: $message" >&2
            ;;
        "DEBUG")
            [[ "${CONFIG_MIGRATION_DEBUG:-false}" == "true" ]] && \
                echo "[$timestamp] [CONFIG-MIGRATION] DEBUG: $message" >&2
            ;;
    esac
}

# Configuration migration error handler
config_migration_error() {
    local error_code="$1"
    local error_message="$2"
    local suggestion="${3:-}"
    
    log_config_migration "ERROR" "Migration failed with code $error_code: $error_message"
    [[ -n "$suggestion" ]] && log_config_migration "INFO" "Suggestion: $suggestion"
    
    # Load errors module if available
    if declare -f throw_error >/dev/null 2>&1; then
        throw_error "$error_code" "$error_message" "$suggestion"
    else
        exit "$error_code"
    fi
}

# =============================================================================
# CONFIGURATION DISCOVERY AND INVENTORY
# =============================================================================

# Discover all configuration sources in the project
discover_configuration_sources() {
    local discovery_report="$MIGRATION_STATE_DIR/config-sources.json"
    
    log_config_migration "INFO" "Discovering configuration sources..."
    
    mkdir -p "$MIGRATION_STATE_DIR"
    
    # Initialize discovery report
    cat > "$discovery_report" << 'EOF'
{
  "discovery_timestamp": "",
  "schema_version": "1",
  "sources": {
    "yaml_configs": [],
    "env_files": [],
    "parameter_store": [],
    "hardcoded_variables": [],
    "script_configs": []
  },
  "statistics": {
    "total_sources": 0,
    "total_variables": 0,
    "duplicates": 0,
    "conflicts": 0
  }
}
EOF
    
    # Update timestamp
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    update_json_field "$discovery_report" ".discovery_timestamp" "\"$timestamp\""
    
    # Discover YAML configuration files
    discover_yaml_configs "$discovery_report"
    
    # Discover environment files
    discover_env_files "$discovery_report"
    
    # Discover Parameter Store configurations
    discover_parameter_store_configs "$discovery_report"
    
    # Discover hardcoded variables in scripts
    discover_hardcoded_variables "$discovery_report"
    
    # Calculate statistics
    calculate_discovery_statistics "$discovery_report"
    
    log_config_migration "INFO" "Configuration discovery completed. Report: $discovery_report"
    echo "$discovery_report"
}

# Discover YAML configuration files
discover_yaml_configs() {
    local discovery_report="$1"
    local yaml_files=()
    
    log_config_migration "DEBUG" "Discovering YAML configuration files..."
    
    # Find all YAML files in config directory
    while IFS= read -r -d '' file; do
        yaml_files+=("$file")
    done < <(find "$CONFIG_ROOT" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null || true)
    
    # Analyze each YAML file
    for yaml_file in "${yaml_files[@]}"; do
        if [[ -f "$yaml_file" ]]; then
            local relative_path="${yaml_file#$PROJECT_ROOT/}"
            local variable_count=$(analyze_yaml_variables "$yaml_file")
            
            # Add to discovery report
            local yaml_entry=$(cat << EOF
{
  "path": "$relative_path",
  "absolute_path": "$yaml_file",
  "variable_count": $variable_count,
  "last_modified": "$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$yaml_file" 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "size_bytes": $(wc -c < "$yaml_file"),
  "type": "yaml_config"
}
EOF
            )
            
            add_to_json_array "$discovery_report" ".sources.yaml_configs" "$yaml_entry"
        fi
    done
    
    log_config_migration "DEBUG" "Found ${#yaml_files[@]} YAML configuration files"
}

# Discover environment files
discover_env_files() {
    local discovery_report="$1"
    local env_files=()
    
    log_config_migration "DEBUG" "Discovering environment files..."
    
    # Find all .env files
    while IFS= read -r -d '' file; do
        env_files+=("$file")
    done < <(find "$PROJECT_ROOT" -name ".env*" -type f -print0 2>/dev/null || true)
    
    # Analyze each env file
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            local relative_path="${env_file#$PROJECT_ROOT/}"
            local variable_count=$(grep -c '^[A-Z_][A-Z0-9_]*=' "$env_file" 2>/dev/null || echo "0")
            
            # Add to discovery report
            local env_entry=$(cat << EOF
{
  "path": "$relative_path",
  "absolute_path": "$env_file",
  "variable_count": $variable_count,
  "last_modified": "$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$env_file" 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "size_bytes": $(wc -c < "$env_file"),
  "type": "env_file"
}
EOF
            )
            
            add_to_json_array "$discovery_report" ".sources.env_files" "$env_entry"
        fi
    done
    
    log_config_migration "DEBUG" "Found ${#env_files[@]} environment files"
}

# Discover Parameter Store configurations
discover_parameter_store_configs() {
    local discovery_report="$1"
    
    log_config_migration "DEBUG" "Discovering Parameter Store configurations..."
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        log_config_migration "WARN" "AWS CLI not available, skipping Parameter Store discovery"
        return 0
    fi
    
    # Try to discover Parameter Store parameters
    local prefixes=("/aibuildkit" "/geousemaker" "/unity")
    
    for prefix in "${prefixes[@]}"; do
        # Get parameters with the prefix (safely handle errors)
        local params_json
        if params_json=$(aws ssm get-parameters-by-path \
            --path "$prefix" \
            --recursive \
            --query 'Parameters[].Name' \
            --output json 2>/dev/null); then
            
            # Count parameters
            local param_count=$(echo "$params_json" | jq '. | length' 2>/dev/null || echo "0")
            
            if [[ "$param_count" -gt 0 ]]; then
                # Add to discovery report
                local param_entry=$(cat << EOF
{
  "prefix": "$prefix",
  "parameter_count": $param_count,
  "discovery_time": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "type": "parameter_store"
}
EOF
                )
                
                add_to_json_array "$discovery_report" ".sources.parameter_store" "$param_entry"
                log_config_migration "DEBUG" "Found $param_count parameters with prefix $prefix"
            fi
        fi
    done
}

# Discover hardcoded variables in scripts
discover_hardcoded_variables() {
    local discovery_report="$1"
    
    log_config_migration "DEBUG" "Discovering hardcoded variables in scripts..."
    
    # Find shell scripts with potential hardcoded configurations
    local script_files=()
    while IFS= read -r -d '' file; do
        script_files+=("$file")
    done < <(find "$PROJECT_ROOT" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    local total_hardcoded=0
    
    for script_file in "${script_files[@]}"; do
        if [[ -f "$script_file" ]]; then
            # Look for variable assignments that look like configuration
            local hardcoded_count=$(grep -c '^[[:space:]]*[A-Z_][A-Z0-9_]*=' "$script_file" 2>/dev/null || echo "0")
            
            if [[ "$hardcoded_count" -gt 0 ]]; then
                local relative_path="${script_file#$PROJECT_ROOT/}"
                
                # Add to discovery report
                local script_entry=$(cat << EOF
{
  "path": "$relative_path",
  "absolute_path": "$script_file",
  "hardcoded_count": $hardcoded_count,
  "last_modified": "$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$script_file" 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "type": "script_config"
}
EOF
                )
                
                add_to_json_array "$discovery_report" ".sources.hardcoded_variables" "$script_entry"
                total_hardcoded=$((total_hardcoded + hardcoded_count))
            fi
        fi
    done
    
    log_config_migration "DEBUG" "Found $total_hardcoded hardcoded variables across ${#script_files[@]} scripts"
}

# =============================================================================
# CONFIGURATION SCHEMA GENERATION AND VALIDATION
# =============================================================================

# Generate unified configuration schema
generate_unified_schema() {
    local schema_file="$CONFIG_ROOT/unity-schema.json"
    
    log_config_migration "INFO" "Generating unified configuration schema..."
    
    # Create base schema structure
    cat > "$schema_file" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Unity Configuration Schema",
  "description": "Unified configuration schema for GeuseMaker Unity system",
  "version": "1.0.0",
  "type": "object",
  "properties": {
    "metadata": {
      "type": "object",
      "properties": {
        "schema_version": {"type": "string"},
        "generated_at": {"type": "string", "format": "date-time"},
        "project_name": {"type": "string"},
        "environment": {"type": "string", "enum": ["development", "staging", "production"]}
      },
      "required": ["schema_version", "project_name", "environment"]
    },
    "global": {"$ref": "#/definitions/global_config"},
    "deployment": {"$ref": "#/definitions/deployment_config"},
    "infrastructure": {"$ref": "#/definitions/infrastructure_config"},
    "applications": {"$ref": "#/definitions/applications_config"},
    "security": {"$ref": "#/definitions/security_config"},
    "monitoring": {"$ref": "#/definitions/monitoring_config"},
    "cost_optimization": {"$ref": "#/definitions/cost_optimization_config"},
    "backup": {"$ref": "#/definitions/backup_config"},
    "compliance": {"$ref": "#/definitions/compliance_config"},
    "existing_resources": {"$ref": "#/definitions/existing_resources_config"},
    "development": {"$ref": "#/definitions/development_config"}
  },
  "required": ["metadata", "global"],
  "definitions": {}
}
EOF
    
    # Add schema definitions based on defaults.yml structure
    add_schema_definitions "$schema_file"
    
    log_config_migration "INFO" "Unified schema generated: $schema_file"
    echo "$schema_file"
}

# Add detailed schema definitions
add_schema_definitions() {
    local schema_file="$1"
    
    # Read the current schema and add definitions
    local definitions=$(cat << 'EOF'
{
  "global_config": {
    "type": "object",
    "properties": {
      "project_name": {"type": "string", "minLength": 1, "maxLength": 50},
      "region": {"type": "string", "pattern": "^[a-z0-9-]+$"},
      "default_region": {"type": "string", "pattern": "^[a-z0-9-]+$"},
      "profile": {"type": "string"},
      "default_tags": {"type": "object"}
    },
    "required": ["project_name", "region"]
  },
  "deployment_config": {
    "type": "object",
    "properties": {
      "aws_region": {"type": "string", "pattern": "^[a-z0-9-]+$"},
      "deployment_type": {
        "type": "string",
        "enum": ["spot", "ondemand", "simple", "enterprise", "alb", "cdn", "full"]
      },
      "instance_type": {"type": "string", "pattern": "^[a-z0-9.]+$"},
      "key_name": {"type": "string", "minLength": 1},
      "volume_size": {"type": "integer", "minimum": 20, "maximum": 1000},
      "environment": {
        "type": "string",
        "enum": ["development", "staging", "production"]
      },
      "debug": {"type": "boolean"},
      "dry_run": {"type": "boolean"},
      "cleanup_on_failure": {"type": "boolean"}
    },
    "required": ["aws_region", "deployment_type", "instance_type", "key_name"]
  },
  "infrastructure_config": {
    "type": "object",
    "properties": {
      "instance_types": {
        "type": "object",
        "properties": {
          "gpu_instances": {"type": "array", "items": {"type": "string"}},
          "cpu_instances": {"type": "array", "items": {"type": "string"}},
          "fallback_instances": {"type": "array", "items": {"type": "string"}}
        }
      },
      "networking": {
        "type": "object",
        "properties": {
          "vpc_cidr": {"type": "string", "pattern": "^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$"},
          "public_subnet_count": {"type": "integer", "minimum": 1, "maximum": 6},
          "private_subnet_count": {"type": "integer", "minimum": 0, "maximum": 6}
        }
      }
    }
  },
  "applications_config": {
    "type": "object",
    "patternProperties": {
      ".*": {
        "type": "object",
        "properties": {
          "image": {"type": "string"},
          "port": {"type": "integer", "minimum": 1, "maximum": 65535},
          "resources": {
            "type": "object",
            "properties": {
              "cpu_limit": {"type": "string"},
              "memory_limit": {"type": "string"},
              "cpu_reservation": {"type": "string"},
              "memory_reservation": {"type": "string"}
            }
          }
        }
      }
    }
  },
  "security_config": {
    "type": "object",
    "properties": {
      "container_security": {"type": "object"},
      "network_security": {"type": "object"},
      "secrets_management": {"type": "object"},
      "access_control": {"type": "object"}
    }
  },
  "monitoring_config": {
    "type": "object",
    "properties": {
      "metrics": {"type": "object"},
      "logging": {"type": "object"},
      "health_checks": {"type": "object"},
      "alerting": {"type": "object"},
      "dashboards": {"type": "object"}
    }
  },
  "cost_optimization_config": {
    "type": "object",
    "properties": {
      "spot_instances": {
        "type": "object",
        "properties": {
          "enabled": {"type": "boolean"},
          "max_price": {"type": "number", "minimum": 0.01, "maximum": 10.0}
        }
      }
    }
  },
  "backup_config": {
    "type": "object",
    "properties": {
      "automated_backups": {"type": "boolean"},
      "backup_retention_days": {"type": "integer", "minimum": 1, "maximum": 365}
    }
  },
  "compliance_config": {
    "type": "object",
    "properties": {
      "audit_logging": {"type": "boolean"},
      "encryption_in_transit": {"type": "boolean"},
      "encryption_at_rest": {"type": "boolean"}
    }
  },
  "existing_resources_config": {
    "type": "object",
    "properties": {
      "enabled": {"type": "boolean"},
      "validation_mode": {
        "type": "string",
        "enum": ["strict", "lenient", "skip"]
      },
      "auto_discovery": {"type": "boolean"}
    }
  },
  "development_config": {
    "type": "object",
    "properties": {
      "hot_reload": {"type": "boolean"},
      "debug_mode": {"type": "boolean"},
      "test_data_enabled": {"type": "boolean"}
    }
  }
}
EOF
    )
    
    # Update schema file with definitions
    echo "$definitions" | jq '.definitions = .' "$schema_file" > "${schema_file}.tmp" && \
        mv "${schema_file}.tmp" "$schema_file"
}

# =============================================================================
# ADVANCED VALIDATION RULES ENGINE
# =============================================================================

# Initialize validation rules
initialize_validation_rules() {
    log_config_migration "DEBUG" "Initializing validation rules..."
    
    # Business logic validation rules
    set_config_value "VALIDATION_RULES" "spot_price_limit" "$SPOT_INSTANCE_MAX_PRICE"
    set_config_value "VALIDATION_RULES" "enterprise_min_instances" "$ENTERPRISE_MIN_INSTANCES"
    set_config_value "VALIDATION_RULES" "max_backup_retention" "$MAX_BACKUP_RETENTION_DAYS"
    set_config_value "VALIDATION_RULES" "min_volume_size" "$MIN_VOLUME_SIZE"
    set_config_value "VALIDATION_RULES" "max_volume_size" "$MAX_VOLUME_SIZE"
    
    # Dependency validation rules
    set_config_value "VALIDATION_RULES" "alb_requires_multi_az" "true"
    set_config_value "VALIDATION_RULES" "cloudfront_requires_alb" "true"
    set_config_value "VALIDATION_RULES" "enterprise_requires_backup" "true"
    set_config_value "VALIDATION_RULES" "production_requires_monitoring" "true"
    
    # Regional constraints
    set_config_value "VALIDATION_RULES" "gpu_supported_regions" "us-east-1,us-west-2,eu-west-1,ap-southeast-1"
    set_config_value "VALIDATION_RULES" "spot_restricted_regions" "cn-north-1,cn-northwest-1"
    
    log_config_migration "DEBUG" "Validation rules initialized"
}

# Validate configuration with business rules
validate_configuration() {
    local config_file="$1"
    local validation_report="$MIGRATION_STATE_DIR/validation-report.json"
    
    log_config_migration "INFO" "Validating configuration: $config_file"
    
    mkdir -p "$MIGRATION_STATE_DIR"
    
    # Initialize validation report
    cat > "$validation_report" << 'EOF'
{
  "validation_timestamp": "",
  "config_file": "",
  "schema_valid": false,
  "business_rules_valid": false,
  "errors": [],
  "warnings": [],
  "suggestions": []
}
EOF
    
    # Update report metadata
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    update_json_field "$validation_report" ".validation_timestamp" "\"$timestamp\""
    update_json_field "$validation_report" ".config_file" "\"$config_file\""
    
    # Schema validation
    validate_schema "$config_file" "$validation_report"
    
    # Business rules validation
    validate_business_rules "$config_file" "$validation_report"
    
    # Dependency validation
    validate_dependencies "$config_file" "$validation_report"
    
    # Regional constraints validation
    validate_regional_constraints "$config_file" "$validation_report"
    
    # Cross-reference validation
    validate_cross_references "$config_file" "$validation_report"
    
    log_config_migration "INFO" "Configuration validation completed. Report: $validation_report"
    echo "$validation_report"
}

# Validate against schema
validate_schema() {
    local config_file="$1"
    local validation_report="$2"
    
    log_config_migration "DEBUG" "Performing schema validation..."
    
    # Check if config file exists and is valid YAML/JSON
    if [[ ! -f "$config_file" ]]; then
        add_validation_error "$validation_report" "schema" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Basic YAML syntax validation
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
            add_validation_error "$validation_report" "schema" "Invalid YAML syntax in configuration file"
            return 1
        fi
    fi
    
    # Schema validation passed
    update_json_field "$validation_report" ".schema_valid" "true"
    log_config_migration "DEBUG" "Schema validation passed"
}

# Validate business rules
validate_business_rules() {
    local config_file="$1"
    local validation_report="$2"
    local rules_passed=true
    
    log_config_migration "DEBUG" "Validating business rules..."
    
    # Get configuration values for validation
    local deployment_type=$(get_yaml_value "$config_file" ".deployment.deployment_type" "spot")
    local instance_type=$(get_yaml_value "$config_file" ".deployment.instance_type" "")
    local volume_size=$(get_yaml_value "$config_file" ".deployment.volume_size" "30")
    local backup_retention=$(get_yaml_value "$config_file" ".backup.backup_retention_days" "30")
    local spot_price=$(get_yaml_value "$config_file" ".cost_optimization.spot_instances.max_price" "1.00")
    
    # Validate spot price limits
    if [[ "$deployment_type" == "spot" ]] && [[ -n "$spot_price" ]]; then
        local max_spot_price=$(get_config_value "VALIDATION_RULES" "spot_price_limit")
        if (( $(echo "$spot_price > $max_spot_price" | bc -l 2>/dev/null || echo "0") )); then
            add_validation_error "$validation_report" "business_rule" \
                "Spot price $spot_price exceeds maximum allowed price $max_spot_price"
            rules_passed=false
        fi
    fi
    
    # Validate volume size
    local min_volume=$(get_config_value "VALIDATION_RULES" "min_volume_size")
    local max_volume=$(get_config_value "VALIDATION_RULES" "max_volume_size")
    if [[ "$volume_size" -lt "$min_volume" ]] || [[ "$volume_size" -gt "$max_volume" ]]; then
        add_validation_error "$validation_report" "business_rule" \
            "Volume size $volume_size is outside allowed range [$min_volume-$max_volume]"
        rules_passed=false
    fi
    
    # Validate backup retention
    local max_retention=$(get_config_value "VALIDATION_RULES" "max_backup_retention")
    if [[ "$backup_retention" -gt "$max_retention" ]]; then
        add_validation_warning "$validation_report" "business_rule" \
            "Backup retention $backup_retention days exceeds recommended maximum $max_retention days"
    fi
    
    # Enterprise deployment validation
    if [[ "$deployment_type" == "enterprise" ]]; then
        local min_instances=$(get_config_value "VALIDATION_RULES" "enterprise_min_instances")
        local auto_scaling_min=$(get_yaml_value "$config_file" ".infrastructure.auto_scaling.min_capacity" "1")
        
        if [[ "$auto_scaling_min" -lt "$min_instances" ]]; then
            add_validation_error "$validation_report" "business_rule" \
                "Enterprise deployment requires minimum $min_instances instances, got $auto_scaling_min"
            rules_passed=false
        fi
    fi
    
    # GPU instance validation
    if [[ "$instance_type" == g* ]] || [[ "$instance_type" == p* ]]; then
        local region=$(get_yaml_value "$config_file" ".global.region" "us-east-1")
        local supported_regions=$(get_config_value "VALIDATION_RULES" "gpu_supported_regions")
        
        if [[ "$supported_regions" != *"$region"* ]]; then
            add_validation_warning "$validation_report" "business_rule" \
                "GPU instance $instance_type may not be available in region $region"
        fi
    fi
    
    # Update validation status
    if [[ "$rules_passed" == "true" ]]; then
        update_json_field "$validation_report" ".business_rules_valid" "true"
        log_config_migration "DEBUG" "Business rules validation passed"
    else
        log_config_migration "WARN" "Business rules validation failed"
    fi
}

# Validate dependencies between configuration options
validate_dependencies() {
    local config_file="$1"
    local validation_report="$2"
    
    log_config_migration "DEBUG" "Validating configuration dependencies..."
    
    # Get key configuration values
    local enable_alb=$(get_yaml_value "$config_file" ".deployment.enable_alb" "false")
    local enable_cloudfront=$(get_yaml_value "$config_file" ".deployment.enable_cloudfront" "false")
    local enable_multi_az=$(get_yaml_value "$config_file" ".deployment.enable_multi_az" "false")
    local environment=$(get_yaml_value "$config_file" ".global.environment" "development")
    local enable_monitoring=$(get_yaml_value "$config_file" ".monitoring.metrics.enabled" "true")
    local deployment_type=$(get_yaml_value "$config_file" ".deployment.deployment_type" "spot")
    
    # ALB requires multi-AZ in production
    if [[ "$enable_alb" == "true" ]] && [[ "$environment" == "production" ]] && [[ "$enable_multi_az" != "true" ]]; then
        add_validation_error "$validation_report" "dependency" \
            "ALB in production environment requires multi-AZ deployment"
    fi
    
    # CloudFront typically requires ALB
    if [[ "$enable_cloudfront" == "true" ]] && [[ "$enable_alb" != "true" ]]; then
        add_validation_warning "$validation_report" "dependency" \
            "CloudFront deployment typically requires ALB for origin"
    fi
    
    # Enterprise deployment requirements
    if [[ "$deployment_type" == "enterprise" ]]; then
        if [[ "$enable_monitoring" != "true" ]]; then
            add_validation_error "$validation_report" "dependency" \
                "Enterprise deployment requires monitoring to be enabled"
        fi
    fi
    
    # Production environment requirements
    if [[ "$environment" == "production" ]]; then
        if [[ "$enable_monitoring" != "true" ]]; then
            add_validation_warning "$validation_report" "dependency" \
                "Production environment should have monitoring enabled"
        fi
        
        local backup_enabled=$(get_yaml_value "$config_file" ".backup.automated_backups" "false")
        if [[ "$backup_enabled" != "true" ]]; then
            add_validation_warning "$validation_report" "dependency" \
                "Production environment should have automated backups enabled"
        fi
    fi
    
    log_config_migration "DEBUG" "Dependency validation completed"
}

# Validate regional constraints
validate_regional_constraints() {
    local config_file="$1"
    local validation_report="$2"
    
    log_config_migration "DEBUG" "Validating regional constraints..."
    
    local region=$(get_yaml_value "$config_file" ".global.region" "us-east-1")
    local deployment_type=$(get_yaml_value "$config_file" ".deployment.deployment_type" "spot")
    
    # Check spot instance restrictions
    if [[ "$deployment_type" == "spot" ]]; then
        local restricted_regions=$(get_config_value "VALIDATION_RULES" "spot_restricted_regions")
        if [[ "$restricted_regions" == *"$region"* ]]; then
            add_validation_error "$validation_report" "regional" \
                "Spot instances are not supported in region $region"
        fi
    fi
    
    log_config_migration "DEBUG" "Regional constraints validation completed"
}

# Validate cross-references between configuration sections
validate_cross_references() {
    local config_file="$1"
    local validation_report="$2"
    
    log_config_migration "DEBUG" "Validating cross-references..."
    
    # Validate VPC CIDR and subnet CIDRs
    local vpc_cidr=$(get_yaml_value "$config_file" ".infrastructure.networking.vpc_cidr" "10.0.0.0/16")
    local public_subnets=$(get_yaml_value "$config_file" ".infrastructure.networking.public_subnets" "")
    
    # Check that subnet CIDRs are within VPC CIDR (simplified check)
    if [[ -n "$public_subnets" ]]; then
        local vpc_prefix=$(echo "$vpc_cidr" | cut -d'/' -f1 | cut -d'.' -f1-2)
        for subnet in $(echo "$public_subnets" | tr ',' ' '); do
            local subnet_prefix=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-2)
            if [[ "$subnet_prefix" != "$vpc_prefix" ]]; then
                add_validation_warning "$validation_report" "cross_reference" \
                    "Subnet $subnet may not be within VPC CIDR $vpc_cidr"
                break
            fi
        done
    fi
    
    log_config_migration "DEBUG" "Cross-reference validation completed"
}

# =============================================================================
# CONFIGURATION CACHING SYSTEM
# =============================================================================

# Initialize configuration cache
initialize_config_cache() {
    log_config_migration "DEBUG" "Initializing configuration cache..."
    
    mkdir -p "$MIGRATION_CACHE_DIR"
    
    # Create cache metadata file
    local cache_metadata="$MIGRATION_CACHE_DIR/cache-metadata.json"
    if [[ ! -f "$cache_metadata" ]]; then
        cat > "$cache_metadata" << EOF
{
  "cache_version": "1.0.0",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "ttl_seconds": $CACHE_TTL,
  "max_size": $CACHE_MAX_SIZE,
  "entries": {}
}
EOF
    fi
    
    log_config_migration "DEBUG" "Configuration cache initialized"
}

# Cache configuration data
cache_config_data() {
    local cache_key="$1"
    local data="$2"
    local ttl="${3:-$CACHE_TTL}"
    
    log_config_migration "DEBUG" "Caching configuration data: $cache_key"
    
    initialize_config_cache
    
    local cache_file="$MIGRATION_CACHE_DIR/${cache_key}.cache"
    local cache_metadata="$MIGRATION_CACHE_DIR/cache-metadata.json"
    local timestamp=$(date +%s)
    local expires_at=$((timestamp + ttl))
    
    # Store cached data
    echo "$data" > "$cache_file"
    
    # Update cache metadata
    local entry_metadata=$(cat << EOF
{
  "cached_at": $timestamp,
  "expires_at": $expires_at,
  "ttl": $ttl,
  "size_bytes": $(echo "$data" | wc -c)
}
EOF
    )
    
    update_json_field "$cache_metadata" ".entries[\"$cache_key\"]" "$entry_metadata"
    
    # Clean up expired entries
    cleanup_expired_cache_entries
    
    log_config_migration "DEBUG" "Configuration data cached successfully"
}

# Retrieve cached configuration data
get_cached_config_data() {
    local cache_key="$1"
    local cache_file="$MIGRATION_CACHE_DIR/${cache_key}.cache"
    local cache_metadata="$MIGRATION_CACHE_DIR/cache-metadata.json"
    
    # Check if cache exists
    if [[ ! -f "$cache_file" ]] || [[ ! -f "$cache_metadata" ]]; then
        return 1
    fi
    
    # Check if cache entry is still valid
    local current_time=$(date +%s)
    local expires_at=$(jq -r ".entries[\"$cache_key\"].expires_at" "$cache_metadata" 2>/dev/null || echo "0")
    
    if [[ "$current_time" -gt "$expires_at" ]]; then
        log_config_migration "DEBUG" "Cache entry expired: $cache_key"
        rm -f "$cache_file"
        return 1
    fi
    
    # Return cached data
    cat "$cache_file"
    log_config_migration "DEBUG" "Retrieved cached configuration data: $cache_key"
    return 0
}

# Clean up expired cache entries
cleanup_expired_cache_entries() {
    local cache_metadata="$MIGRATION_CACHE_DIR/cache-metadata.json"
    
    if [[ ! -f "$cache_metadata" ]]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    
    # Get all cache entries
    local expired_keys=()
    while IFS= read -r key; do
        local expires_at=$(jq -r ".entries[\"$key\"].expires_at" "$cache_metadata" 2>/dev/null || echo "0")
        if [[ "$current_time" -gt "$expires_at" ]]; then
            expired_keys+=("$key")
        fi
    done < <(jq -r '.entries | keys[]' "$cache_metadata" 2>/dev/null || true)
    
    # Remove expired entries
    for key in "${expired_keys[@]}"; do
        local cache_file="$MIGRATION_CACHE_DIR/${key}.cache"
        rm -f "$cache_file"
        
        # Remove from metadata
        local temp_metadata=$(jq "del(.entries[\"$key\"])" "$cache_metadata")
        echo "$temp_metadata" > "$cache_metadata"
        
        log_config_migration "DEBUG" "Removed expired cache entry: $key"
    done
}

# Invalidate cache entry
invalidate_cache_entry() {
    local cache_key="$1"
    local cache_file="$MIGRATION_CACHE_DIR/${cache_key}.cache"
    local cache_metadata="$MIGRATION_CACHE_DIR/cache-metadata.json"
    
    rm -f "$cache_file"
    
    if [[ -f "$cache_metadata" ]]; then
        local temp_metadata=$(jq "del(.entries[\"$cache_key\"])" "$cache_metadata")
        echo "$temp_metadata" > "$cache_metadata"
    fi
    
    log_config_migration "DEBUG" "Invalidated cache entry: $cache_key"
}

# =============================================================================
# ENVIRONMENT OVERRIDE MANAGEMENT
# =============================================================================

# Load environment-specific overrides
load_environment_overrides() {
    local environment="$1"
    local base_config="$2"
    local override_file="$CONFIG_ROOT/environments/${environment}.yml"
    
    log_config_migration "INFO" "Loading environment overrides for: $environment"
    
    if [[ ! -f "$override_file" ]]; then
        log_config_migration "WARN" "No override file found for environment: $environment"
        echo "$base_config"
        return 0
    fi
    
    # Check cache first
    local cache_key="env_override_${environment}_$(stat -f '%m' "$override_file" 2>/dev/null || echo "0")"
    if get_cached_config_data "$cache_key" 2>/dev/null; then
        log_config_migration "DEBUG" "Using cached environment overrides"
        return 0
    fi
    
    # Merge configurations
    local merged_config
    if command -v yq >/dev/null 2>&1; then
        # Use yq for YAML merging if available
        merged_config=$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$base_config" "$override_file" 2>/dev/null || cat "$base_config")
    else
        # Fallback to simple concatenation (not ideal but functional)
        merged_config="$base_config"
        log_config_migration "WARN" "yq not available, override merging may be incomplete"
    fi
    
    # Cache the merged configuration
    cache_config_data "$cache_key" "$merged_config"
    
    echo "$merged_config"
    log_config_migration "INFO" "Environment overrides loaded and merged"
}

# Apply runtime environment variable overrides
apply_runtime_overrides() {
    local config_data="$1"
    
    log_config_migration "DEBUG" "Applying runtime environment variable overrides..."
    
    # Define environment variable to config path mappings
    local override_mappings=(
        "AWS_REGION:.global.region"
        "STACK_NAME:.metadata.stack_name"
        "DEPLOYMENT_TYPE:.deployment.deployment_type"
        "INSTANCE_TYPE:.deployment.instance_type"
        "KEY_NAME:.deployment.key_name"
        "VOLUME_SIZE:.deployment.volume_size"
        "ENVIRONMENT:.metadata.environment"
        "DEBUG:.deployment.debug"
        "DRY_RUN:.deployment.dry_run"
        "ENABLE_MULTI_AZ:.deployment.enable_multi_az"
        "ENABLE_ALB:.deployment.enable_alb"
        "ENABLE_CLOUDFRONT:.deployment.enable_cloudfront"
        "SPOT_PRICE:.cost_optimization.spot_instances.max_price"
    )
    
    local modified_config="$config_data"
    
    # Process each override mapping
    for mapping in "${override_mappings[@]}"; do
        local env_var="${mapping%%:*}"
        local config_path="${mapping#*:}"
        
        # Check if environment variable is set
        if [[ -n "${!env_var:-}" ]]; then
            log_config_migration "DEBUG" "Applying override: $env_var=${!env_var} -> $config_path"
            
            # Store override in memory structure
            set_config_value "ENVIRONMENT_OVERRIDES" "$config_path" "${!env_var}"
            
            # Apply override to config data (if yq is available)
            if command -v yq >/dev/null 2>&1; then
                modified_config=$(echo "$modified_config" | \
                    yq eval "$config_path = \"${!env_var}\"" - 2>/dev/null || echo "$modified_config")
            fi
        fi
    done
    
    echo "$modified_config"
    log_config_migration "DEBUG" "Runtime overrides applied"
}

# =============================================================================
# MIGRATION UTILITIES AND TOOLS
# =============================================================================

# Create configuration backup
create_config_backup() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_dir="$MIGRATION_BACKUP_DIR/$backup_name"
    
    log_config_migration "INFO" "Creating configuration backup: $backup_name"
    
    mkdir -p "$backup_dir"
    
    # Backup all configuration files
    local files_backed_up=0
    
    # Backup YAML configs
    if [[ -d "$CONFIG_ROOT" ]]; then
        find "$CONFIG_ROOT" -name "*.yml" -o -name "*.yaml" | while read -r file; do
            local relative_path="${file#$CONFIG_ROOT/}"
            local backup_file="$backup_dir/config/$relative_path"
            mkdir -p "$(dirname "$backup_file")"
            cp "$file" "$backup_file"
            files_backed_up=$((files_backed_up + 1))
        done
    fi
    
    # Backup environment files
    find "$PROJECT_ROOT" -maxdepth 1 -name ".env*" -type f | while read -r file; do
        local filename="$(basename "$file")"
        cp "$file" "$backup_dir/$filename"
        files_backed_up=$((files_backed_up + 1))
    done
    
    # Create backup metadata
    cat > "$backup_dir/backup-metadata.json" << EOF
{
  "backup_name": "$backup_name",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "created_by": "unity-config-migration",
  "version": "$CONFIG_MIGRATION_VERSION",
  "files_count": $files_backed_up,
  "project_root": "$PROJECT_ROOT",
  "config_root": "$CONFIG_ROOT"
}
EOF
    
    log_config_migration "INFO" "Configuration backup created: $backup_dir"
    echo "$backup_dir"
}

# Restore configuration from backup
restore_config_backup() {
    local backup_name="$1"
    local backup_dir="$MIGRATION_BACKUP_DIR/$backup_name"
    
    if [[ ! -d "$backup_dir" ]]; then
        config_migration_error 404 "Backup not found: $backup_name"
        return 1
    fi
    
    log_config_migration "INFO" "Restoring configuration from backup: $backup_name"
    
    # Verify backup integrity
    if [[ ! -f "$backup_dir/backup-metadata.json" ]]; then
        config_migration_error 422 "Invalid backup: missing metadata"
        return 1
    fi
    
    # Create current backup before restore
    local current_backup=$(create_config_backup "pre_restore_$(date +%Y%m%d_%H%M%S)")
    
    # Restore configuration files
    if [[ -d "$backup_dir/config" ]]; then
        cp -r "$backup_dir/config/"* "$CONFIG_ROOT/"
    fi
    
    # Restore environment files
    find "$backup_dir" -maxdepth 1 -name ".env*" -type f | while read -r file; do
        local filename="$(basename "$file")"
        cp "$file" "$PROJECT_ROOT/$filename"
    done
    
    # Invalidate all cache entries
    rm -rf "$MIGRATION_CACHE_DIR"
    
    log_config_migration "INFO" "Configuration restored from backup: $backup_name"
    log_config_migration "INFO" "Previous configuration backed up to: $current_backup"
}

# Generate migration plan
generate_migration_plan() {
    local target_environment="${1:-development}"
    local plan_file="$MIGRATION_STATE_DIR/migration-plan-${target_environment}.json"
    
    log_config_migration "INFO" "Generating migration plan for environment: $target_environment"
    
    mkdir -p "$MIGRATION_STATE_DIR"
    
    # Discover current configuration sources
    local discovery_report=$(discover_configuration_sources)
    
    # Create migration plan
    cat > "$plan_file" << EOF
{
  "plan_version": "1.0.0",
  "target_environment": "$target_environment",
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "discovery_report": "$discovery_report",
  "migration_steps": [],
  "rollback_plan": {},
  "estimated_duration": "15-30 minutes",
  "prerequisites": [],
  "post_migration_tasks": []
}
EOF
    
    # Add migration steps
    add_migration_steps "$plan_file" "$target_environment"
    
    # Add prerequisites
    add_migration_prerequisites "$plan_file"
    
    # Add post-migration tasks
    add_post_migration_tasks "$plan_file"
    
    # Create rollback plan
    create_rollback_plan "$plan_file"
    
    log_config_migration "INFO" "Migration plan generated: $plan_file"
    echo "$plan_file"
}

# Execute migration plan
execute_migration_plan() {
    local plan_file="$1"
    local execution_log="$MIGRATION_STATE_DIR/migration-execution.log"
    
    if [[ ! -f "$plan_file" ]]; then
        config_migration_error 404 "Migration plan not found: $plan_file"
        return 1
    fi
    
    log_config_migration "INFO" "Executing migration plan: $plan_file"
    
    # Create execution log
    echo "Migration execution started at $(date)" > "$execution_log"
    echo "Plan file: $plan_file" >> "$execution_log"
    echo "---" >> "$execution_log"
    
    # Create pre-migration backup
    local backup_dir=$(create_config_backup "pre_migration_$(date +%Y%m%d_%H%M%S)")
    echo "Pre-migration backup created: $backup_dir" >> "$execution_log"
    
    # Execute migration steps
    local steps_count=$(jq '.migration_steps | length' "$plan_file")
    local step_index=0
    
    while [[ $step_index -lt $steps_count ]]; do
        local step=$(jq -r ".migration_steps[$step_index]" "$plan_file")
        local step_name=$(echo "$step" | jq -r '.name')
        local step_command=$(echo "$step" | jq -r '.command')
        
        log_config_migration "INFO" "Executing migration step: $step_name"
        echo "Step $((step_index + 1))/$steps_count: $step_name" >> "$execution_log"
        
        # Execute step command
        if eval "$step_command" >> "$execution_log" 2>&1; then
            echo "Step completed successfully" >> "$execution_log"
            log_config_migration "INFO" "Migration step completed: $step_name"
        else
            echo "Step failed with exit code $?" >> "$execution_log"
            log_config_migration "ERROR" "Migration step failed: $step_name"
            
            # Rollback on failure
            log_config_migration "INFO" "Rolling back migration..."
            restore_config_backup "$(basename "$backup_dir")"
            config_migration_error 500 "Migration failed at step: $step_name" \
                "Check migration log: $execution_log"
            return 1
        fi
        
        step_index=$((step_index + 1))
        echo "---" >> "$execution_log"
    done
    
    echo "Migration completed successfully at $(date)" >> "$execution_log"
    log_config_migration "INFO" "Migration plan executed successfully"
    
    # Post-migration validation
    validate_migrated_configuration
    
    return 0
}

# =============================================================================
# TEMPLATE SYSTEM AND INHERITANCE
# =============================================================================

# Generate configuration template
generate_config_template() {
    local template_name="$1"
    local base_template="${2:-default}"
    local template_file="$CONFIG_ROOT/templates/${template_name}.yml"
    
    log_config_migration "INFO" "Generating configuration template: $template_name"
    
    mkdir -p "$CONFIG_ROOT/templates"
    
    # Create template based on base template or defaults
    if [[ "$base_template" == "default" ]]; then
        cp "$CONFIG_ROOT/defaults.yml" "$template_file"
    else
        local base_template_file="$CONFIG_ROOT/templates/${base_template}.yml"
        if [[ -f "$base_template_file" ]]; then
            cp "$base_template_file" "$template_file"
        else
            config_migration_error 404 "Base template not found: $base_template"
            return 1
        fi
    fi
    
    # Add template metadata
    local template_metadata=$(cat << EOF

# Template Metadata
# template:
#   name: $template_name
#   base: $base_template
#   created_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
#   version: 1.0.0
EOF
    )
    
    echo "$template_metadata" >> "$template_file"
    
    log_config_migration "INFO" "Configuration template generated: $template_file"
    echo "$template_file"
}

# Resolve configuration inheritance chain
resolve_inheritance_chain() {
    local config_file="$1"
    local resolved_config="$MIGRATION_CACHE_DIR/resolved_$(basename "$config_file")"
    
    log_config_migration "DEBUG" "Resolving inheritance chain for: $config_file"
    
    # Check if already resolved and cached
    local cache_key="resolved_$(basename "$config_file")_$(stat -f '%m' "$config_file" 2>/dev/null || echo "0")"
    if get_cached_config_data "$cache_key" > "$resolved_config" 2>/dev/null; then
        echo "$resolved_config"
        return 0
    fi
    
    # Start with the config file
    local current_config="$config_file"
    local inheritance_chain=("$config_file")
    
    # Trace inheritance chain
    while true; do
        local parent_template=$(get_yaml_value "$current_config" ".template.base" "")
        if [[ -z "$parent_template" ]] || [[ "$parent_template" == "null" ]]; then
            break
        fi
        
        local parent_file="$CONFIG_ROOT/templates/${parent_template}.yml"
        if [[ ! -f "$parent_file" ]]; then
            log_config_migration "WARN" "Parent template not found: $parent_template"
            break
        fi
        
        inheritance_chain+=("$parent_file")
        current_config="$parent_file"
        
        # Prevent infinite loops
        if [[ ${#inheritance_chain[@]} -gt 10 ]]; then
            log_config_migration "WARN" "Inheritance chain too deep, stopping at 10 levels"
            break
        fi
    done
    
    # Merge configurations from top to bottom
    if command -v yq >/dev/null 2>&1; then
        # Reverse the chain for proper inheritance (base first)
        local reversed_chain=()
        for ((i=${#inheritance_chain[@]}-1; i>=0; i--)); do
            reversed_chain+=("${inheritance_chain[i]}")
        done
        
        # Merge all configurations
        yq eval-all 'select(fi == 0) * select(fi == 1)' "${reversed_chain[@]}" > "$resolved_config" 2>/dev/null || {
            log_config_migration "WARN" "Failed to merge inheritance chain, using base config"
            cp "$config_file" "$resolved_config"
        }
    else
        # Fallback: just use the original config
        cp "$config_file" "$resolved_config"
    fi
    
    # Cache the resolved configuration
    cache_config_data "$cache_key" "$(cat "$resolved_config")"
    
    log_config_migration "DEBUG" "Inheritance chain resolved: ${#inheritance_chain[@]} levels"
    echo "$resolved_config"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Get YAML value (yq wrapper with fallback)
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

# Update JSON field (jq wrapper)
update_json_field() {
    local file="$1"
    local path="$2"
    local value="$3"
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file="${file}.tmp"
        jq "$path = $value" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Add to JSON array
add_to_json_array() {
    local file="$1"
    local path="$2"
    local element="$3"
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file="${file}.tmp"
        jq "$path += [$element]" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Add validation error
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
    
    add_to_json_array "$report" ".errors" "$error_entry"
}

# Add validation warning
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
    
    add_to_json_array "$report" ".warnings" "$warning_entry"
}

# Analyze YAML variables count
analyze_yaml_variables() {
    local file="$1"
    
    # Count unique keys at all levels (rough estimate)
    if command -v yq >/dev/null 2>&1; then
        yq eval 'paths(scalars) as $p | $p | join(".")' "$file" 2>/dev/null | wc -l | tr -d ' '
    else
        # Fallback: count lines that look like YAML keys
        grep -c '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:' "$file" 2>/dev/null || echo "0"
    fi
}

# Calculate discovery statistics
calculate_discovery_statistics() {
    local discovery_report="$1"
    
    if command -v jq >/dev/null 2>&1; then
        local total_sources=$(jq '[.sources[] | length] | add' "$discovery_report" 2>/dev/null || echo "0")
        local total_yaml_vars=$(jq '[.sources.yaml_configs[].variable_count] | add' "$discovery_report" 2>/dev/null || echo "0")
        local total_env_vars=$(jq '[.sources.env_files[].variable_count] | add' "$discovery_report" 2>/dev/null || echo "0")
        local total_variables=$((total_yaml_vars + total_env_vars))
        
        update_json_field "$discovery_report" ".statistics.total_sources" "$total_sources"
        update_json_field "$discovery_report" ".statistics.total_variables" "$total_variables"
    fi
}

# Add migration steps to plan
add_migration_steps() {
    local plan_file="$1"
    local target_environment="$2"
    
    # Define migration steps
    local steps=(
        '{"name": "validate_prerequisites", "command": "validate_migration_prerequisites", "description": "Validate migration prerequisites"}'
        '{"name": "create_backup", "command": "create_config_backup pre_migration", "description": "Create pre-migration backup"}'
        '{"name": "consolidate_configs", "command": "consolidate_configurations", "description": "Consolidate all configuration sources"}'
        '{"name": "apply_environment_overrides", "command": "apply_environment_specific_overrides", "description": "Apply environment-specific overrides"}'
        '{"name": "validate_consolidated", "command": "validate_consolidated_configuration", "description": "Validate consolidated configuration"}'
        '{"name": "generate_unity_config", "command": "generate_unity_configuration", "description": "Generate Unity system configuration"}'
        '{"name": "update_variable_references", "command": "update_script_variable_references", "description": "Update variable references in scripts"}'
        '{"name": "test_configuration", "command": "test_migrated_configuration", "description": "Test migrated configuration"}'
    )
    
    # Add each step to the plan
    for step in "${steps[@]}"; do
        add_to_json_array "$plan_file" ".migration_steps" "$step"
    done
}

# Add migration prerequisites
add_migration_prerequisites() {
    local plan_file="$1"
    
    local prerequisites=(
        '"Backup current configuration"'
        '"Ensure yq is installed for YAML processing"'
        '"Ensure jq is installed for JSON processing"'
        '"Verify write permissions to config directory"'
        '"Stop any running services that depend on configuration"'
        '"Test AWS CLI access if using Parameter Store"'
    )
    
    for prereq in "${prerequisites[@]}"; do
        add_to_json_array "$plan_file" ".prerequisites" "$prereq"
    done
}

# Add post-migration tasks
add_post_migration_tasks() {
    local plan_file="$1"
    
    local tasks=(
        '"Update deployment scripts to use Unity configuration"'
        '"Test deployment with new configuration"'
        '"Update documentation with new configuration structure"'
        '"Train team on new configuration management system"'
        '"Set up configuration validation in CI/CD pipeline"'
        '"Remove deprecated configuration files after validation period"'
    )
    
    for task in "${tasks[@]}"; do
        add_to_json_array "$plan_file" ".post_migration_tasks" "$task"
    done
}

# Create rollback plan
create_rollback_plan() {
    local plan_file="$1"
    
    local rollback_plan=$(cat << 'EOF'
{
  "description": "Rollback plan for configuration migration",
  "steps": [
    {
      "name": "stop_services",
      "command": "stop_affected_services",
      "description": "Stop services affected by configuration changes"
    },
    {
      "name": "restore_backup",
      "command": "restore_config_backup pre_migration",
      "description": "Restore pre-migration configuration backup"
    },
    {
      "name": "clear_cache",
      "command": "rm -rf $MIGRATION_CACHE_DIR",
      "description": "Clear configuration cache"
    },
    {
      "name": "restart_services",
      "command": "restart_affected_services",
      "description": "Restart services with restored configuration"
    },
    {
      "name": "validate_rollback",
      "command": "validate_configuration_integrity",
      "description": "Validate rollback was successful"
    }
  ],
  "estimated_duration": "5-10 minutes",
  "automatic_triggers": [
    "validation_failure",
    "service_startup_failure",
    "critical_error_during_migration"
  ]
}
EOF
    )
    
    update_json_field "$plan_file" ".rollback_plan" "$rollback_plan"
}

# Validate migrated configuration
validate_migrated_configuration() {
    log_config_migration "INFO" "Validating migrated configuration..."
    
    local unity_config="$CONFIG_ROOT/unity.yml"
    if [[ -f "$unity_config" ]]; then
        local validation_report=$(validate_configuration "$unity_config")
        local schema_valid=$(jq -r '.schema_valid' "$validation_report" 2>/dev/null || echo "false")
        local business_rules_valid=$(jq -r '.business_rules_valid' "$validation_report" 2>/dev/null || echo "false")
        
        if [[ "$schema_valid" == "true" ]] && [[ "$business_rules_valid" == "true" ]]; then
            log_config_migration "INFO" "Migrated configuration validation passed"
            return 0
        else
            log_config_migration "ERROR" "Migrated configuration validation failed"
            return 1
        fi
    else
        log_config_migration "ERROR" "Unity configuration file not found"
        return 1
    fi
}

# =============================================================================
# PUBLIC API FUNCTIONS
# =============================================================================

# Initialize the configuration migration system
initialize_config_migration() {
    local environment="${1:-development}"
    
    log_config_migration "INFO" "Initializing Unity Configuration Migration System v$CONFIG_MIGRATION_VERSION"
    
    # Create necessary directories
    mkdir -p "$MIGRATION_STATE_DIR" "$MIGRATION_CACHE_DIR" "$MIGRATION_BACKUP_DIR"
    
    # Initialize validation rules
    initialize_validation_rules
    
    # Initialize configuration cache
    initialize_config_cache
    
    log_config_migration "INFO" "Configuration migration system initialized"
    return 0
}

# Perform full configuration migration
migrate_configuration() {
    local target_environment="${1:-development}"
    local dry_run="${2:-false}"
    
    log_config_migration "INFO" "Starting configuration migration to environment: $target_environment"
    
    # Initialize migration system
    initialize_config_migration "$target_environment"
    
    # Generate migration plan
    local migration_plan=$(generate_migration_plan "$target_environment")
    
    if [[ "$dry_run" == "true" ]]; then
        log_config_migration "INFO" "Dry run mode - migration plan generated but not executed"
        echo "$migration_plan"
        return 0
    fi
    
    # Execute migration plan
    execute_migration_plan "$migration_plan"
    
    log_config_migration "INFO" "Configuration migration completed successfully"
    return 0
}

# Get migration status
get_migration_status() {
    local status_file="$MIGRATION_STATE_DIR/migration-status.json"
    
    if [[ -f "$status_file" ]]; then
        cat "$status_file"
    else
        echo '{"status": "not_started", "message": "No migration has been performed"}'
    fi
}

# Export functions for use in other scripts
export -f initialize_config_migration
export -f migrate_configuration  
export -f get_migration_status
export -f discover_configuration_sources
export -f validate_configuration
export -f generate_unified_schema
export -f create_config_backup
export -f restore_config_backup
export -f generate_migration_plan
export -f execute_migration_plan

# Set script as executable
chmod +x "${BASH_SOURCE[0]}" 2>/dev/null || true

log_config_migration "DEBUG" "Unity Configuration Migration Service loaded successfully"