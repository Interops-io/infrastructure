#!/bin/sh

# Deployment processor - watches queue and processes deployment requests
# Runs inside deployer container with full docker and git access

set -e

QUEUE_DIR="/queue"
PROJECTS_DIR="/projects"
PROCESSED_DIR="/queue/processed"
FAILED_DIR="/queue/failed"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEPLOYER] $1"
}

# Initialize directories
mkdir -p "$PROCESSED_DIR" "$FAILED_DIR"

log "🔄 Deployment processor started"
log "📁 Watching queue directory: $QUEUE_DIR"

# Check disk space on startup
check_disk_space() {
    local available=$(df /projects | tail -1 | awk '{print $4}')
    local threshold=1048576  # 1GB in KB
    if [ "$available" -lt "$threshold" ]; then
        log "⚠️ Low disk space warning: $(($available/1024))MB available"
    fi
}

check_disk_space

# Process a single deployment request
process_deployment() {
    local request_file="$1"
    local request_id=$(basename "$request_file" .json)
    
    log "📦 Processing deployment request: $request_id"
    
    # Parse JSON using jq for reliable extraction
    local repository=$(jq -r '.repository' "$request_file" 2>/dev/null)
    local branch=$(jq -r '.branch' "$request_file" 2>/dev/null)
    local environment=$(jq -r '.environment' "$request_file" 2>/dev/null)
    local commit_sha=$(jq -r '.commit_sha' "$request_file" 2>/dev/null)
    local pusher=$(jq -r '.pusher_name' "$request_file" 2>/dev/null)
    
    # Validate required fields
    if [ -z "$repository" ] || [ "$repository" = "null" ] || [ -z "$branch" ] || [ "$branch" = "null" ]; then
        log "❌ Invalid or corrupted request file: $request_file"
        mv "$request_file" "$FAILED_DIR/"
        return 1
    fi
    
    log "Repository: $repository"
    log "Branch: $branch → Environment: $environment"
    log "Commit: $commit_sha"
    log "Pushed by: $pusher"
    
    # Update request status to processing
    local temp_file="${request_file}.processing"
    jq '.status = "processing"' "$request_file" > "$temp_file"
    mv "$temp_file" "$request_file"
    
    # Parse additional fields for webhook-dispatcher.sh
    local clone_url=$(jq -r '.repository_clone_url' "$request_file")
    local ssh_url=$(jq -r '.repository_ssh_url' "$request_file")
    local ref=$(jq -r '.ref' "$request_file")
    
    # Set environment variables that webhook-dispatcher.sh expects
    export WEBHOOK_REPOSITORY_NAME="$repository"
    export WEBHOOK_REF="$ref"
    export WEBHOOK_COMMIT_SHA="$commit_sha"
    export WEBHOOK_PUSHER_NAME="$pusher"
    export WEBHOOK_BRANCH="$ref"
    export WEBHOOK_REPOSITORY_CLONE_URL="$clone_url"
    export WEBHOOK_REPOSITORY_SSH_URL="$ssh_url"
    
    # Execute the actual deployment (use existing webhook-dispatcher.sh logic)
    if /scripts/webhook-dispatcher.sh "$repository" "$ref"; then
        log "✅ Deployment completed successfully"
        
        # Update status and move to processed
        jq '.status = "completed"' "$request_file" > "$temp_file"
        mv "$temp_file" "$PROCESSED_DIR/$(basename "$request_file")"
        
        # Output success metrics
        echo "METRICS: deployment_completed{project=\"$repository\",environment=\"$environment\",commit=\"$commit_sha\",branch=\"$branch\",pusher=\"$pusher\"} $(date +%s)"
    else
        log "❌ Deployment failed"
        
        # Update status and move to failed
        jq '.status = "failed"' "$request_file" > "$temp_file"
        mv "$temp_file" "$FAILED_DIR/$(basename "$request_file")"
        
        # Output failure metrics
        echo "METRICS: deployment_failed{project=\"$repository\",environment=\"$environment\",commit=\"$commit_sha\",branch=\"$branch\",pusher=\"$pusher\"} $(date +%s)"
    fi
}

# Watch for new deployment requests using inotify
watch_queue() {
    log "📁 Processing any existing deployment requests..."

    # Process any existing files first (top-level only)
    for request_file in "$QUEUE_DIR"/*.json; do
        [ -f "$request_file" ] || continue
        case "$(basename "$request_file")" in
            .*) continue ;;  # Skip hidden
            *.tmp) continue ;;
        esac
        process_deployment "$request_file"
    done

    log "👁️ Starting inotify file watcher on $QUEUE_DIR (create + moved_to events)"

    # New approach:
    #  - Watch create and moved_to so files written via temp -> final name are picked up.
    #  - Before processing, validate JSON and ensure .status field is missing or null.
    #  - Skip if status is processing/completed/failed to avoid loops.
    #  - Still restrict to top-level directory.

    inotifywait -m "$QUEUE_DIR" -e create -e moved_to --format '%w%f' --exclude '(^|/)processed/|(^|/)failed/' 2>/dev/null | while read filepath; do
        dir_part=$(dirname "$filepath")
        base_part=$(basename "$filepath")
        [ "$dir_part" = "$QUEUE_DIR" ] || continue
        case "$base_part" in
            .*) continue ;;
            *.tmp) continue ;;
            *.json)
                [ -f "$filepath" ] || continue
                # Validate JSON structure quietly
                if ! jq empty "$filepath" 2>/dev/null; then
                    log "⚠️ Ignoring invalid JSON file: $base_part"
                    continue
                fi
                file_status=$(jq -r 'try .status // ""' "$filepath" 2>/dev/null)
                case "$file_status" in
                    ""|null)
                        log "📥 New deployment request detected (no status): $base_part"
                        process_deployment "$filepath"
                        ;;
                    processing|completed|failed)
                        # Already handled or in-flight
                        continue
                        ;;
                    *)
                        # Unknown status - skip to avoid unintended reprocessing
                        log "ℹ️ Skipping file with status '$file_status': $base_part"
                        continue
                        ;;
                esac
                ;;
            *) continue ;;
        esac
    done
}

# Handle graceful shutdown
trap 'log "🛑 Shutting down deployment processor"; exit 0' TERM INT

# Check if inotify is available
if ! command -v inotifywait >/dev/null 2>&1; then
    log "❌ inotifywait not found. Please install inotify-tools package."
    exit 1
fi

# Start watching
log "🚀 Starting deployment processor with inotify file watching"
watch_queue