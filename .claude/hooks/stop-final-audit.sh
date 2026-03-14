#!/usr/bin/env bash
# Final audit on session stop — warnings only, never blocks (too late to undo)
# BUILD mode: only gitleaks scan
# DEPLOY mode: full audit (gitleaks, npm audit, pip-audit, TODO check, missing tests)
# Triggered on: Stop event
# Always exits 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/mode.sh"

AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# Safety: any unexpected error exits cleanly
trap 'exit 0' ERR

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "" >> "$AUDIT_LOG"
echo "========================================" >> "$AUDIT_LOG"
echo "[$TIMESTAMP] FINAL AUDIT — Session Stop" >> "$AUDIT_LOG"
echo "========================================" >> "$AUDIT_LOG"

WARNINGS=0
MODE=$(get_mode)

# --- Early exit: skip if nothing has changed this session ---
if git rev-parse --is-inside-work-tree &>/dev/null; then
    CHANGED=$(git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null)
    if [[ -z "$CHANGED" ]]; then
        echo "[$TIMESTAMP] SKIPPED: No changed files — nothing to audit" >> "$AUDIT_LOG"
        exit 0
    fi
fi

# --- Gitleaks full scan (always runs in both modes) ---
if command -v gitleaks &>/dev/null; then
    GITLEAKS_OUTPUT=$(gitleaks detect --source=. 2>&1)
    GITLEAKS_EXIT=$?
    if [[ $GITLEAKS_EXIT -ne 0 ]]; then
        echo "[$TIMESTAMP] WARNING: Gitleaks detected secrets" >> "$AUDIT_LOG"
        echo "$GITLEAKS_OUTPUT" >> "$AUDIT_LOG"
        ((WARNINGS++))
    else
        echo "[$TIMESTAMP] OK: Gitleaks scan clean" >> "$AUDIT_LOG"
    fi
else
    echo "[$TIMESTAMP] SKIPPED: gitleaks not installed" >> "$AUDIT_LOG"
fi

