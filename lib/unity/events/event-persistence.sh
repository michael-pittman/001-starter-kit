#!/bin/bash
# Unity Event System - Event Persistence and Storage
# Comprehensive event storage, audit trails, and replay functionality

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Persistence configuration
UNITY_EVENT_STORAGE_DIR=".unity/events/storage"
UNITY_EVENT_AUDIT_DIR=".unity/events/audit"
UNITY_EVENT_SNAPSHOTS_DIR=".unity/events/snapshots"
UNITY_EVENT_INDEXES_DIR=".unity/events/indexes"
UNITY_EVENT_ARCHIVE_DIR=".unity/events/archive"

# Storage settings
UNITY_EVENT_BATCH_WRITE_SIZE=50
UNITY_EVENT_INDEX_REBUILD_INTERVAL=3600  # 1 hour
UNITY_EVENT_ARCHIVE_AFTER_DAYS=30
UNITY_EVENT_COMPRESSION_ENABLED=true

# Storage format version
UNITY_EVENT_STORAGE_VERSION="2.0"

#############################################
# Initialization and Setup
#############################################

# Initialize event persistence system
init_event_persistence() {
    local verbose="${1:-false}"
    
    # Create all storage directories
    mkdir -p "$UNITY_EVENT_STORAGE_DIR" "$UNITY_EVENT_AUDIT_DIR" "$UNITY_EVENT_SNAPSHOTS_DIR"
    mkdir -p "$UNITY_EVENT_INDEXES_DIR" "$UNITY_EVENT_ARCHIVE_DIR"
    mkdir -p "$UNITY_EVENT_STORAGE_DIR/by-date" "$UNITY_EVENT_STORAGE_DIR/by-type" "$UNITY_EVENT_STORAGE_DIR/by-source"
    
    # Initialize storage metadata
    _init_storage_metadata
    
    # Create indexes
    _init_event_indexes
    
    # Set up automatic archiving
    _setup_automatic_archiving
    
    # Create storage health check
    _create_storage_health_check
    
    if [[ "$verbose" == "true" ]] && command -v unity_log >/dev/null 2>&1; then
        unity_log "SUCCESS" "Event persistence system initialized with indexes and archiving"
    fi
    
    return 0
}

# Initialize storage metadata
_init_storage_metadata() {
    cat > "$UNITY_EVENT_STORAGE_DIR/metadata.info" <<EOF
# Unity Event Storage Metadata
STORAGE_VERSION=$UNITY_EVENT_STORAGE_VERSION
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_SIZE=$UNITY_EVENT_BATCH_WRITE_SIZE
COMPRESSION_ENABLED=$UNITY_EVENT_COMPRESSION_ENABLED
ARCHIVE_AFTER_DAYS=$UNITY_EVENT_ARCHIVE_AFTER_DAYS
LAST_INDEX_REBUILD=0
TOTAL_EVENTS_STORED=0
EOF
}

# Initialize event indexes
_init_event_indexes() {
    # Create index files
    touch "$UNITY_EVENT_INDEXES_DIR/by-type.idx"
    touch "$UNITY_EVENT_INDEXES_DIR/by-source.idx"
    touch "$UNITY_EVENT_INDEXES_DIR/by-date.idx"
    touch "$UNITY_EVENT_INDEXES_DIR/by-correlation.idx"
    
    # Create index metadata
    cat > "$UNITY_EVENT_INDEXES_DIR/index.meta" <<EOF
# Event Index Metadata
LAST_REBUILD=$(date +%s)
INDEX_VERSION=2.0
INDEXES_ENABLED=true
EOF
}

