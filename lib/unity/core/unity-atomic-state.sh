#!/bin/bash
# Unity Atomic State Management
# Provides atomic write operations for state files with validation and recovery
# =============================================================================

# Configuration
UNITY_ATOMIC_STATE_DIR="${UNITY_STATE_DIR:-/tmp/unity/state}"
UNITY_ATOMIC_BACKUP_DIR="${UNITY_ATOMIC_STATE_DIR}/backups"
UNITY_ATOMIC_TEMP_DIR="${UNITY_ATOMIC_STATE_DIR}/temp"
UNITY_ATOMIC_LOCK_DIR="${UNITY_ATOMIC_STATE_DIR}/locks"
UNITY_ATOMIC_CHECKSUM_DIR="${UNITY_ATOMIC_STATE_DIR}/checksums"
UNITY_ATOMIC_TRANSACTION_LOG="${UNITY_ATOMIC_STATE_DIR}/transactions.log"

# Settings
UNITY_ATOMIC_MAX_BACKUPS="${UNITY_ATOMIC_MAX_BACKUPS:-10}"
UNITY_ATOMIC_LOCK_TIMEOUT="${UNITY_ATOMIC_LOCK_TIMEOUT:-30}"
UNITY_ATOMIC_VALIDATION_ENABLED="${UNITY_ATOMIC_VALIDATION_ENABLED:-true}"

# Initialize atomic state management
unity_atomic_init() {
    # Create required directories
    for dir in "$UNITY_ATOMIC_STATE_DIR" "$UNITY_ATOMIC_BACKUP_DIR" "$UNITY_ATOMIC_TEMP_DIR" "$UNITY_ATOMIC_LOCK_DIR" "$UNITY_ATOMIC_CHECKSUM_DIR"; do
        mkdir -p "$dir" || {
            echo "[ERROR] Failed to create directory: $dir" >&2
            return 1
        }
    done
    
    # Initialize transaction log
    if [[ ! -f "$UNITY_ATOMIC_TRANSACTION_LOG" ]]; then
        echo "# Unity Atomic State Transaction Log" > "$UNITY_ATOMIC_TRANSACTION_LOG"
        echo "# Format: TIMESTAMP|OPERATION|FILE|STATUS|DETAILS" >> "$UNITY_ATOMIC_TRANSACTION_LOG"
    fi
    
    # Clean up stale locks on initialization
    unity_atomic_cleanup_locks
    
    return 0
}

# Atomic write with validation and backup
unity_atomic_write() {
    local file_path="$1"
    local content="$2"
    local file_type="${3:-text}"  # text, json, yaml
    local create_backup="${4:-true}"
    
    # Ensure initialization
    [[ -d "$UNITY_ATOMIC_STATE_DIR" ]] || unity_atomic_init
    
    local file_name=$(basename "$file_path")
    local temp_file="$UNITY_ATOMIC_TEMP_DIR/${file_name}.tmp.$$"
    local lock_file="$UNITY_ATOMIC_LOCK_DIR/${file_name}.lock"
    local checksum_file="$UNITY_ATOMIC_CHECKSUM_DIR/${file_name}.sha256"
    
    # Acquire lock
    if ! unity_atomic_acquire_lock "$lock_file"; then
        unity_atomic_log_transaction "WRITE_FAILED" "$file_path" "LOCK_TIMEOUT" ""
        return 1
    fi
    
    # Trap to ensure lock is released
    trap "unity_atomic_release_lock '$lock_file'" EXIT
    
    # Write to temporary file
    echo "$content" > "$temp_file" || {
        unity_atomic_log_transaction "WRITE_FAILED" "$file_path" "TEMP_WRITE_FAILED" ""
        unity_atomic_release_lock "$lock_file"
        return 1
    }
    
    # Validate content if enabled
    if [[ "$UNITY_ATOMIC_VALIDATION_ENABLED" == "true" ]]; then
        if ! unity_atomic_validate_content "$temp_file" "$file_type"; then
            unity_atomic_log_transaction "WRITE_FAILED" "$file_path" "VALIDATION_FAILED" "$file_type"
            rm -f "$temp_file"
            unity_atomic_release_lock "$lock_file"
            return 1
        fi
    fi
    
    # Create backup if requested and file exists
    if [[ "$create_backup" == "true" ]] && [[ -f "$file_path" ]]; then
        if ! unity_atomic_create_backup "$file_path"; then
            unity_atomic_log_transaction "WRITE_WARNING" "$file_path" "BACKUP_FAILED" ""
            # Continue anyway - backup failure shouldn't stop the write
        fi
    fi
    
    # Calculate checksum of new content
    local new_checksum=$(sha256sum "$temp_file" | cut -d' ' -f1)
    
    # Ensure target directory exists
    local target_dir=$(dirname "$file_path")
    mkdir -p "$target_dir" 2>/dev/null || true
    
    # Atomic rename (atomic on same filesystem)
    if mv -f "$temp_file" "$file_path" 2>/dev/null; then
        # Update checksum
        echo "$new_checksum" > "$checksum_file"
        
        unity_atomic_log_transaction "WRITE_SUCCESS" "$file_path" "COMPLETED" "checksum:$new_checksum"
        unity_atomic_release_lock "$lock_file"
        
        # Emit event if function exists
        if type -t unity_emit_event >/dev/null 2>&1; then
            unity_emit_event "ATOMIC_STATE_WRITTEN" "atomic" "file:$file_name,checksum:$new_checksum"
        fi
        
        return 0
    else
        unity_atomic_log_transaction "WRITE_FAILED" "$file_path" "RENAME_FAILED" ""
        rm -f "$temp_file"
        unity_atomic_release_lock "$lock_file"
        return 1
    fi
}

