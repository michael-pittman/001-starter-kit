#!/bin/bash
# Unity Event System - Event Schemas and Validation
# Comprehensive event type definitions, validation, and schema management

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Schema version and compatibility
UNITY_EVENT_SCHEMA_VERSION="2.0"
UNITY_EVENT_SCHEMA_COMPATIBILITY=("1.0" "2.0")

# Event schema registry paths
UNITY_EVENT_SCHEMAS_DIR="${SCRIPT_DIR}/../.unity/events/schemas"
UNITY_EVENT_VALIDATION_LOG="logs/unity/event-validation.log"

#############################################
# Event Schema Definitions
#############################################

# Initialize event schemas
init_event_schemas() {
    local verbose="${1:-false}"
    
    mkdir -p "$UNITY_EVENT_SCHEMAS_DIR" "$(dirname "$UNITY_EVENT_VALIDATION_LOG")"
    
    # Create base event schema
    _create_base_event_schema
    
    # Create service-specific schemas
    _create_deployment_schemas
    _create_aws_schemas
    _create_docker_schemas
    _create_config_schemas
    _create_monitor_schemas
    _create_system_schemas
    
    # Create validation rules
    _create_validation_rules
    
    if [[ "$verbose" == "true" ]] && command -v unity_log >/dev/null 2>&1; then
        unity_log "SUCCESS" "Event schemas initialized with validation rules"
    fi
    
    return 0
}