# Set up automatic archiving
_setup_automatic_archiving() {
    cat > "$UNITY_EVENT_STORAGE_DIR/archive.sh" <<'ARCHIVE_EOF'
#!/bin/bash
# Automatic event archiving script

STORAGE_DIR=".unity/events/storage"
ARCHIVE_DIR=".unity/events/archive"
ARCHIVE_AFTER_DAYS=30

# Archive old events
find "$STORAGE_DIR/by-date" -name "*.events" -mtime +$ARCHIVE_AFTER_DAYS | while read -r event_file; do
    if [[ -f "$event_file" ]]; then
        # Compress and move to archive
        gzip "$event_file"
        mv "${event_file}.gz" "$ARCHIVE_DIR/"
        
        # Update metadata
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Archived $event_file" >> "$ARCHIVE_DIR/archive.log"
    fi
done

# Clean up old indexes for archived files
find "$UNITY_EVENT_INDEXES_DIR" -name "*.idx.old" -mtime +7 -delete
ARCHIVE_EOF
    chmod +x "$UNITY_EVENT_STORAGE_DIR/archive.sh"
}

# Create storage health check
_create_storage_health_check() {
    cat > "$UNITY_EVENT_STORAGE_DIR/health-check.sh" <<'HEALTH_EOF'
#!/bin/bash
# Event storage health check

STORAGE_DIR=".unity/events/storage"
HEALTH_LOG="$STORAGE_DIR/health.log"

# Check disk space
DISK_USAGE=$(df "$STORAGE_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 90 ]]; then
    echo "$(date): WARNING: Disk usage at ${DISK_USAGE}%" >> "$HEALTH_LOG"
fi

# Check file integrity
CORRUPT_FILES=0
find "$STORAGE_DIR" -name "*.events" | while read -r file; do
    if ! grep -q "^{" "$file" 2>/dev/null; then
        echo "$(date): ERROR: Corrupt file detected: $file" >> "$HEALTH_LOG"
        CORRUPT_FILES=$((CORRUPT_FILES + 1))
    fi
done

# Check index consistency
if [[ -f "$STORAGE_DIR/../indexes/by-type.idx" ]]; then
    INDEX_ENTRIES=$(wc -l < "$STORAGE_DIR/../indexes/by-type.idx")
    echo "$(date): Index entries: $INDEX_ENTRIES" >> "$HEALTH_LOG"
fi

echo "$(date): Health check completed" >> "$HEALTH_LOG"
HEALTH_EOF
    chmod +x "$UNITY_EVENT_STORAGE_DIR/health-check.sh"
}

#############################################
# Event Storage Functions
#############################################

# Store event with comprehensive indexing
store_event() {
    local event_id="$1"
    local event_payload="$2"
    local storage_options="${3:-}"
    
    # Extract event metadata
    local event_type
    local event_source
    local timestamp
    local correlation_id
    
    event_type=$(echo "$event_payload" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    event_source=$(echo "$event_payload" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
    timestamp=$(echo "$event_payload" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
    correlation_id=$(echo "$event_payload" | grep -o '"correlation_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    
    local date_path
    date_path=$(date -d "@$timestamp" '+%Y/%m/%d' 2>/dev/null || date -r "$timestamp" '+%Y/%m/%d' 2>/dev/null || date '+%Y/%m/%d')
    
    # Create storage paths
    local date_dir="$UNITY_EVENT_STORAGE_DIR/by-date/$date_path"
    local type_dir="$UNITY_EVENT_STORAGE_DIR/by-type/$event_type"
    local source_dir="$UNITY_EVENT_STORAGE_DIR/by-source/$event_source"
    
    mkdir -p "$date_dir" "$type_dir" "$source_dir"
    
    # Store in primary location (by date)
    local primary_file="$date_dir/$(date -d "@$timestamp" '+%H' 2>/dev/null || date -r "$timestamp" '+%H' 2>/dev/null || date '+%H').events"
    echo "$event_payload" >> "$primary_file"
    
    # Create symbolic links for other indexes
    local link_name="${event_id}.event"
    ln -sf "../../../by-date/$date_path/$(basename "$primary_file")" "$type_dir/$link_name" 2>/dev/null || true
    ln -sf "../../../by-date/$date_path/$(basename "$primary_file")" "$source_dir/$link_name" 2>/dev/null || true
    
    # Update indexes
    _update_event_indexes "$event_id" "$event_type" "$event_source" "$timestamp" "$correlation_id"
    
    # Update storage statistics
    _update_storage_stats "$event_type" "$event_source"
    
    # Check if batch processing is needed
    _check_batch_processing "$primary_file"
    
    return 0
}

# Update event indexes
_update_event_indexes() {
    local event_id="$1"
    local event_type="$2"
    local event_source="$3"
    local timestamp="$4"
    local correlation_id="$5"
    
    local date_str
    date_str=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
    
    # Update type index
    echo "$timestamp|$event_id|$event_type|$event_source" >> "$UNITY_EVENT_INDEXES_DIR/by-type.idx"
    
    # Update source index
    echo "$timestamp|$event_id|$event_source|$event_type" >> "$UNITY_EVENT_INDEXES_DIR/by-source.idx"
    
    # Update date index
    echo "$timestamp|$event_id|$date_str|$event_type" >> "$UNITY_EVENT_INDEXES_DIR/by-date.idx"
    
    # Update correlation index if correlation_id exists
    if [[ -n "$correlation_id" ]]; then
        echo "$timestamp|$event_id|$correlation_id|$event_type" >> "$UNITY_EVENT_INDEXES_DIR/by-correlation.idx"
    fi
}

# Update storage statistics
_update_storage_stats() {
    local event_type="$1"
    local event_source="$2"
    
    # Update metadata counters
    local metadata_file="$UNITY_EVENT_STORAGE_DIR/metadata.info"
    local current_count
    current_count=$(grep "^TOTAL_EVENTS_STORED=" "$metadata_file" | cut -d'=' -f2)
    current_count=$((current_count + 1))
    
    sed -i.bak "s/^TOTAL_EVENTS_STORED=.*/TOTAL_EVENTS_STORED=$current_count/" "$metadata_file"
    rm -f "${metadata_file}.bak"
    
    # Update type statistics
    local stats_file="$UNITY_EVENT_STORAGE_DIR/stats.txt"
    echo "$(date +%s)|$event_type|$event_source" >> "$stats_file"
}

# Check if batch processing is needed
_check_batch_processing() {
    local file="$1"
    local line_count
    line_count=$(wc -l < "$file" 2>/dev/null || echo "0")
    
    if [[ $line_count -ge $UNITY_EVENT_BATCH_WRITE_SIZE ]]; then
        _process_batch_file "$file"
    fi
}

# Process batch file (compression, optimization)
_process_batch_file() {
    local file="$1"
    
    if [[ "$UNITY_EVENT_COMPRESSION_ENABLED" == "true" ]]; then
        # Compress large files
        gzip "$file"
        mv "${file}.gz" "${file%.events}.batch.gz"
        
        # Create new file for continued writing
        touch "$file"
    fi
}

#############################################
# Event Retrieval Functions
#############################################

# Query events with various filters
query_events() {
    local query_type="$1"
    local filter_value="$2"
    local start_time="${3:-0}"
    local end_time="${4:-$(date +%s)}"
    local limit="${5:-100}"
    local format="${6:-json}"
    
    case "$query_type" in
        "by-type")
            _query_events_by_type "$filter_value" "$start_time" "$end_time" "$limit" "$format"
            ;;
        "by-source")
            _query_events_by_source "$filter_value" "$start_time" "$end_time" "$limit" "$format"
            ;;
        "by-date")
            _query_events_by_date "$filter_value" "$start_time" "$end_time" "$limit" "$format"
            ;;
        "by-correlation")
            _query_events_by_correlation "$filter_value" "$start_time" "$end_time" "$limit" "$format"
            ;;
        "all")
            _query_all_events "$start_time" "$end_time" "$limit" "$format"
            ;;
        *)
            _log_persistence_error "Unknown query type: $query_type"
            return 1
            ;;
    esac
}