# Atomic read with validation
unity_atomic_read() {
    local file_path="$1"
    local validate="${2:-true}"
    
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    
    local file_name=$(basename "$file_path")
    local checksum_file="$UNITY_ATOMIC_CHECKSUM_DIR/${file_name}.sha256"
    
    # Validate checksum if requested
    if [[ "$validate" == "true" ]] && [[ -f "$checksum_file" ]]; then
        local expected_checksum=$(cat "$checksum_file" 2>/dev/null)
        local actual_checksum=$(sha256sum "$file_path" 2>/dev/null | cut -d' ' -f1)
        
        if [[ "$expected_checksum" != "$actual_checksum" ]]; then
            unity_atomic_log_transaction "READ_FAILED" "$file_path" "CHECKSUM_MISMATCH" "expected:$expected_checksum,actual:$actual_checksum"
            
            # Attempt recovery from backup
            if unity_atomic_recover_from_backup "$file_path"; then
                # Retry read after recovery
                cat "$file_path" 2>/dev/null
                return $?
            else
                return 1
            fi
        fi
    fi
    
    cat "$file_path" 2>/dev/null
}

# Validate content based on type
unity_atomic_validate_content() {
    local file="$1"
    local file_type="$2"
    
    case "$file_type" in
        json)
            # Validate JSON using python if available
            if command -v python3 >/dev/null 2>&1; then
                python3 -m json.tool "$file" >/dev/null 2>&1
            elif command -v python >/dev/null 2>&1; then
                python -m json.tool "$file" >/dev/null 2>&1
            elif command -v jq >/dev/null 2>&1; then
                jq . "$file" >/dev/null 2>&1
            else
                # Basic JSON validation - check for balanced braces
                local content=$(cat "$file")
                local open_braces=$(echo "$content" | grep -o '{' | wc -l)
                local close_braces=$(echo "$content" | grep -o '}' | wc -l)
                [[ $open_braces -eq $close_braces ]]
            fi
            ;;
        yaml)
            # Validate YAML using python if available
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "import yaml; yaml.safe_load(open('$file'))" >/dev/null 2>&1
            elif command -v yq >/dev/null 2>&1; then
                yq e . "$file" >/dev/null 2>&1
            else
                # Basic YAML validation - check for proper indentation
                ! grep -E '^\t' "$file" >/dev/null 2>&1
            fi
            ;;
        text|*)
            # Text files are always valid
            return 0
            ;;
    esac
}