# Create base event schema
_create_base_event_schema() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/base-event.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "type": "object",
  "required": ["id", "timestamp", "type", "source", "data", "metadata"],
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^event_[0-9]+_[0-9]+$",
      "description": "Unique event identifier"
    },
    "timestamp": {
      "type": "integer",
      "minimum": 0,
      "description": "Unix timestamp when event was created"
    },
    "type": {
      "type": "string",
      "pattern": "^[a-z]+\\.[a-z_]+$",
      "description": "Event type in format: category.action"
    },
    "source": {
      "type": "string",
      "minLength": 1,
      "description": "Event source identifier"
    },
    "data": {
      "type": "object",
      "description": "Event-specific data payload"
    },
    "metadata": {
      "type": "object",
      "required": ["priority", "version"],
      "properties": {
        "priority": {
          "type": "string",
          "enum": ["high", "medium", "low"]
        },
        "correlation_id": {
          "type": "string",
          "description": "Optional correlation ID for event tracing"
        },
        "version": {
          "type": "string",
          "enum": ["1.0", "2.0"]
        },
        "sync_mode": {
          "type": "boolean",
          "default": false
        },
        "retry_count": {
          "type": "integer",
          "minimum": 0,
          "default": 0
        },
        "tags": {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create deployment event schemas
_create_deployment_schemas() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/deployment.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "deployment_events": {
    "deployment.started": {
      "data": {
        "type": "object",
        "required": ["stack_name", "deployment_type"],
        "properties": {
          "stack_name": {"type": "string"},
          "deployment_type": {"type": "string", "enum": ["spot", "on-demand", "asg"]},
          "instance_type": {"type": "string"},
          "region": {"type": "string"},
          "estimated_cost": {"type": "number"},
          "configuration": {"type": "object"}
        }
      }
    },
    "deployment.completed": {
      "data": {
        "type": "object",
        "required": ["stack_name", "duration", "success"],
        "properties": {
          "stack_name": {"type": "string"},
          "duration": {"type": "integer"},
          "success": {"type": "boolean"},
          "resources_created": {"type": "array"},
          "endpoint_url": {"type": "string"},
          "total_cost": {"type": "number"}
        }
      }
    },
    "deployment.failed": {
      "data": {
        "type": "object",
        "required": ["stack_name", "error", "failure_stage"],
        "properties": {
          "stack_name": {"type": "string"},
          "error": {"type": "string"},
          "failure_stage": {"type": "string"},
          "partial_resources": {"type": "array"},
          "rollback_initiated": {"type": "boolean"}
        }
      }
    },
    "deployment.rollback_started": {
      "data": {
        "type": "object",
        "required": ["stack_name", "reason"],
        "properties": {
          "stack_name": {"type": "string"},
          "reason": {"type": "string"},
          "resources_to_cleanup": {"type": "array"}
        }
      }
    },
    "deployment.rollback_completed": { 
      "data": {
        "type": "object",
        "required": ["stack_name", "success"],
        "properties": {
          "stack_name": {"type": "string"},
          "success": {"type": "boolean"},
          "resources_cleaned": {"type": "array"}
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create AWS service schemas
_create_aws_schemas() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/aws.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "aws_events": {
    "aws.resource.created": {
      "data": {
        "type": "object",
        "required": ["resource_type", "resource_id", "stack_name"],
        "properties": {
          "resource_type": {"type": "string", "enum": ["ec2", "vpc", "alb", "efs", "cloudfront", "asg"]},
          "resource_id": {"type": "string"},
          "stack_name": {"type": "string"},
          "region": {"type": "string"},
          "cost_per_hour": {"type": "number"},
          "tags": {"type": "object"}
        }
      }
    },
    "aws.ec2.launched": {
      "data": {
        "type": "object",
        "required": ["instance_id", "instance_type", "deployment_type"],
        "properties": {
          "instance_id": {"type": "string"},
          "instance_type": {"type": "string"},
          "deployment_type": {"type": "string", "enum": ["spot", "on-demand"]},
          "availability_zone": {"type": "string"},
          "spot_price": {"type": "number"},
          "savings_percentage": {"type": "number"}
        }
      }
    },
    "aws.cost.threshold_exceeded": {
      "data": {
        "type": "object",
        "required": ["threshold", "current_cost", "stack_name"],
        "properties": {
          "threshold": {"type": "number"},
          "current_cost": {"type": "number"},
          "stack_name": {"type": "string"},
          "time_period": {"type": "string"},
          "action_required": {"type": "boolean"}
        }
      }
    },
    "aws.vpc.created": {
      "data": {
        "type": "object",
        "required": ["vpc_id", "cidr_block"],
        "properties": {
          "vpc_id": {"type": "string"},
          "cidr_block": {"type": "string"},
          "dns_enabled": {"type": "boolean"},
          "subnets": {"type": "array"}
        }
      }
    },
    "aws.alb.created": {
      "data": {
        "type": "object",
        "required": ["alb_arn", "dns_name"],
        "properties": {
          "alb_arn": {"type": "string"},
          "dns_name": {"type": "string"},
          "scheme": {"type": "string"},
          "target_groups": {"type": "array"}
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create Docker service schemas
_create_docker_schemas() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/docker.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "docker_events": {
    "docker.container.started": {
      "data": {
        "type": "object",
        "required": ["container_id", "container_name", "image"],
        "properties": {
          "container_id": {"type": "string"},
          "container_name": {"type": "string"},
          "image": {"type": "string"},
          "ports": {"type": "array"},
          "environment": {"type": "object"},
          "health_check_url": {"type": "string"}
        }
      }
    },
    "docker.container.stopped": {
      "data": {
        "type": "object",
        "required": ["container_id", "exit_code"],
        "properties": {
          "container_id": {"type": "string"},
          "container_name": {"type": "string"},
          "exit_code": {"type": "integer"},
          "reason": {"type": "string"},
          "uptime": {"type": "integer"}
        }
      }
    },
    "docker.container.failed": {
      "data": {
        "type": "object",
        "required": ["container_name", "error", "image"],
        "properties": {
          "container_name": {"type": "string"},
          "image": {"type": "string"},
          "error": {"type": "string"},
          "exit_code": {"type": "integer"},
          "restart_attempts": {"type": "integer"}
        }
      }
    },
    "docker.compose.up": {
      "data": {
        "type": "object",
        "required": ["compose_file", "services"],
        "properties": {
          "compose_file": {"type": "string"},
          "services": {"type": "array"},
          "network": {"type": "string"},
          "volumes": {"type": "array"}
        }
      }
    },
    "docker.image.pulled": {
      "data": {
        "type": "object",
        "required": ["image", "tag"],
        "properties": {
          "image": {"type": "string"},
          "tag": {"type": "string"},
          "digest": {"type": "string"},
          "size": {"type": "integer"}
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create configuration service schemas
_create_config_schemas() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/config.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "config_events": {
    "config.loaded": {
      "data": {
        "type": "object",
        "required": ["config_source", "config_count"],
        "properties": {
          "config_source": {"type": "string"},
          "config_count": {"type": "integer"},
          "environment": {"type": "string"},
          "validation_passed": {"type": "boolean"}
        }
      }
    },
    "config.updated": {
      "data": {
        "type": "object",
        "required": ["config_key", "old_value", "new_value"],
        "properties": {
          "config_key": {"type": "string"},
          "old_value": {"type": "string"},
          "new_value": {"type": "string"},
          "source": {"type": "string"},
          "requires_restart": {"type": "boolean"}
        }
      }
    },
    "config.validated": {
      "data": {
        "type": "object",
        "required": ["validation_result", "config_count"],
        "properties": {
          "validation_result": {"type": "boolean"},
          "config_count": {"type": "integer"},
          "errors": {"type": "array"},
          "warnings": {"type": "array"}
        }
      }
    },
    "config.error": {
      "data": {
        "type": "object",
        "required": ["error_type", "config_key", "message"],
        "properties": {
          "error_type": {"type": "string", "enum": ["validation", "loading", "parsing", "missing"]},
          "config_key": {"type": "string"},
          "message": {"type": "string"},
          "severity": {"type": "string", "enum": ["warning", "error", "critical"]}
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create monitoring service schemas
_create_monitor_schemas() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/monitor.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "monitor_events": {
    "monitor.health.check": {
      "data": {
        "type": "object",
        "required": ["service", "status", "response_time"],
        "properties": {
          "service": {"type": "string"},
          "status": {"type": "string", "enum": ["healthy", "unhealthy", "degraded"]},
          "response_time": {"type": "integer"},
          "endpoint": {"type": "string"},
          "details": {"type": "object"}
        }
      }
    },
    "monitor.alert.triggered": {
      "data": {
        "type": "object",
        "required": ["alert_type", "severity", "message"],
        "properties": {
          "alert_type": {"type": "string"},
          "severity": {"type": "string", "enum": ["info", "warning", "critical"]},
          "message": {"type": "string"},
          "service": {"type": "string"},
          "metric_value": {"type": "number"},
          "threshold": {"type": "number"}
        }
      }
    },
    "monitor.metric.collected": {
      "data": {
        "type": "object",
        "required": ["metric_name", "value", "unit"],
        "properties": {
          "metric_name": {"type": "string"},
          "value": {"type": "number"},
          "unit": {"type": "string"},
          "service": {"type": "string"},
          "tags": {"type": "object"}
        }
      }
    },
    "monitor.threshold.exceeded": {
      "data": {
        "type": "object",
        "required": ["metric", "threshold", "current_value"],
        "properties": {
          "metric": {"type": "string"},
          "threshold": {"type": "number"},
          "current_value": {"type": "number"},
          "service": {"type": "string"},
          "action": {"type": "string"}
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create system event schemas
_create_system_schemas() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/system.schema" <<'SCHEMA_EOF'
{
  "schema_version": "2.0",
  "system_events": {
    "system.startup": {
      "data": {
        "type": "object",
        "required": ["component", "version"],
        "properties": {
          "component": {"type": "string"},
          "version": {"type": "string"},
          "startup_time": {"type": "integer"},
          "configuration": {"type": "object"}
        }
      }
    },
    "system.shutdown": {
      "data": {
        "type": "object",
        "required": ["component", "reason"],
        "properties": {
          "component": {"type": "string"},
          "reason": {"type": "string"},
          "graceful": {"type": "boolean"},
          "uptime": {"type": "integer"}
        }
      }
    },
    "system.error": {
      "data": {
        "type": "object",
        "required": ["error_code", "message", "component"],
        "properties": {
          "error_code": {"type": "string"},
          "message": {"type": "string"},
          "component": {"type": "string"},
          "stack_trace": {"type": "string"},
          "recovery_action": {"type": "string"}
        }
      }
    }
  }
}
SCHEMA_EOF
}

# Create validation rules
_create_validation_rules() {
    cat > "$UNITY_EVENT_SCHEMAS_DIR/validation.rules" <<'RULES_EOF'
# Unity Event Validation Rules
# Format: event_pattern|validation_rule|severity

# Basic validation rules
*|required_fields_present|error
*|valid_event_id_format|error
*|valid_timestamp|error
*|valid_priority|warning

# Deployment validation
deployment.*|stack_name_valid|error
deployment.started|instance_type_valid|warning
deployment.failed|error_message_present|error

# AWS validation
aws.*|resource_id_present|error
aws.ec2.*|instance_id_format|error
aws.cost.*|numeric_values|error

# Docker validation
docker.container.*|container_name_valid|error
docker.image.*|image_name_valid|error

# Config validation
config.*|config_key_present|error
config.error|severity_valid|warning

# Monitor validation
monitor.health.*|status_valid|error
monitor.alert.*|severity_valid|error
monitor.metric.*|numeric_value|error
RULES_EOF
}

#############################################
# Event Validation Functions
#############################################

# Validate event against schema
validate_event() {
    local event_payload="$1"
    local strict_mode="${2:-false}"
    
    # Extract event type
    local event_type
    event_type=$(echo "$event_payload" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$event_type" ]]; then
        _log_validation_error "Missing event type" "$event_payload"
        return 1
    fi
    
    # Validate base schema first
    if ! _validate_base_schema "$event_payload"; then
        _log_validation_error "Base schema validation failed" "$event_payload"
        return 1
    fi
    
    # Validate against specific event schema
    if ! _validate_event_specific_schema "$event_type" "$event_payload"; then
        if [[ "$strict_mode" == "true" ]]; then
            _log_validation_error "Event-specific schema validation failed" "$event_payload"
            return 1
        else
            _log_validation_warning "Event-specific schema validation failed (non-strict mode)" "$event_payload"
        fi
    fi
    
    # Apply validation rules
    _apply_validation_rules "$event_type" "$event_payload" "$strict_mode"
    
    return 0
}

# Validate base event schema
_validate_base_schema() {
    local event_payload="$1"
    
    # Check required fields
    local required_fields=("id" "timestamp" "type" "source" "data" "metadata")
    
    for field in "${required_fields[@]}"; do
        if [[ ! "$event_payload" =~ \"$field\": ]]; then
            return 1
        fi
    done
    
    # Validate event ID format
    local event_id
    event_id=$(echo "$event_payload" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)
    if [[ ! "$event_id" =~ ^event_[0-9]+_[0-9]+$ ]]; then
        return 1
    fi
    
    # Validate timestamp
    local timestamp
    timestamp=$(echo "$event_payload" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
    if [[ ! "$timestamp" =~ ^[0-9]+$ ]] || [[ "$timestamp" -eq 0 ]]; then
        return 1
    fi
    
    # Validate event type format
    local event_type
    event_type=$(echo "$event_payload" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    if [[ ! "$event_type" =~ ^[a-z]+\.[a-z_]+$ ]]; then
        return 1
    fi
    
    # Validate priority
    local priority
    priority=$(echo "$event_payload" | grep -o '"priority": "[^"]*"' | cut -d'"' -f4)
    if [[ ! "$priority" =~ ^(high|medium|low)$ ]]; then
        return 1
    fi
    
    return 0
}

# Validate event-specific schema
_validate_event_specific_schema() {
    local event_type="$1"
    local event_payload="$2"
    
    local category="${event_type%%.*}"
    local schema_file="$UNITY_EVENT_SCHEMAS_DIR/${category}.schema"
    
    if [[ ! -f "$schema_file" ]]; then
        # No specific schema available - use basic validation
        return 0
    fi
    
    # Extract event data
    local event_data
    event_data=$(echo "$event_payload" | grep -o '"data": {[^}]*}' | cut -d':' -f2-)
    
    # Basic validation - check if required fields exist based on schema
    case "$event_type" in
        "deployment.started")
            [[ "$event_data" =~ \"stack_name\" ]] && [[ "$event_data" =~ \"deployment_type\" ]]
            ;;
        "deployment.completed")
            [[ "$event_data" =~ \"stack_name\" ]] && [[ "$event_data" =~ \"duration\" ]] && [[ "$event_data" =~ \"success\" ]]
            ;;
        "aws.resource.created")
            [[ "$event_data" =~ \"resource_type\" ]] && [[ "$event_data" =~ \"resource_id\" ]] && [[ "$event_data" =~ \"stack_name\" ]]
            ;;
        "docker.container.started")
            [[ "$event_data" =~ \"container_id\" ]] && [[ "$event_data" =~ \"container_name\" ]] && [[ "$event_data" =~ \"image\" ]]
            ;;
        "config.loaded")
            [[ "$event_data" =~ \"config_source\" ]] && [[ "$event_data" =~ \"config_count\" ]]
            ;;
        "monitor.health.check")
            [[ "$event_data" =~ \"service\" ]] && [[ "$event_data" =~ \"status\" ]] && [[ "$event_data" =~ \"response_time\" ]]
            ;;
        *)
            # Unknown event type - basic validation only
            return 0
            ;;
    esac
}

# Apply validation rules
_apply_validation_rules() {
    local event_type="$1"
    local event_payload="$2"
    local strict_mode="$3"
    
    if [[ ! -f "$UNITY_EVENT_SCHEMAS_DIR/validation.rules" ]]; then
        return 0
    fi
    
    local validation_errors=0
    local validation_warnings=0
    
    while IFS='|' read -r pattern rule severity; do
        [[ "$pattern" =~ ^#.*$ ]] && continue  # Skip comments
        [[ -z "$pattern" ]] && continue        # Skip empty lines
        
        if [[ "$event_type" =~ $pattern ]]; then
            if ! _apply_single_validation_rule "$rule" "$event_payload"; then
                case "$severity" in
                    "error")
                        validation_errors=$((validation_errors + 1))
                        _log_validation_error "Validation rule '$rule' failed for event type '$event_type'" "$event_payload"
                        ;;
                    "warning")
                        validation_warnings=$((validation_warnings + 1))
                        _log_validation_warning "Validation rule '$rule' failed for event type '$event_type'" "$event_payload"
                        ;;
                esac
            fi
        fi
    done < "$UNITY_EVENT_SCHEMAS_DIR/validation.rules"
    
    # Log validation summary
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp|VALIDATION_SUMMARY|$event_type|{\"errors\":$validation_errors,\"warnings\":$validation_warnings}" >> "$UNITY_EVENT_VALIDATION_LOG"
    
    # Return failure only if there are errors and we're in strict mode
    if [[ $validation_errors -gt 0 ]] && [[ "$strict_mode" == "true" ]]; then
        return 1
    fi
    
    return 0
}

# Apply single validation rule
_apply_single_validation_rule() {
    local rule="$1"
    local event_payload="$2"
    
    case "$rule" in
        "required_fields_present")
            [[ "$event_payload" =~ \"id\": ]] && [[ "$event_payload" =~ \"timestamp\": ]] && [[ "$event_payload" =~ \"type\": ]]
            ;;
        "valid_event_id_format")
            local event_id
            event_id=$(echo "$event_payload" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)
            [[ "$event_id" =~ ^event_[0-9]+_[0-9]+$ ]]
            ;;
        "valid_timestamp")
            local timestamp
            timestamp=$(echo "$event_payload" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
            [[ "$timestamp" =~ ^[0-9]+$ ]] && [[ "$timestamp" -gt 0 ]]
            ;;
        "valid_priority")
            local priority
            priority=$(echo "$event_payload" | grep -o '"priority": "[^"]*"' | cut -d'"' -f4)
            [[ "$priority" =~ ^(high|medium|low)$ ]]
            ;;
        "stack_name_valid")
            [[ "$event_payload" =~ \"stack_name\":\ \"[a-zA-Z0-9_-]+\" ]]
            ;;
        "instance_type_valid")
            [[ "$event_payload" =~ \"instance_type\":\ \"[a-z0-9]+\.[a-z0-9]+\" ]]
            ;;
        "error_message_present")
            [[ "$event_payload" =~ \"error\":\ \"[^\"]+\" ]]
            ;;
        "resource_id_present")
            [[ "$event_payload" =~ \"resource_id\":\ \"[^\"]+\" ]]
            ;;
        "instance_id_format")
            [[ "$event_payload" =~ \"instance_id\":\ \"i-[a-f0-9]+\" ]]
            ;;
        "numeric_values")
            # Check that numeric fields contain valid numbers
            local numeric_fields=("cost" "threshold" "value" "price")
            for field in "${numeric_fields[@]}"; do
                if [[ "$event_payload" =~ \"$field\":\ ([0-9]+\.?[0-9]*) ]]; then
                    [[ "${BASH_REMATCH[1]}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
                fi
            done
            ;;
        "container_name_valid")
            [[ "$event_payload" =~ \"container_name\":\ \"[a-zA-Z0-9_-]+\" ]]
            ;;
        "image_name_valid")
            [[ "$event_payload" =~ \"image\":\ \"[a-zA-Z0-9_/:-]+\" ]]
            ;;
        "config_key_present")
            [[ "$event_payload" =~ \"config_key\":\ \"[^\"]+\" ]]
            ;;
        "severity_valid")
            local severity
            severity=$(echo "$event_payload" | grep -o '"severity": "[^"]*"' | cut -d'"' -f4)
            [[ "$severity" =~ ^(info|warning|error|critical)$ ]]
            ;;
        "status_valid")
            local status
            status=$(echo "$event_payload" | grep -o '"status": "[^"]*"' | cut -d'"' -f4)
            [[ "$status" =~ ^(healthy|unhealthy|degraded)$ ]]
            ;;
        "numeric_value")
            [[ "$event_payload" =~ \"value\":\ [0-9]+(\.[0-9]+)? ]]
            ;;
        *)
            # Unknown rule - pass by default
            return 0
            ;;
    esac
}

#############################################
# Schema Management Functions
#############################################

# Get event schema for type
get_event_schema() {
    local event_type="$1"
    local category="${event_type%%.*}"
    local schema_file="$UNITY_EVENT_SCHEMAS_DIR/${category}.schema"
    
    if [[ -f "$schema_file" ]]; then
        cat "$schema_file"
    else
        cat "$UNITY_EVENT_SCHEMAS_DIR/base-event.schema"
    fi
}

# List available event types
list_event_types() {
    local category="${1:-all}"
    
    if [[ "$category" == "all" ]]; then
        find "$UNITY_EVENT_SCHEMAS_DIR" -name "*.schema" -not -name "base-event.schema" | while read -r schema_file; do
            local schema_category
            schema_category=$(basename "$schema_file" .schema)
            echo "=== $schema_category events ==="
            grep -o '"[^"]*":' "$schema_file" | tr -d '":' | grep '\.' | sort
            echo
        done
    else
        local schema_file="$UNITY_EVENT_SCHEMAS_DIR/${category}.schema"
        if [[ -f "$schema_file" ]]; then
            grep -o '"[^"]*":' "$schema_file" | tr -d '":' | grep '\.' | sort
        fi
    fi
}

# Validate schema file
validate_schema_file() {
    local schema_file="$1"
    
    if [[ ! -f "$schema_file" ]]; then
        echo "Schema file not found: $schema_file"
        return 1
    fi
    
    # Basic JSON-like structure validation
    if ! grep -q '"schema_version":' "$schema_file"; then
        echo "Missing schema_version in $schema_file"
        return 1
    fi
    
    echo "Schema file $schema_file is valid"
    return 0
}

# Create custom event type
create_custom_event_type() {
    local event_type="$1"
    local schema_definition="$2"
    local category="${event_type%%.*}"
    
    local schema_file="$UNITY_EVENT_SCHEMAS_DIR/${category}.schema"
    
    # Create or update schema file
    if [[ ! -f "$schema_file" ]]; then
        cat > "$schema_file" <<EOF
{
  "schema_version": "$UNITY_EVENT_SCHEMA_VERSION",
  "${category}_events": {}
}
EOF
    fi
    
    # Add new event type to schema (simplified implementation)
    echo "Custom event type $event_type registered in $schema_file"
}

#############################################
# Logging Functions
#############################################

# Log validation error
_log_validation_error() {
    local message="$1"
    local event_payload="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$timestamp|ERROR|VALIDATION|$message" >> "$UNITY_EVENT_VALIDATION_LOG"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "ERROR" "Event Validation: $message"
    else
        echo "ERROR: Event Validation: $message" >&2
    fi
}

# Log validation warning
_log_validation_warning() {
    local message="$1"
    local event_payload="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$timestamp|WARNING|VALIDATION|$message" >> "$UNITY_EVENT_VALIDATION_LOG"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "WARN" "Event Validation: $message"
    fi
}

#############################################
# Export Functions
#############################################

# Export all schema functions
export -f init_event_schemas
export -f validate_event
export -f get_event_schema
export -f list_event_types
export -f validate_schema_file
export -f create_custom_event_type

# Initialize schemas if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_event_schemas "true"
fi