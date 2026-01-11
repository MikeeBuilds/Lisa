#!/bin/bash
# Lisa - Gemini Autonomous Agent (Ralph Port)
# Usage: ./lisa.sh [max_iterations]

set -e

# Configuration
MAX_ITERATIONS=${1:-20}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" # Go up one level to root
PRD_FILE="$PLUGIN_ROOT/prd.json"
PROGRESS_FILE="$PLUGIN_ROOT/progress.txt"
ARCHIVE_DIR="$PLUGIN_ROOT/archive"
LAST_BRANCH_FILE="$PLUGIN_ROOT/.last-branch"
PROMPT_TEMPLATE="$PLUGIN_ROOT/prompt.md"
RESPONSE_FILE="$PLUGIN_ROOT/last_response.md"
CONTEXT_FILE="$PLUGIN_ROOT/context.txt"
FULL_PROMPT_FILE="$PLUGIN_ROOT/full_prompt_temp.txt"
HOOKS_DIR="$PLUGIN_ROOT/hooks"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Starting Lisa (Ralph Port)...${NC}"

# Check prerequisites
for cmd in gemini jq; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: '$cmd' not found.${NC}"
        exit 1
    fi
done

# --- Ralph's Archiving Logic ---
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^lisa/||') # Adapted from ralph/
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    echo "# Lisa Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Lisa Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# --- Helper Functions ---

# Trap Ctrl+C for safe exit
trap ctrl_c INT

ctrl_c() {
    echo -e "\n${RED}Lisa interrupted by user. Saving state...${NC}"
    log_progress "Interrupted by User"
    exit 130
}

get_next_story() {
    # Find first story where 'passes' is false
    jq -c '.userStories[] | select(.passes==false)' "$PRD_FILE" | head -n 1
}

update_story_status() {
    local story_id=$1
    local status=$2 # true or false
    local temp_file=$(mktemp)
    jq ".(.userStories[] | select(.id == \"$story_id\") | .passes) = $status" "$PRD_FILE" > "$temp_file" && mv "$temp_file" "$PRD_FILE"
}

log_progress() {
    echo "[$(date +%T)] $1" >> "$PROGRESS_FILE"
}

# --- Main Loop ---

for i in $(seq 1 $MAX_ITERATIONS); do
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Lisa Iteration $i of $MAX_ITERATIONS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    STORY_JSON=$(get_next_story)

    if [ -z "$STORY_JSON" ]; then
        echo -e "${GREEN}All User Stories completed!${NC}"
        echo "Lisa completed all tasks at iteration $i."
        log_progress "COMPLETED ALL TASKS"
        exit 0
    fi

    STORY_ID=$(echo "$STORY_JSON" | jq -r '.id')
    STORY_TITLE=$(echo "$STORY_JSON" | jq -r '.title')
    STORY_DESC=$(echo "$STORY_JSON" | jq -r '.description')
    
    echo -e "${BLUE}Current Story ($STORY_ID): $STORY_TITLE${NC}"
    log_progress "Starting $STORY_ID: $STORY_TITLE"

    # 1. Gather Context (Gemini specific)
    echo "Gathering project context..."
    echo "# Project Structure" > "$CONTEXT_FILE"
    find . -maxdepth 4 -not -path '*/.*' -not -path './node_modules*' -not -path './archive*' >> "$CONTEXT_FILE"
    
    echo -e "\n# File Contents" >> "$CONTEXT_FILE"
    # Read relevant files (source code, config, docs)
    find . -maxdepth 4 -type f \
        -not -path '*/.*' \
        -not -name "$CONTEXT_FILE" \
        -not -name "$RESPONSE_FILE" \
        -not -name "full_prompt_temp.txt" \
        -not -path "./archive*" \
        -not -name "*.png" \
        -not -name "*.jpg" \
        | while read -r file; do
        if file "$file" | grep -q "text"; then
            echo -e "\n## File: $file" >> "$CONTEXT_FILE"
            echo '```' >> "$CONTEXT_FILE"
            cat "$file" >> "$CONTEXT_FILE"
            echo -e "\n'```'" >> "$CONTEXT_FILE"
        fi
    done

    # 2. Construct Prompt
    # We combine the Template + Context + Current Task
    cat "$PROMPT_TEMPLATE" > "$FULL_PROMPT_FILE"
    echo -e "\n\n# Project Context" >> "$FULL_PROMPT_FILE"
    cat "$CONTEXT_FILE" >> "$FULL_PROMPT_FILE"
    echo -e "\n\n# Current User Story" >> "$FULL_PROMPT_FILE"
    echo "ID: $STORY_ID" >> "$FULL_PROMPT_FILE"
    echo "Title: $STORY_TITLE" >> "$FULL_PROMPT_FILE"
    echo "Description: $STORY_DESC" >> "$FULL_PROMPT_FILE"
    echo "Acceptance Criteria:" >> "$FULL_PROMPT_FILE"
    echo "$STORY_JSON" | jq -r '.acceptanceCriteria[]' | sed 's/^/- /' >> "$FULL_PROMPT_FILE"

    # 3. Call Gemini
    echo "Sending prompt to Gemini..."
    gemini "$(cat "$FULL_PROMPT_FILE")" --output-format text > "$RESPONSE_FILE" 2>/dev/null
    
    echo -e "${GREEN}Response received.${NC}"
    log_progress "Response received for $STORY_ID"

    # 4. Execute Plan
    BASH_CODE=$(sed -n '/```bash/,/```/p' "$RESPONSE_FILE" | sed '1d;$d')

    if [ -n "$BASH_CODE" ]; then
        echo -e "${BLUE}Executing plan...${NC}"
        echo "-----------------------------------"
        echo "$BASH_CODE"
        echo "-----------------------------------"
        
        # Capture output
        EXEC_OUTPUT=$(echo "$BASH_CODE" | bash 2>&1)
        EXEC_EXIT_CODE=$?
        
        echo "$EXEC_OUTPUT"
        
        if [ $EXEC_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}Execution successful.${NC}"
            
            # --- LISA ENHANCED VALIDATION ---
            if [ -f "$HOOKS_DIR/validate.sh" ]; then
                echo -e "${BLUE}Running Validation Hook...${NC}"
                "$HOOKS_DIR/validate.sh"
                VALIDATION_EXIT_CODE=$?
            else
                VALIDATION_EXIT_CODE=0
            fi

            if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
                echo -e "${GREEN}Validation Passed. Marking story as complete.${NC}"
                update_story_status "$STORY_ID" "true"
                log_progress "Completed $STORY_ID"
            else
                echo -e "${RED}Validation Failed.${NC}"
                [ -f "$HOOKS_DIR/stop-hook.sh" ] && "$HOOKS_DIR/stop-hook.sh" "$STORY_ID" "Validation Failed"
                log_progress "Validation Failed for $STORY_ID"
            fi
        else
            echo -e "${RED}Execution failed.${NC}"
            [ -f "$HOOKS_DIR/stop-hook.sh" ] && "$HOOKS_DIR/stop-hook.sh" "$STORY_ID" "Execution Failed (Exit Code: $EXEC_EXIT_CODE)"
            log_progress "Failed $STORY_ID (Exit Code: $EXEC_EXIT_CODE)"
        fi
    else
        echo -e "${RED}No code block found.${NC}"
        log_progress "No code block returned for $STORY_ID"
    fi
    
    sleep 2
done

echo ""
echo "Reached max iterations ($MAX_ITERATIONS)."
exit 1
