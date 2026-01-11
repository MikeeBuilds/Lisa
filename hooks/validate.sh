#!/bin/bash
# hooks/validate.sh
# Returns 0 if validation passes, 1 otherwise.
# Lisa will NOT mark a story as complete if this script fails.

echo "Running validation checks..."

# Example: Check if simple syntax is correct (for Python/JS)
# In a real project, this would run 'npm test' or 'pytest'

# 1. Check for syntax errors in Python files
if command -v python3 &> /dev/null; then
    find . -name "*.py" -not -path "*/.*" -not -path "./venv/*" | while read -r file; do
        python3 -m py_compile "$file"
        if [ $? -ne 0 ]; then
            echo "Validation Failed: Syntax error in $file"
            exit 1
        fi
    done
fi

# If we reached here, basics pass. 
# Check for any specific 'test' command defined in package.json or similar?
# For now, just return 0 to allow the loop to proceed.
echo "Validation passed."
exit 0