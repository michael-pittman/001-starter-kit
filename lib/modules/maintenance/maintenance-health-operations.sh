#!/bin/bash
#
# Maintenance Health Operations Module
# Contains all health check operations extracted from maintenance scripts
#

# Global health state
declare -g OVERALL_HEALTH=true
declare -g HEALTH_REPORT=""
declare -g HEALTH_ISSUES=0
declare -g HEALTH_WARNINGS=0

# =============================================================================
# SERVICE HEALTH CHECKS
# =============================================================================

# Check PostgreSQL Database
check_postgres() {
    local service="PostgreSQL Database"
    increment_counter "processed"
    
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^postgres$"; then
        check_result "$service" "unhealthy" "Container not running"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    # Check if PostgreSQL is ready
    if docker exec postgres pg_isready -U n8n >/dev/null 2>&1; then
        # Advanced check: Can we actually query?
        if docker exec postgres psql -U n8n -d n8n -c "SELECT 1" >/dev/null 2>&1; then
            # Check connection count
            local connections=$(docker exec postgres psql -U n8n -d n8n -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'" 2>/dev/null | tr -d ' ' || echo "0")
            
            # Check database size
            local db_size=$(docker exec postgres psql -U n8n -d n8n -t -c "SELECT pg_size_pretty(pg_database_size('n8n'))" 2>/dev/null | tr -d ' ' || echo "unknown")
            
            check_result "$service" "healthy" "Active connections: $connections, DB size: $db_size"
            
            # Check for warnings
            if [[ ${connections:-0} -gt 50 ]]; then
                log_maintenance "WARNING" "High connection count: $connections"
                ((HEALTH_WARNINGS++))
            fi
        else
            check_result "$service" "unhealthy" "Database is up but queries failing"
            ((HEALTH_ISSUES++))
            return 1
        fi
    else
        check_result "$service" "unhealthy" "Database is not responding"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    return 0
}

# Check n8n Workflow Engine
check_n8n() {
    local service="n8n Workflow Engine"
    increment_counter "processed"
    
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^n8n$"; then
        check_result "$service" "unhealthy" "Container not running"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    # Check if n8n is responding
    if curl -sf http://localhost:5678/healthz >/dev/null 2>&1; then
        # Check if we can access the API
        if curl -sf http://localhost:5678/api/v1/info >/dev/null 2>&1; then
            # Get workflow count if possible
            local workflow_count=$(curl -s http://localhost:5678/api/v1/workflows 2>/dev/null | jq '.data | length' 2>/dev/null || echo "unknown")
            check_result "$service" "healthy" "API responsive, Workflows: $workflow_count"
        else
            check_result "$service" "healthy" "Basic health OK, API requires authentication"
        fi
        
        # Check memory usage
        local memory_usage=$(docker stats --no-stream --format "{{.MemUsage}}" n8n 2>/dev/null || echo "unknown")
        HEALTH_REPORT+="  └─ Memory Usage: $memory_usage\n"
    else
        check_result "$service" "unhealthy" "Service not responding on port 5678"
        ((HEALTH_ISSUES++))
        
        # Check if port is in use by another process
        if check_port 5678 >/dev/null; then
            log_maintenance "WARNING" "Port 5678 is in use but n8n not responding"
        fi
        
        return 1
    fi
    
    return 0
}

# Check Ollama LLM Service
check_ollama() {
    local service="Ollama LLM Service"
    increment_counter "processed"
    
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^ollama$"; then
        check_result "$service" "unhealthy" "Container not running"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    # Check if Ollama API is responding
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        # Check loaded models
        local models=$(curl -s http://localhost:11434/api/tags 2>/dev/null | jq -r '.models[].name' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        local model_count=$(echo "$models" | tr ',' '\n' | grep -c . || echo 0)
        
        if [[ $model_count -gt 0 ]]; then
            check_result "$service" "healthy" "Models loaded: $models"
        else
            check_result "$service" "healthy" "Service running, no models loaded yet"
            ((HEALTH_WARNINGS++))
        fi
        
        # Check GPU availability
        if docker exec ollama nvidia-smi >/dev/null 2>&1; then
            local gpu_info=$(docker exec ollama nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
            if [[ -n "$gpu_info" ]]; then
                local gpu_name=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
                local gpu_memory_used=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')
                local gpu_memory_total=$(echo "$gpu_info" | cut -d',' -f3 | tr -d ' ')
                local gpu_utilization=$(echo "$gpu_info" | cut -d',' -f4 | tr -d ' ')
                
                HEALTH_REPORT+="  └─ GPU: $gpu_name, Memory: ${gpu_memory_used}MB/${gpu_memory_total}MB, Utilization: ${gpu_utilization}%\n"
                
                # Check for GPU memory pressure
                if [[ $gpu_memory_total -gt 0 ]]; then
                    local gpu_memory_percent=$((gpu_memory_used * 100 / gpu_memory_total))
                    if [[ $gpu_memory_percent -gt 90 ]]; then
                        log_maintenance "WARNING" "GPU memory usage high: ${gpu_memory_percent}%"
                        ((HEALTH_WARNINGS++))
                    fi
                fi
            fi
        else
            HEALTH_REPORT+="  └─ GPU: Not available or not configured\n"
            ((HEALTH_WARNINGS++))
        fi
    else
        check_result "$service" "unhealthy" "Service not responding on port 11434"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    return 0
}

# Check Qdrant Vector Database
check_qdrant() {
    local service="Qdrant Vector Database"
    increment_counter "processed"
    
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^qdrant$"; then
        check_result "$service" "unhealthy" "Container not running"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    # Check if Qdrant is ready
    if curl -sf http://localhost:6333/readyz >/dev/null 2>&1; then
        # Get cluster info
        local cluster_info=$(curl -s http://localhost:6333/cluster 2>/dev/null)
        local status=$(echo "$cluster_info" | jq -r '.result.status' 2>/dev/null || echo "unknown")
        
        # Check collections
        local collections=$(curl -s http://localhost:6333/collections 2>/dev/null | jq -r '.result.collections[].name' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        local collection_count=$(echo "$collections" | tr ',' '\n' | grep -c . || echo 0)
        
        if [[ -n "$collections" ]]; then
            check_result "$service" "healthy" "Status: $status, Collections: $collections"
            
            # Check collection sizes
            for collection in $(echo "$collections" | tr ',' ' '); do
                local collection_info=$(curl -s "http://localhost:6333/collections/$collection" 2>/dev/null)
                local vectors_count=$(echo "$collection_info" | jq -r '.result.vectors_count' 2>/dev/null || echo "0")
                HEALTH_REPORT+="  └─ Collection '$collection': $vectors_count vectors\n"
            done
        else
            check_result "$service" "healthy" "Status: $status, No collections created yet"
        fi
        
        # Check storage usage
        local storage_info=$(docker exec qdrant du -sh /qdrant/storage 2>/dev/null | cut -f1 || echo "unknown")
        HEALTH_REPORT+="  └─ Storage Usage: $storage_info\n"
    else
        check_result "$service" "unhealthy" "Service not responding on port 6333"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    return 0
}

# Check Crawl4AI Service
check_crawl4ai() {
    local service="Crawl4AI Service"
    increment_counter "processed"
    
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "crawl4ai"; then
        check_result "$service" "unhealthy" "Container not running"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    # Check if Crawl4AI is responding
    if curl -sf http://localhost:11235/health >/dev/null 2>&1; then
        # Check service status
        local health_response=$(curl -s http://localhost:11235/health 2>/dev/null)
        local status=$(echo "$health_response" | jq -r '.status' 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "healthy" ]] || [[ "$status" == "ok" ]]; then
            # Get additional metrics if available
            local active_crawls=$(echo "$health_response" | jq -r '.active_crawls' 2>/dev/null || echo "0")
            local total_crawls=$(echo "$health_response" | jq -r '.total_crawls' 2>/dev/null || echo "0")
            
            check_result "$service" "healthy" "Status: $status, Active crawls: $active_crawls, Total: $total_crawls"
        else
            check_result "$service" "healthy" "Service running, status: $status"
            if [[ "$status" != "healthy" ]] && [[ "$status" != "ok" ]]; then
                ((HEALTH_WARNINGS++))
            fi
        fi
        
        # Check resource usage
        local cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" crawl4ai 2>/dev/null || echo "unknown")
        local memory_usage=$(docker stats --no-stream --format "{{.MemUsage}}" crawl4ai 2>/dev/null || echo "unknown")
        HEALTH_REPORT+="  └─ Resources: CPU: $cpu_usage, Memory: $memory_usage\n"
    else
        check_result "$service" "unhealthy" "Service not responding on port 11235"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    return 0
}

# Check GPU availability and health
check_gpu() {
    local service="GPU Resources"
    increment_counter "processed"
    
    # Check if nvidia-smi is available
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        # Check if running in container with GPU
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "gpu-monitor"; then
            if docker exec gpu-monitor nvidia-smi >/dev/null 2>&1; then
                check_gpu_in_container
                return $?
            fi
        fi
        
        check_result "$service" "unhealthy" "NVIDIA drivers not installed or GPU not available"
        ((HEALTH_WARNINGS++))
        return 1
    fi
    
    # Get GPU information
    local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    
    if [[ $gpu_count -gt 0 ]]; then
        check_result "$service" "healthy" "Found $gpu_count GPU(s)"
        
        # Check each GPU
        nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits | \
        while IFS=',' read -r index name temp utilization mem_used mem_total power; do
            # Trim whitespace
            index=$(echo "$index" | tr -d ' ')
            name=$(echo "$name" | tr -d ' ')
            temp=$(echo "$temp" | tr -d ' ')
            utilization=$(echo "$utilization" | tr -d ' ')
            mem_used=$(echo "$mem_used" | tr -d ' ')
            mem_total=$(echo "$mem_total" | tr -d ' ')
            power=$(echo "$power" | tr -d ' ')
            
            local mem_percent=$((mem_used * 100 / mem_total))
            
            HEALTH_REPORT+="  └─ GPU $index: $name\n"
            HEALTH_REPORT+="      Temperature: ${temp}°C, Utilization: ${utilization}%, Memory: ${mem_used}MB/${mem_total}MB (${mem_percent}%), Power: ${power}W\n"
            
            # Check for issues
            if [[ $temp -gt 80 ]]; then
                log_maintenance "WARNING" "GPU $index temperature high: ${temp}°C"
                ((HEALTH_WARNINGS++))
            fi
            
            if [[ $mem_percent -gt 90 ]]; then
                log_maintenance "WARNING" "GPU $index memory usage high: ${mem_percent}%"
                ((HEALTH_WARNINGS++))
            fi
        done
    else
        check_result "$service" "unhealthy" "No GPUs detected"
        ((HEALTH_ISSUES++))
        return 1
    fi
    
    return 0
}

# Check GPU in container
check_gpu_in_container() {
    local gpu_info=$(docker exec gpu-monitor nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null)
    
    if [[ -n "$gpu_info" ]]; then
        check_result "GPU Resources" "healthy" "GPU available in container"
        
        echo "$gpu_info" | while IFS=',' read -r name mem_used mem_total utilization; do
            name=$(echo "$name" | tr -d ' ')
            mem_used=$(echo "$mem_used" | tr -d ' ')
            mem_total=$(echo "$mem_total" | tr -d ' ')
            utilization=$(echo "$utilization" | tr -d ' ')
            
            HEALTH_REPORT+="  └─ GPU: $name, Memory: ${mem_used}/${mem_total}, Utilization: ${utilization}%\n"
        done
        
        return 0
    else
        check_result "GPU Resources" "unhealthy" "GPU not accessible in container"
        ((HEALTH_ISSUES++))
        return 1
    fi
}

# =============================================================================
# SYSTEM HEALTH CHECKS
# =============================================================================

# Check system resources
check_system() {
    local service="System Resources"
    increment_counter "processed"
    
    log_maintenance "INFO" "Checking system resources..."
    
    # CPU Usage
    local cpu_usage=$(get_system_resources "cpu")
    local cpu_status="healthy"
    if [[ ${cpu_usage%.*} -gt 80 ]]; then
        cpu_status="warning"
        ((HEALTH_WARNINGS++))
    elif [[ ${cpu_usage%.*} -gt 95 ]]; then
        cpu_status="critical"
        ((HEALTH_ISSUES++))
    fi
    HEALTH_REPORT+="  └─ CPU Usage: ${cpu_usage}% ($cpu_status)\n"
    
    # Memory Usage
    local mem_usage=$(get_system_resources "memory")
    local mem_status="healthy"
    if [[ ${mem_usage%.*} -gt 80 ]]; then
        mem_status="warning"
        ((HEALTH_WARNINGS++))
    elif [[ ${mem_usage%.*} -gt 95 ]]; then
        mem_status="critical"
        ((HEALTH_ISSUES++))
    fi
    HEALTH_REPORT+="  └─ Memory Usage: ${mem_usage}% ($mem_status)\n"
    
    # Disk Usage
    local disk_usage=$(get_system_resources "disk")
    local disk_available=$(get_system_resources "disk_available")
    local disk_status="healthy"
    if [[ $disk_usage -gt 80 ]]; then
        disk_status="warning"
        ((HEALTH_WARNINGS++))
    elif [[ $disk_usage -gt 95 ]]; then
        disk_status="critical"
        ((HEALTH_ISSUES++))
    fi
    HEALTH_REPORT+="  └─ Disk Usage: ${disk_usage}% (${disk_available}GB free) ($disk_status)\n"
    
    # Load Average
    local load_avg=$(get_system_resources "load")
    HEALTH_REPORT+="  └─ Load Average: $load_avg\n"
    
    # Docker Status
    if systemctl is-active --quiet docker; then
        local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        HEALTH_REPORT+="  └─ Docker: Running (v$docker_version)\n"
    else
        HEALTH_REPORT+="  └─ Docker: Not running\n"
        ((HEALTH_ISSUES++))
    fi
    
    # Network connectivity
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        HEALTH_REPORT+="  └─ Network: Connected\n"
    else
        HEALTH_REPORT+="  └─ Network: No internet connection\n"
        ((HEALTH_WARNINGS++))
    fi
    
    # Overall system status
    if [[ "$cpu_status" == "critical" ]] || [[ "$mem_status" == "critical" ]] || [[ "$disk_status" == "critical" ]]; then
        check_result "$service" "unhealthy" "Critical resource usage detected"
    elif [[ "$cpu_status" == "warning" ]] || [[ "$mem_status" == "warning" ]] || [[ "$disk_status" == "warning" ]]; then
        check_result "$service" "healthy" "Some resources showing high usage"
    else
        check_result "$service" "healthy" "All resources within normal limits"
    fi
    
    return 0
}

# =============================================================================
# COMPREHENSIVE HEALTH CHECK
# =============================================================================

# Run all health checks
run_all_health_checks() {
    log_maintenance "INFO" "Starting comprehensive health check..."
    
    # Reset global state
    OVERALL_HEALTH=true
    HEALTH_REPORT=""
    HEALTH_ISSUES=0
    HEALTH_WARNINGS=0
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    HEALTH_REPORT="Health Check Report - $timestamp\n"
    HEALTH_REPORT+="=====================================\n\n"
    
    # Service health checks
    HEALTH_REPORT+="SERVICE HEALTH CHECKS:\n"
    HEALTH_REPORT+="---------------------\n"
    
    check_postgres
    check_n8n
    check_ollama
    check_qdrant
    check_crawl4ai
    
    # GPU health check
    HEALTH_REPORT+="\nGPU HEALTH CHECK:\n"
    HEALTH_REPORT+="-----------------\n"
    check_gpu
    
    # System health check
    HEALTH_REPORT+="\nSYSTEM HEALTH CHECK:\n"
    HEALTH_REPORT+="-------------------\n"
    check_system
    
    # Summary
    HEALTH_REPORT+="\nHEALTH CHECK SUMMARY:\n"
    HEALTH_REPORT+="-------------------\n"
    HEALTH_REPORT+="Total Issues: $HEALTH_ISSUES\n"
    HEALTH_REPORT+="Total Warnings: $HEALTH_WARNINGS\n"
    
    if [[ $HEALTH_ISSUES -eq 0 ]] && [[ $HEALTH_WARNINGS -eq 0 ]]; then
        HEALTH_REPORT+="Overall Status: ✅ HEALTHY - All checks passed\n"
        log_maintenance "SUCCESS" "All health checks passed"
    elif [[ $HEALTH_ISSUES -eq 0 ]]; then
        HEALTH_REPORT+="Overall Status: ⚠️  WARNING - $HEALTH_WARNINGS warning(s) detected\n"
        log_maintenance "WARNING" "Health check completed with $HEALTH_WARNINGS warnings"
    else
        HEALTH_REPORT+="Overall Status: ❌ UNHEALTHY - $HEALTH_ISSUES issue(s) detected\n"
        log_maintenance "ERROR" "Health check failed with $HEALTH_ISSUES issues"
    fi
    
    # Save report to file if requested
    if [[ -n "${HEALTH_REPORT_FILE:-}" ]]; then
        echo -e "$HEALTH_REPORT" > "$HEALTH_REPORT_FILE"
        log_maintenance "INFO" "Health report saved to: $HEALTH_REPORT_FILE"
    else
        # Display report
        echo -e "\n$HEALTH_REPORT"
    fi
    
    # Return based on health status
    [[ $HEALTH_ISSUES -eq 0 ]]
}

# Export health check functions
export -f check_postgres
export -f check_n8n
export -f check_ollama
export -f check_qdrant
export -f check_crawl4ai
export -f check_gpu
export -f check_gpu_in_container
export -f check_system
export -f run_all_health_checks