# Create backup with rotation
unity_atomic_create_backup() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local timestamp=$(date +%Y%m%d_%H%M%S_%N)
    local backup_file="$UNITY_ATOMIC_BACKUP_DIR/${file_name}.${timestamp}.bak"
    
    # Copy to backup
    if cp -p "$file_path" "$backup_file" 2>/dev/null; then
        # Copy checksum too
        local checksum_file="$UNITY_ATOMIC_CHECKSUM_DIR/${file_name}.sha256"
        if [[ -f "$checksum_file" ]]; then
            cp -p "$checksum_file" "${backup_file}.sha256" 2>/dev/null || true
        fi
        
        # Rotate old backups
        unity_atomic_rotate_backups "$file_name"
        
        unity_atomic_log_transaction "BACKUP_CREATED" "$file_path" "SUCCESS" "backup:$backup_file"
        return 0
    else
        return 1
    fi
}

# Rotate old backups
unity_atomic_rotate_backups() {
    local file_name="$1"
    
    # Get list of backups sorted by age (oldest first)
    local backups=($(ls -t "$UNITY_ATOMIC_BACKUP_DIR/${file_name}".*.bak 2>/dev/null | tail -n +$((UNITY_ATOMIC_MAX_BACKUPS + 1))))
    
    # Remove old backups
    for backup in "${backups[@]}"; do
        rm -f "$backup" "${backup}.sha256" 2>/dev/null
        unity_atomic_log_transaction "BACKUP_ROTATED" "$backup" "REMOVED" "max_backups:$UNITY_ATOMIC_MAX_BACKUPS"
    done
}

# Recover from backup
unity_atomic_recover_from_backup() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    
    # Find most recent backup
    local latest_backup=$(ls -t "$UNITY_ATOMIC_BACKUP_DIR/${file_name}".*.bak 2>/dev/null | head -n1)
    
    if [[ -n "$latest_backup" ]] && [[ -f "$latest_backup" ]]; then
        # Restore from backup
        if cp -p "$latest_backup" "$file_path" 2>/dev/null; then
            # Restore checksum too
            local backup_checksum="${latest_backup}.sha256"
            local checksum_file="$UNITY_ATOMIC_CHECKSUM_DIR/${file_name}.sha256"
            if [[ -f "$backup_checksum" ]]; then
                cp -p "$backup_checksum" "$checksum_file" 2>/dev/null || true
            fi
            
            unity_atomic_log_transaction "RECOVERY_SUCCESS" "$file_path" "RESTORED" "from:$latest_backup"
            
            # Emit recovery event
            if type -t unity_emit_event >/dev/null 2>&1; then
                unity_emit_event "ATOMIC_STATE_RECOVERED" "atomic" "file:$file_name,backup:$(basename "$latest_backup")"
            fi
            
            return 0
        fi
    fi
    
    unity_atomic_log_transaction "RECOVERY_FAILED" "$file_path" "NO_BACKUP" ""
    return 1
}

# Acquire lock with timeout
unity_atomic_acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-$UNITY_ATOMIC_LOCK_TIMEOUT}"
    local wait_time=0
    
    while [[ $wait_time -lt $timeout ]]; do
        # Try to create lock file atomically
        if (set -C; echo "$$|$(date +%s)" > "$lock_file") 2>/dev/null; then
            return 0
        fi
        
        # Check if lock is stale
        if [[ -f "$lock_file" ]]; then
            local lock_info=$(cat "$lock_file" 2>/dev/null)
            local lock_pid=$(echo "$lock_info" | cut -d'|' -f1)
            local lock_time=$(echo "$lock_info" | cut -d'|' -f2)
            
            # Check if process is still alive
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Process is dead, remove stale lock
                rm -f "$lock_file"
                unity_atomic_log_transaction "LOCK_CLEANED" "$lock_file" "STALE" "dead_pid:$lock_pid"
                continue
            fi
            
            # Check if lock is too old (10 minutes)
            if [[ -n "$lock_time" ]]; then
                local current_time=$(date +%s)
                local lock_age=$((current_time - lock_time))
                if [[ $lock_age -gt 600 ]]; then
                    rm -f "$lock_file"
                    unity_atomic_log_transaction "LOCK_CLEANED" "$lock_file" "TIMEOUT" "age:${lock_age}s"
                    continue
                fi
            fi
        fi
        
        sleep 0.1
        wait_time=$((wait_time + 1))
    done
    
    return 1
}

# Release lock
unity_atomic_release_lock() {
    local lock_file="$1"
    
    # Verify we own the lock
    if [[ -f "$lock_file" ]]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null | cut -d'|' -f1)
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$lock_file"
        fi
    fi
}

