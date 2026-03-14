#!/usr/bin/env bash
set -euo pipefail

# Smoke test: verifies the app starts and key pages load without errors.
# Page paths are configurable via SMOKE_PAGES env var (comma-separated).
# Exit 0 = all checks pass, Exit 1 = one or more failed

FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
GATE_LEVEL="${GATE_LEVEL:-mvp}"
SMOKE_PAGES="${SMOKE_PAGES:-/}"
RESULTS_FILE=".claude/tmp/smoke-results.json"

mkdir -p .claude/tmp
PASSED=0
FAILED=0
WARNED=0
CHECKS=()

check() {
    local name="$1"
    local url="$2"
    local expect_in_body="${3:-}"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^[23] ]]; then
        if [[ -n "$expect_in_body" ]]; then
            local page_body
            page_body=$(curl -s "$url" 2>/dev/null)
            if echo "$page_body" | grep -qi "$expect_in_body"; then
                PASSED=$((PASSED + 1))
                CHECKS+=("{\"name\": \"$name\", \"status\": \"pass\", \"http\": $http_code}")
                echo "  PASS  $name (HTTP $http_code)"
                return 0
            else
                FAILED=$((FAILED + 1))
                CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"http\": $http_code, \"reason\": \"Expected: $expect_in_body\"}")
                echo "  FAIL  $name (HTTP $http_code — missing: $expect_in_body)"
                return 1
            fi
        fi
        PASSED=$((PASSED + 1))
        CHECKS+=("{\"name\": \"$name\", \"status\": \"pass\", \"http\": $http_code}")
        echo "  PASS  $name (HTTP $http_code)"
    else
        FAILED=$((FAILED + 1))
        CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"http\": $http_code}")
        echo "  FAIL  $name (HTTP $http_code)"
    fi
}

check_no_error_banner() {
    local name="$1"
    local url="$2"

    local page_body
    page_body=$(curl -s "$url" 2>/dev/null) || page_body=""

    if echo "$page_body" | grep -qi "without a database\|not configured\|Setup needed"; then
        if [[ "$GATE_LEVEL" == "team" || "$GATE_LEVEL" == "production" ]]; then
            FAILED=$((FAILED + 1))
            CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"reason\": \"Database not connected\"}")
            echo "  FAIL  $name (database not connected — required at $GATE_LEVEL gate)"
            return 1
        else
            WARNED=$((WARNED + 1))
            PASSED=$((PASSED + 1))
            CHECKS+=("{\"name\": \"$name\", \"status\": \"warn\", \"reason\": \"No database — OK for building\"}")
            echo "  WARN  $name (no database — OK for building)"
            return 0
        fi
    fi

    if echo "$page_body" | grep -qiE "500 Internal|Server Error|Unhandled Exception|FATAL"; then
        FAILED=$((FAILED + 1))
        CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"reason\": \"Page error\"}")
        echo "  FAIL  $name (page contains error)"
        return 1
    fi

    PASSED=$((PASSED + 1))
    CHECKS+=("{\"name\": \"$name\", \"status\": \"pass\"}")
    echo "  PASS  $name (no errors)"
}

echo ""
echo "Smoke Test ($GATE_LEVEL gate)"
echo "──────────────────────────────────────────"
echo ""

# Backend checks
echo "Backend ($BACKEND_URL):"
check "health-endpoint" "$BACKEND_URL/api/health"
check "api-docs" "$BACKEND_URL/docs"
echo ""

# Frontend checks — configurable pages
echo "Frontend ($FRONTEND_URL):"
IFS=',' read -ra PAGES <<< "$SMOKE_PAGES"
for page in "${PAGES[@]}"; do
    page=$(echo "$page" | xargs)  # trim whitespace
    page_name=$(echo "$page" | tr '/' '-' | sed 's/^-//')
    [[ -z "$page_name" ]] && page_name="home"
    check "$page_name-page" "$FRONTEND_URL$page"
    check_no_error_banner "$page_name-no-errors" "$FRONTEND_URL$page"
done
echo ""

# Summary
echo "──────────────────────────────────────────"
if [[ $WARNED -gt 0 ]]; then
    echo "Results: $PASSED passed, $FAILED failed, $WARNED warnings"
else
    echo "Results: $PASSED passed, $FAILED failed"
fi
echo ""

# Write results
CHECKS_JSON=$(printf '%s\n' "${CHECKS[@]}" | paste -sd',' -)
cat > "$RESULTS_FILE" << RESULT_EOF
{
  "total": $((PASSED + FAILED)),
  "passed": $PASSED,
  "failed": $FAILED,
  "checks": [$CHECKS_JSON]
}
RESULT_EOF

if [[ $FAILED -gt 0 ]]; then
    echo "Smoke test FAILED — $FAILED check(s) need attention."
    exit 1
else
    echo "Smoke test PASSED."
    exit 0
fi
