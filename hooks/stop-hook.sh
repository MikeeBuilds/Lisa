#!/bin/bash
# hooks/on-failure.sh
# Runs when a Lisa iteration fails (Gemini code execution fails or validation fails).

FAILED_STORY_ID=$1
ERROR_MSG=$2

echo "Handling failure for $FAILED_STORY_ID..."
echo "Error: $ERROR_MSG"

# 1. Log the error specifically to a dedicated error log
echo "[$(date)] FAILED: $FAILED_STORY_ID - $ERROR_MSG" >> "error_log.txt"

# 2. (Optional) Revert changes? 
# Ralph often persists changes, so we might not want to revert immediately.
# But we could tag the git state.
# git tag "fail-$FAILED_STORY_ID-$(date +%s)"

# 3. Suggest a search?
# If the error contains specific keywords, we could append a suggestion file.