# Clean up stale locks
unity_atomic_cleanup_locks() {
    local cleaned=0
    
    for lock_file in "$UNITY_ATOMIC_LOCK_DIR"/*.lock; do
        [[ -f "$lock_file" ]] || continue
        
        local lock_info=$(cat "$lock_file" 2>/dev/null)
        local lock_pid=$(echo "$lock_info" | cut -d'|' -f1)
        
        # Check if process is dead
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$lock_file"
            cleaned=$((cleaned + 1))
        fi
    done
    
    if [[ $cleaned -gt 0 ]]; then
        unity_atomic_log_transaction "CLEANUP" "locks" "SUCCESS" "cleaned:$cleaned"
    fi
}

# Log transaction
unity_atomic_log_transaction() {
    local operation="$1"
    local file="$2"
    local status="$3"
    local details="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "${timestamp}|${operation}|${file}|${status}|${details}" >> "$UNITY_ATOMIC_TRANSACTION_LOG"
}

# Batch atomic write for multiple files
unity_atomic_batch_write() {
    local -n files=$1  # Array of file paths
    local -n contents=$2  # Array of contents
    local file_type="${3:-text}"
    local transaction_id="batch_$(date +%s%N)"
    
    unity_atomic_log_transaction "BATCH_START" "$transaction_id" "STARTED" "count:${#files[@]}"
    
    # Validate arrays have same length
    if [[ ${#files[@]} -ne ${#contents[@]} ]]; then
        unity_atomic_log_transaction "BATCH_FAILED" "$transaction_id" "INVALID_INPUT" "files:${#files[@]},contents:${#contents[@]}"
        return 1
    fi
    
    # Write all files atomically
    local success=true
    local written_files=()
    
    for i in "${!files[@]}"; do
        if unity_atomic_write "${files[$i]}" "${contents[$i]}" "$file_type" "true"; then
            written_files+=("${files[$i]}")
        else
            success=false
            break
        fi
    done
    
    if [[ "$success" == "true" ]]; then
        unity_atomic_log_transaction "BATCH_SUCCESS" "$transaction_id" "COMPLETED" "count:${#written_files[@]}"
        return 0
    else
        # Rollback on failure
        unity_atomic_log_transaction "BATCH_ROLLBACK" "$transaction_id" "STARTED" "written:${#written_files[@]}"
        
        for file in "${written_files[@]}"; do
            if unity_atomic_recover_from_backup "$file"; then
                unity_atomic_log_transaction "BATCH_ROLLBACK" "$file" "SUCCESS" ""
            else
                unity_atomic_log_transaction "BATCH_ROLLBACK" "$file" "FAILED" ""
            fi
        done
        
        return 1
    fi
}

# Get transaction history
unity_atomic_get_transactions() {
    local file_filter="${1:-}"
    local operation_filter="${2:-}"
    local limit="${3:-100}"
    
    if [[ -n "$file_filter" ]] && [[ -n "$operation_filter" ]]; then
        tail -n "$limit" "$UNITY_ATOMIC_TRANSACTION_LOG" | grep "|$operation_filter|" | grep "|$file_filter|"
    elif [[ -n "$file_filter" ]]; then
        tail -n "$limit" "$UNITY_ATOMIC_TRANSACTION_LOG" | grep "|$file_filter|"
    elif [[ -n "$operation_filter" ]]; then
        tail -n "$limit" "$UNITY_ATOMIC_TRANSACTION_LOG" | grep "|$operation_filter|"
    else
        tail -n "$limit" "$UNITY_ATOMIC_TRANSACTION_LOG"
    fi
}

# Export functions
export -f unity_atomic_init
export -f unity_atomic_write
export -f unity_atomic_read
export -f unity_atomic_validate_content
export -f unity_atomic_create_backup
export -f unity_atomic_rotate_backups
export -f unity_atomic_recover_from_backup
export -f unity_atomic_acquire_lock
export -f unity_atomic_release_lock
export -f unity_atomic_cleanup_locks
export -f unity_atomic_log_transaction
export -f unity_atomic_batch_write
export -f unity_atomic_get_transactions

# Initialize on source
unity_atomic_init