# Query events by type
_query_events_by_type() {
    local event_type="$1"
    local start_time="$2"
    local end_time="$3"
    local limit="$4"
    local format="$5"
    
    # Use index for efficient lookup
    awk -F'|' -v type="$event_type" -v start="$start_time" -v end="$end_time" -v limit="$limit" '
        $1 >= start && $1 <= end && $3 == type {
            print $2; 
            if (NR >= limit) exit
        }' "$UNITY_EVENT_INDEXES_DIR/by-type.idx" | head -n "$limit" | while read -r event_id; do
        _retrieve_event_by_id "$event_id" "$format"
    done
}

# Query events by source
_query_events_by_source() {
    local event_source="$1"
    local start_time="$2"
    local end_time="$3"
    local limit="$4"
    local format="$5"
    
    awk -F'|' -v source="$event_source" -v start="$start_time" -v end="$end_time" -v limit="$limit" '
        $1 >= start && $1 <= end && $3 == source {
            print $2; 
            if (NR >= limit) exit
        }' "$UNITY_EVENT_INDEXES_DIR/by-source.idx" | head -n "$limit" | while read -r event_id; do
        _retrieve_event_by_id "$event_id" "$format"
    done
}

# Query events by date range
_query_events_by_date() {
    local date_filter="$1"
    local start_time="$2"
    local end_time="$3"
    local limit="$4"
    local format="$5"
    
    awk -F'|' -v start="$start_time" -v end="$end_time" -v limit="$limit" '
        $1 >= start && $1 <= end {
            print $2; 
            if (NR >= limit) exit
        }' "$UNITY_EVENT_INDEXES_DIR/by-date.idx" | head -n "$limit" | while read -r event_id; do
        _retrieve_event_by_id "$event_id" "$format"
    done
}