# --- DEPLOY mode only: full audit checks ---
if [[ "$MODE" == "deploy" ]]; then

    # --- npm audit ---
    if [[ -f "frontend/package-lock.json" ]] && command -v npm &>/dev/null; then
        NPM_AUDIT=$(cd frontend && npm audit --audit-level=high 2>&1)
        NPM_EXIT=$?
        if [[ $NPM_EXIT -ne 0 ]]; then
            echo "[$TIMESTAMP] WARNING: npm audit found vulnerabilities" >> "$AUDIT_LOG"
            echo "$NPM_AUDIT" >> "$AUDIT_LOG"
            ((WARNINGS++))
        else
            echo "[$TIMESTAMP] OK: npm audit clean" >> "$AUDIT_LOG"
        fi
    fi

    # --- pip-audit ---
    if [[ -f "backend/requirements.txt" || -f "requirements.txt" ]]; then
        if command -v pip-audit &>/dev/null; then
            REQ_FILE="requirements.txt"
            [[ -f "backend/requirements.txt" ]] && REQ_FILE="backend/requirements.txt"
            PIP_AUDIT=$(pip-audit -r "$REQ_FILE" 2>&1)
            PIP_EXIT=$?
            if [[ $PIP_EXIT -ne 0 ]]; then
                echo "[$TIMESTAMP] WARNING: pip-audit found vulnerabilities" >> "$AUDIT_LOG"
                echo "$PIP_AUDIT" >> "$AUDIT_LOG"
                ((WARNINGS++))
            else
                echo "[$TIMESTAMP] OK: pip-audit clean" >> "$AUDIT_LOG"
            fi
        else
            echo "[$TIMESTAMP] SKIPPED: pip-audit not installed" >> "$AUDIT_LOG"
        fi
    fi

    # --- TODO/FIXME check in changed files ---
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
        if [[ -n "$CHANGED_FILES" ]]; then
            TODO_TOTAL=0
            TODO_FILES=""
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    COUNT=$(grep -ciE '\bTODO\b|\bFIXME\b' "$file" 2>/dev/null; true)
                    if [[ "$COUNT" -gt 0 ]]; then
                        TODO_TOTAL=$((TODO_TOTAL + COUNT))
                        TODO_FILES="$TODO_FILES  - $file ($COUNT markers)\n"
                    fi
                fi
            done <<< "$CHANGED_FILES"

            if [[ $TODO_TOTAL -gt 0 ]]; then
                echo "[$TIMESTAMP] WARNING: $TODO_TOTAL TODO/FIXME in changed files" >> "$AUDIT_LOG"
                echo -e "$TODO_FILES" >> "$AUDIT_LOG"
                ((WARNINGS++))
            else
                echo "[$TIMESTAMP] OK: No TODO/FIXME in changed files" >> "$AUDIT_LOG"
            fi
        fi

        # --- Missing test files for new source files ---
        NEW_FILES=$(git diff --diff-filter=A --name-only HEAD 2>/dev/null || echo "")
        if [[ -n "$NEW_FILES" ]]; then
            MISSING_TESTS=""
            while IFS= read -r file; do
                if echo "$file" | grep -qE '(test_|\.test\.|\.spec\.|__pycache__|migrations/|docs/|\.claude/|\.config)'; then
                    continue
                fi
                if echo "$file" | grep -qE '\.(py|ts|tsx|js|jsx|vue)$'; then
                    BASE_NAME=$(basename "$file" | sed 's/\.\(py\|ts\|tsx\|js\|jsx\|vue\)$//')
                    TEST_EXISTS=false

                    if echo "$file" | grep -qE '\.py$'; then
                        find backend/tests -name "test_${BASE_NAME}.py" 2>/dev/null | grep -q . && TEST_EXISTS=true
                    fi

                    if echo "$file" | grep -qE '\.(ts|tsx|js|jsx|vue)$'; then
                        find frontend/tests -name "${BASE_NAME}.test.*" -o -name "${BASE_NAME}.spec.*" 2>/dev/null | grep -q . && TEST_EXISTS=true
                    fi

                    if [[ "$TEST_EXISTS" == false ]]; then
                        MISSING_TESTS="$MISSING_TESTS  - $file\n"
                    fi
                fi
            done <<< "$NEW_FILES"

            if [[ -n "$MISSING_TESTS" ]]; then
                echo "[$TIMESTAMP] WARNING: New files missing tests" >> "$AUDIT_LOG"
                echo -e "$MISSING_TESTS" >> "$AUDIT_LOG"
                ((WARNINGS++))
            fi
        fi
    fi

else
    echo "[$TIMESTAMP] BUILD MODE: Skipped deploy-only checks" >> "$AUDIT_LOG"
fi

# --- Session checkpoint ---
SESSION_DIR=".claude/session"
mkdir -p "$SESSION_DIR" 2>/dev/null || true

GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_STATUS=$(git status --short 2>/dev/null || echo "")
LAST_COMMIT=$(git log -1 --format="%h %s" 2>/dev/null || echo "none")
FILES_MODIFIED="[]"
if [[ -f "$SESSION_DIR/file-log.txt" ]]; then
    FILES_MODIFIED=$(sort -u "$SESSION_DIR/file-log.txt" | head -100 | sed 's/"/\\"/g' | awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')
fi

cat > "$SESSION_DIR/latest.json" << CHECKPOINT_EOF
{
  "session_id": "$(date '+%Y%m%d-%H%M%S')",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "status": "completed",
  "task_brief": "",
  "files_modified": $FILES_MODIFIED,
  "git_branch": "$GIT_BRANCH",
  "git_status": $(echo "$GIT_STATUS" | head -20 | sed 's/"/\\"/g' | awk 'BEGIN{printf "\""} NR>1{printf "\\n"} {printf "%s", $0} END{printf "\""}'),
  "last_commit": "$LAST_COMMIT"
}
CHECKPOINT_EOF
echo "[$TIMESTAMP] Session checkpoint written to $SESSION_DIR/latest.json" >> "$AUDIT_LOG"

# --- Final summary (single line to stderr) ---
echo "" >> "$AUDIT_LOG"
echo "[$TIMESTAMP] FINAL AUDIT COMPLETE ($MODE mode): $WARNINGS warning(s)" >> "$AUDIT_LOG"
echo "Audit complete ($MODE mode): $WARNINGS warning(s)" >&2

# Always exit 0 — stop hooks should never block
exit 0
