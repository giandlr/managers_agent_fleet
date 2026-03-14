#!/usr/bin/env bash
set -uo pipefail

# Standalone security scan — gitleaks wrapper
# Exit 0 = clean, Exit 1 = issues found

RESULTS_FILE=".claude/tmp/security-results.json"
mkdir -p .claude/tmp

echo "Security Scan"
echo "──────────────────────────────────────────"
echo ""

ISSUES=0

# Gitleaks
if command -v gitleaks &>/dev/null; then
    GITLEAKS_OUTPUT=$(gitleaks detect --source=. 2>&1)
    GITLEAKS_EXIT=$?
    if [[ $GITLEAKS_EXIT -ne 0 ]]; then
        echo "  FAIL  Secret detected in repository"
        echo "$GITLEAKS_OUTPUT" | head -20
        ISSUES=$((ISSUES + 1))
    else
        echo "  PASS  No secrets detected"
    fi
else
    echo "  SKIP  gitleaks not installed"
fi

# Check for service role key in frontend
if grep -rliE 'SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY' frontend/ 2>/dev/null | grep -qvE 'node_modules'; then
    echo "  FAIL  Service role key found in frontend code"
    ISSUES=$((ISSUES + 1))
else
    echo "  PASS  No service role key in frontend"
fi

# Check for hardcoded secrets patterns
SECRET_FILES=$(grep -rliE 'AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}' --include="*.py" --include="*.ts" --include="*.js" --include="*.vue" . 2>/dev/null | grep -vE 'node_modules|\.claude/' || true)
if [[ -n "$SECRET_FILES" ]]; then
    echo "  FAIL  Hardcoded secret patterns found in:"
    echo "$SECRET_FILES" | head -5 | sed 's/^/         /'
    ISSUES=$((ISSUES + 1))
else
    echo "  PASS  No hardcoded secret patterns"
fi

echo ""
echo "──────────────────────────────────────────"

# Write results
if [[ $ISSUES -eq 0 ]]; then
    echo '{"stage": "security-scan", "overall_status": "PASS", "issues": 0}' > "$RESULTS_FILE"
    echo "Security scan PASSED."
    exit 0
else
    echo "{\"stage\": \"security-scan\", \"overall_status\": \"FAIL\", \"issues\": $ISSUES}" > "$RESULTS_FILE"
    echo "Security scan FAILED — $ISSUES issue(s) found."
    exit 1
fi