# Query events by correlation ID
_query_events_by_correlation() {
    local correlation_id="$1"
    local start_time="$2"
    local end_time="$3"
    local limit="$4"
    local format="$5"
    
    if [[ ! -f "$UNITY_EVENT_INDEXES_DIR/by-correlation.idx" ]]; then
        return 0
    fi
    
    awk -F'|' -v corr="$correlation_id" -v start="$start_time" -v end="$end_time" -v limit="$limit" '
        $1 >= start && $1 <= end && $3 == corr {
            print $2; 
            if (NR >= limit) exit
        }' "$UNITY_EVENT_INDEXES_DIR/by-correlation.idx" | head -n "$limit" | while read -r event_id; do
        _retrieve_event_by_id "$event_id" "$format"
    done
}

# Query all events in time range
_query_all_events() {
    local start_time="$1"
    local end_time="$2"
    local limit="$3"
    local format="$4"
    
    awk -F'|' -v start="$start_time" -v end="$end_time" -v limit="$limit" '
        $1 >= start && $1 <= end {
            print $2; 
            if (NR >= limit) exit
        }' "$UNITY_EVENT_INDEXES_DIR/by-date.idx" | sort -n | head -n "$limit" | while read -r event_id; do
        _retrieve_event_by_id "$event_id" "$format"
    done
}

# Retrieve specific event by ID
_retrieve_event_by_id() {
    local event_id="$1"
    local format="${2:-json}"
    
    # Search in storage files
    local event_data
    event_data=$(find "$UNITY_EVENT_STORAGE_DIR/by-date" -name "*.events" -exec grep -l "\"id\": \"$event_id\"" {} \; | head -1 | xargs grep "\"id\": \"$event_id\"" 2>/dev/null || true)
    
    if [[ -z "$event_data" ]]; then
        # Check compressed files
        event_data=$(find "$UNITY_EVENT_STORAGE_DIR/by-date" -name "*.batch.gz" -exec zgrep -l "\"id\": \"$event_id\"" {} \; | head -1 | xargs zgrep "\"id\": \"$event_id\"" 2>/dev/null || true)
    fi
    
    if [[ -n "$event_data" ]]; then
        case "$format" in
            "json")
                echo "$event_data"
                ;;
            "csv")
                _convert_event_to_csv "$event_data"
                ;;
            "summary")
                _convert_event_to_summary "$event_data"
                ;;
        esac
    fi
}

# Convert event to CSV format
_convert_event_to_csv() {
    local event_data="$1"
    
    local event_id event_type event_source timestamp
    event_id=$(echo "$event_data" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)
    event_type=$(echo "$event_data" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    event_source=$(echo "$event_data" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
    timestamp=$(echo "$event_data" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
    
    echo "$event_id,$event_type,$event_source,$timestamp"
}

# Convert event to summary format
_convert_event_to_summary() {
    local event_data="$1"
    
    local event_id event_type event_source timestamp
    event_id=$(echo "$event_data" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)
    event_type=$(echo "$event_data" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    event_source=$(echo "$event_data" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
    timestamp=$(echo "$event_data" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
    
    local date_str
    date_str=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
    
    echo "$date_str | $event_type | $event_source | $event_id"
}

#############################################
# Event Replay Functions
#############################################

# Create event snapshot for replay
create_event_snapshot() {
    local snapshot_name="$1"
    local start_time="${2:-0}"
    local end_time="${3:-$(date +%s)}"
    local event_filter="${4:-.*}"
    
    local snapshot_dir="$UNITY_EVENT_SNAPSHOTS_DIR/$snapshot_name"
    mkdir -p "$snapshot_dir"
    
    # Create snapshot metadata
    cat > "$snapshot_dir/metadata.json" <<EOF
{
  "snapshot_name": "$snapshot_name",
  "created_at": $(date +%s),
  "start_time": $start_time,
  "end_time": $end_time,
  "event_filter": "$event_filter",
  "version": "$UNITY_EVENT_STORAGE_VERSION"
}
EOF
    
    # Extract events matching criteria
    query_events "all" "" "$start_time" "$end_time" "10000" "json" | grep -E "$event_filter" > "$snapshot_dir/events.jsonl"
    
    local event_count
    event_count=$(wc -l < "$snapshot_dir/events.jsonl" 2>/dev/null || echo "0")
    
    # Update metadata with event count
    echo "  \"event_count\": $event_count" >> "$snapshot_dir/metadata.json"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "INFO" "Created snapshot '$snapshot_name' with $event_count events"
    fi
    
    echo "$snapshot_name"
}

# Replay events from snapshot
replay_from_snapshot() {
    local snapshot_name="$1"
    local target_event_bus="${2:-unity_emit_event}"
    local delay_between_events="${3:-0}"
    local dry_run="${4:-true}"
    
    local snapshot_dir="$UNITY_EVENT_SNAPSHOTS_DIR/$snapshot_name"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        _log_persistence_error "Snapshot not found: $snapshot_name"
        return 1
    fi
    
    local events_file="$snapshot_dir/events.jsonl"
    if [[ ! -f "$events_file" ]]; then
        _log_persistence_error "Events file not found in snapshot: $snapshot_name"
        return 1
    fi
    
    local replayed_count=0
    
    while IFS= read -r event_line; do
        if [[ -n "$event_line" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                echo "[DRY RUN] Would replay: $(echo "$event_line" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)"
            else
                # Extract event components for replay
                local event_type event_source event_data
                event_type=$(echo "$event_line" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
                event_source=$(echo "$event_line" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
                event_data=$(echo "$event_line" | grep -o '"data": {[^}]*}' | cut -d':' -f2-)
                
                # Replay event
                if command -v "$target_event_bus" >/dev/null 2>&1; then
                    "$target_event_bus" "$event_type" "$event_source" "$event_data" "medium" "false"
                fi
            fi
            
            replayed_count=$((replayed_count + 1))
            
            # Add delay if specified
            if [[ "$delay_between_events" -gt 0 ]]; then
                sleep "$delay_between_events"
            fi
        fi
    done < "$events_file"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "INFO" "Replayed $replayed_count events from snapshot '$snapshot_name' (dry_run=$dry_run)"
    fi
    
    return 0
}

# List available snapshots
list_snapshots() {
    local format="${1:-summary}"
    
    if [[ ! -d "$UNITY_EVENT_SNAPSHOTS_DIR" ]]; then
        echo "No snapshots directory found"
        return 0
    fi
    
    for snapshot_dir in "$UNITY_EVENT_SNAPSHOTS_DIR"/*; do
        if [[ -d "$snapshot_dir" ]]; then
            local snapshot_name
            snapshot_name=$(basename "$snapshot_dir")
            
            if [[ "$format" == "summary" ]]; then
                local metadata_file="$snapshot_dir/metadata.json"
                if [[ -f "$metadata_file" ]]; then
                    local created_at event_count
                    created_at=$(grep '"created_at":' "$metadata_file" | grep -o '[0-9]*')
                    event_count=$(grep '"event_count":' "$metadata_file" | grep -o '[0-9]*' || echo "0")
                    
                    local created_str
                    created_str=$(date -d "@$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                    
                    echo "$snapshot_name | $created_str | $event_count events"
                else
                    echo "$snapshot_name | No metadata | Unknown events"
                fi
            else
                echo "$snapshot_name"
            fi
        fi
    done
}

#############################################
# Maintenance Functions
#############################################

# Rebuild event indexes
rebuild_indexes() {
    local force="${1:-false}"
    
    # Check if rebuild is needed
    local last_rebuild
    last_rebuild=$(grep "^LAST_REBUILD=" "$UNITY_EVENT_INDEXES_DIR/index.meta" | cut -d'=' -f2 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    
    if [[ "$force" != "true" ]] && [[ $((current_time - last_rebuild)) -lt $UNITY_EVENT_INDEX_REBUILD_INTERVAL ]]; then
        return 0
    fi
    
    # Backup existing indexes
    for index_file in "$UNITY_EVENT_INDEXES_DIR"/*.idx; do
        if [[ -f "$index_file" ]]; then
            cp "$index_file" "${index_file}.old"
        fi
    done
    
    # Clear indexes
    > "$UNITY_EVENT_INDEXES_DIR/by-type.idx"
    > "$UNITY_EVENT_INDEXES_DIR/by-source.idx"
    > "$UNITY_EVENT_INDEXES_DIR/by-date.idx"
    > "$UNITY_EVENT_INDEXES_DIR/by-correlation.idx"
    
    # Rebuild from all stored events
    find "$UNITY_EVENT_STORAGE_DIR/by-date" -name "*.events" | while read -r events_file; do
        while IFS= read -r event_line; do
            if [[ -n "$event_line" ]]; then
                local event_id event_type event_source timestamp correlation_id
                
                event_id=$(echo "$event_line" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)
                event_type=$(echo "$event_line" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
                event_source=$(echo "$event_line" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
                timestamp=$(echo "$event_line" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
                correlation_id=$(echo "$event_line" | grep -o '"correlation_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
                
                _update_event_indexes "$event_id" "$event_type" "$event_source" "$timestamp" "$correlation_id"
            fi
        done < "$events_file"
    done
    
    # Update metadata
    sed -i.bak "s/^LAST_REBUILD=.*/LAST_REBUILD=$current_time/" "$UNITY_EVENT_INDEXES_DIR/index.meta"
    rm -f "$UNITY_EVENT_INDEXES_DIR/index.meta.bak"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "INFO" "Event indexes rebuilt successfully"
    fi
}

# Archive old events
archive_old_events() {
    local archive_after_days="${1:-$UNITY_EVENT_ARCHIVE_AFTER_DAYS}"
    local dry_run="${2:-false}"
    
    local archived_count=0
    
    find "$UNITY_EVENT_STORAGE_DIR/by-date" -name "*.events" -mtime +$archive_after_days | while read -r event_file; do
        if [[ "$dry_run" == "true" ]]; then
            echo "[DRY RUN] Would archive: $event_file"
        else
            # Compress and move to archive
            gzip "$event_file"
            mv "${event_file}.gz" "$UNITY_EVENT_ARCHIVE_DIR/"
            
            # Log archival
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Archived $event_file" >> "$UNITY_EVENT_ARCHIVE_DIR/archive.log"
        fi
        
        archived_count=$((archived_count + 1))
    done
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "INFO" "Archived $archived_count event files (dry_run=$dry_run)"
    fi
    
    return 0
}

# Get storage statistics
get_storage_stats() {
    local format="${1:-summary}"
    
    case "$format" in
        "summary")
            _get_storage_summary
            ;;
        "detailed")
            _get_detailed_storage_stats
            ;;
        "json")
            _get_storage_stats_json
            ;;
    esac
}

# Get storage summary
_get_storage_summary() {
    local total_events
    total_events=$(grep "^TOTAL_EVENTS_STORED=" "$UNITY_EVENT_STORAGE_DIR/metadata.info" | cut -d'=' -f2 2>/dev/null || echo "0")
    
    local storage_size
    storage_size=$(du -sh "$UNITY_EVENT_STORAGE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    
    local index_size
    index_size=$(du -sh "$UNITY_EVENT_INDEXES_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    
    echo "=== Event Storage Summary ==="
    echo "Total Events: $total_events"
    echo "Storage Size: $storage_size"
    echo "Index Size: $index_size"
    echo "Archive Directory: $(ls -1 "$UNITY_EVENT_ARCHIVE_DIR" 2>/dev/null | wc -l) files"
}

# Get detailed storage statistics
_get_detailed_storage_stats() {
    _get_storage_summary
    echo
    echo "=== Event Types ==="
    if [[ -f "$UNITY_EVENT_INDEXES_DIR/by-type.idx" ]]; then
        awk -F'|' '{print $3}' "$UNITY_EVENT_INDEXES_DIR/by-type.idx" | sort | uniq -c | sort -nr | head -10
    fi
    
    echo
    echo "=== Event Sources ==="
    if [[ -f "$UNITY_EVENT_INDEXES_DIR/by-source.idx" ]]; then
        awk -F'|' '{print $3}' "$UNITY_EVENT_INDEXES_DIR/by-source.idx" | sort | uniq -c | sort -nr | head -10
    fi
}

# Get storage statistics in JSON format
_get_storage_stats_json() {
    local total_events
    total_events=$(grep "^TOTAL_EVENTS_STORED=" "$UNITY_EVENT_STORAGE_DIR/metadata.info" | cut -d'=' -f2 2>/dev/null || echo "0")
    
    local storage_size_bytes
    storage_size_bytes=$(du -sb "$UNITY_EVENT_STORAGE_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    cat <<EOF
{
  "total_events": $total_events,
  "storage_size_bytes": $storage_size_bytes,
  "storage_version": "$UNITY_EVENT_STORAGE_VERSION",
  "last_updated": $(date +%s)
}
EOF
}

#############################################
# Utility Functions
#############################################

# Log persistence errors
_log_persistence_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$timestamp|ERROR|PERSISTENCE|$message" >> "$UNITY_EVENT_STORAGE_DIR/error.log"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "ERROR" "Event Persistence: $message"
    else
        echo "ERROR: Event Persistence: $message" >&2
    fi
}

#############################################
# Export Functions
#############################################

# Export all persistence functions
export -f init_event_persistence
export -f store_event
export -f query_events
export -f create_event_snapshot
export -f replay_from_snapshot
export -f list_snapshots
export -f rebuild_indexes
export -f archive_old_events 
export -f get_storage_stats

# Initialize persistence if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_event_persistence "true"
fi