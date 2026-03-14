#!/usr/bin/env bash
set -uo pipefail

# Master CI/CD pipeline orchestrator — gate-level aware
# Usage: bash .claude/scripts/run-pipeline.sh [mvp|team|production]
# Reads .claude/deploy-gates.json for stage requirements per gate level
# Exit 0 = PIPELINE PASSED, Exit 1 = PIPELINE FAILED

GATE_LEVEL="${1:-production}"
PIPELINE_START=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Set deploy mode, restore build mode on exit
echo "deploy" > .claude/mode
trap 'echo "build" > .claude/mode' EXIT

# Clean tmp directory
rm -rf .claude/tmp
mkdir -p .claude/tmp

echo "═══════════════════════════════════════════════════════════"
echo " CI/CD PIPELINE — $TIMESTAMP"
echo " Gate level: $GATE_LEVEL"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Read gate config
DEPLOY_GATES=".claude/deploy-gates.json"
if [[ ! -f "$DEPLOY_GATES" ]]; then
    echo "ERROR: $DEPLOY_GATES not found" >&2
    exit 1
fi

# Check if a stage is required for current gate level
stage_required() {
    local stage="$1"
    if command -v jq &>/dev/null; then
        jq -e ".\"$GATE_LEVEL\".requires | index(\"$stage\")" "$DEPLOY_GATES" &>/dev/null
        return $?
    fi
    # Fallback: grep-based check
    grep -q "\"$stage\"" <<< "$(grep -A 20 "\"$GATE_LEVEL\"" "$DEPLOY_GATES" | grep -A 10 '"requires"')"
}

# Track stage results
declare -a FAILED_STAGES=()
declare -A STAGE_STATUS=()
declare -A STAGE_PIDS=()

# ============================================================
# Stage: Security Scan (always runs)
# ============================================================
echo "Running security scan..."
(
    bash .claude/scripts/security-scan.sh > .claude/tmp/security-output.txt 2>&1
) &
STAGE_PIDS[security]=$!

# ============================================================
# Stage: Smoke Test (mvp and above)
# ============================================================
if stage_required "app-starts" || stage_required "happy-path-works"; then
    echo "Running smoke tests..."
    (
        GATE_LEVEL="$GATE_LEVEL" bash .claude/scripts/smoke-test.sh > .claude/tmp/smoke-output.txt 2>&1
    ) &
    STAGE_PIDS[smoke]=$!
else
    STAGE_STATUS[smoke]="SKIP"
fi

# ============================================================
# Stage: Unit Tests (team and above)
# ============================================================
if stage_required "unit-tests"; then
    echo "Running unit tests..."
    (
        BACKEND_EXIT=0
        FRONTEND_EXIT=0

        if command -v pytest &>/dev/null && [[ -d "backend/tests" ]]; then
            cd backend && python -m pytest \
                --cov=. \
                --cov-report=json:../.claude/tmp/backend-coverage.json \
                --cov-report=term-missing \
                -v --tb=short \
                2>&1 | tee ../.claude/tmp/backend-unit-output.txt
            BACKEND_EXIT=${PIPESTATUS[0]}
            cd ..
        fi

        if command -v npx &>/dev/null && [[ -f "frontend/package.json" ]]; then
            cd frontend && npx vitest run --coverage --reporter=verbose \
                2>&1 | tee ../.claude/tmp/frontend-unit-output.txt
            FRONTEND_EXIT=${PIPESTATUS[0]}
            cd ..
        fi

        if [[ ${BACKEND_EXIT:-0} -eq 0 && ${FRONTEND_EXIT:-0} -eq 0 ]]; then
            echo '{"stage": "unit-tests", "overall_status": "PASS"}' > .claude/tmp/unit-results.json
            exit 0
        else
            echo '{"stage": "unit-tests", "overall_status": "FAIL"}' > .claude/tmp/unit-results.json
            exit 1
        fi
    ) &
    STAGE_PIDS[unit]=$!
else
    STAGE_STATUS[unit]="SKIP"
fi

# ============================================================
# Stage: Integration Tests (production only)
# ============================================================
if stage_required "integration-tests"; then
    echo "Running integration tests..."
    (
        if command -v pytest &>/dev/null && [[ -d "backend/tests/integration" ]]; then
            cd backend && python -m pytest tests/integration/ -v --tb=short \
                2>&1 | tee ../.claude/tmp/integration-output.txt
            if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                echo '{"stage": "integration-tests", "overall_status": "PASS"}' > .claude/tmp/integration-results.json
                exit 0
            else
                echo '{"stage": "integration-tests", "overall_status": "FAIL"}' > .claude/tmp/integration-results.json
                exit 1
            fi
        else
            echo '{"stage": "integration-tests", "overall_status": "SKIP"}' > .claude/tmp/integration-results.json
            exit 0
        fi
    ) &
    STAGE_PIDS[integration]=$!
else
    STAGE_STATUS[integration]="SKIP"
fi

# ============================================================
# Stage: UI Tests (production only)
# ============================================================
if stage_required "ui-tests"; then
    echo "Running UI tests..."
    (
        if command -v npx &>/dev/null && [[ -f "frontend/playwright.config.ts" || -f "frontend/playwright.config.js" ]]; then
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
            if [[ "$HTTP_STATUS" == "000" || "$HTTP_STATUS" == "0" ]]; then
                echo '{"stage": "ui-tests", "overall_status": "SKIP", "reason": "App not running"}' > .claude/tmp/ui-results.json
                exit 0
            fi
            cd frontend && npx playwright test --reporter=json \
                2>&1 | tee ../.claude/tmp/playwright-output.txt
            if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                echo '{"stage": "ui-tests", "overall_status": "PASS"}' > .claude/tmp/ui-results.json
                exit 0
            else
                echo '{"stage": "ui-tests", "overall_status": "FAIL"}' > .claude/tmp/ui-results.json
                exit 1
            fi
        else
            echo '{"stage": "ui-tests", "overall_status": "SKIP"}' > .claude/tmp/ui-results.json
            exit 0
        fi
    ) &
    STAGE_PIDS[ui]=$!
else
    STAGE_STATUS[ui]="SKIP"
fi

# ============================================================
# Stage: Performance (production only)
# ============================================================
if stage_required "performance"; then
    echo "Running performance tests..."
    (
        K6_STATUS="SKIP"
        LH_STATUS="SKIP"

        if command -v k6 &>/dev/null; then
            K6_SCRIPT=$(find . -path "*/k6/*.js" -o -path "*/k6/*.ts" 2>/dev/null | head -1)
            if [[ -n "$K6_SCRIPT" ]]; then
                k6 run --summary-export=.claude/tmp/k6-export.json "$K6_SCRIPT" \
                    2>&1 | tee .claude/tmp/k6-output.txt
                [[ ${PIPESTATUS[0]} -eq 0 ]] && K6_STATUS="PASS" || K6_STATUS="FAIL"
            fi
        fi

        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
        if [[ "$HTTP_STATUS" != "000" && "$HTTP_STATUS" != "0" ]]; then
            if npx --yes @lhci/cli --version &>/dev/null 2>&1; then
                npx --yes @lhci/cli collect --url=http://localhost:3000 --numberOfRuns=1 \
                    2>&1 | tee .claude/tmp/lighthouse-output.txt
                [[ ${PIPESTATUS[0]} -eq 0 ]] && LH_STATUS="PASS" || LH_STATUS="FAIL"
            fi
        fi

        OVERALL="PASS"
        [[ "$K6_STATUS" == "FAIL" || "$LH_STATUS" == "FAIL" ]] && OVERALL="FAIL"
        [[ "$K6_STATUS" == "SKIP" && "$LH_STATUS" == "SKIP" ]] && OVERALL="SKIP"
        printf '{"stage":"performance","k6":"%s","lighthouse":"%s","overall_status":"%s"}' "$K6_STATUS" "$LH_STATUS" "$OVERALL" > .claude/tmp/k6-summary.json
        [[ "$OVERALL" == "FAIL" ]] && exit 1 || exit 0
    ) &
    STAGE_PIDS[perf]=$!
else
    STAGE_STATUS[perf]="SKIP"
fi

# ============================================================
# Wait for all stages
# ============================================================
echo ""
echo "Waiting for stages to complete..."
echo ""

for stage in security smoke unit integration ui perf; do
    if [[ -n "${STAGE_PIDS[$stage]+x}" ]]; then
        wait "${STAGE_PIDS[$stage]}" 2>/dev/null
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 0 ]]; then
            STAGE_STATUS[$stage]="PASS"
            echo "  + $stage: PASS"
        else
            STAGE_STATUS[$stage]="FAIL"
            FAILED_STAGES+=("$stage")
            echo "  x $stage: FAIL (exit $EXIT_CODE)"
        fi
    else
        echo "  - $stage: ${STAGE_STATUS[$stage]:-SKIP}"
    fi
done

echo ""

# ============================================================
# Gate Decision
# ============================================================

if [[ ${#FAILED_STAGES[@]} -gt 0 ]]; then
    echo "═══════════════════════════════════════════════════════════"
    echo " GATE: STAGES FAILED — ${FAILED_STAGES[*]}"
    echo "═══════════════════════════════════════════════════════════"

    PIPELINE_END=$(date +%s)
    DURATION=$((PIPELINE_END - PIPELINE_START))

    cat > .claude/tmp/pipeline-results.md << RESULTS_EOF
Pipeline Results ($GATE_LEVEL gate)
Timestamp: $TIMESTAMP | Duration: ${DURATION}s

Security:    ${STAGE_STATUS[security]:-SKIP}
Smoke:       ${STAGE_STATUS[smoke]:-SKIP}
Unit Tests:  ${STAGE_STATUS[unit]:-SKIP}
Integration: ${STAGE_STATUS[integration]:-SKIP}
UI Tests:    ${STAGE_STATUS[ui]:-SKIP}
Performance: ${STAGE_STATUS[perf]:-SKIP}
Opus Review: SKIPPED

GATE DECISION: PIPELINE FAILED
RESULTS_EOF

    cat .claude/tmp/pipeline-results.md
    exit 1
fi

# ============================================================
# Stage: Opus Code Review (production gate only)
# ============================================================

OPUS_STATUS="SKIP"
OPUS_EXIT=0

if stage_required "opus-review"; then
    echo "═══════════════════════════════════════════════════════════"
    echo " ALL TESTS PASSED — Proceeding to Opus Code Review"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    bash .claude/scripts/build-review-payload.sh
    echo ""

    # Run with 5 minute timeout
    timeout 300 bash .claude/scripts/invoke-opus-reviewer.sh
    OPUS_EXIT=$?

    OPUS_STATUS="APPROVED"
    [[ $OPUS_EXIT -ne 0 ]] && OPUS_STATUS="CHANGES REQUIRED"
fi

# ============================================================
# Final Report
# ============================================================

PIPELINE_END=$(date +%s)
DURATION=$((PIPELINE_END - PIPELINE_START))

OVERALL_DECISION="PIPELINE PASSED"
FINAL_EXIT=0
if [[ $OPUS_EXIT -ne 0 ]]; then
    OVERALL_DECISION="PIPELINE FAILED"
    FINAL_EXIT=1
fi

cat > .claude/tmp/pipeline-results.md << RESULTS_EOF
Pipeline Results ($GATE_LEVEL gate)
Timestamp: $TIMESTAMP | Duration: ${DURATION}s

Security:    ${STAGE_STATUS[security]:-SKIP}
Smoke:       ${STAGE_STATUS[smoke]:-SKIP}
Unit Tests:  ${STAGE_STATUS[unit]:-SKIP}
Integration: ${STAGE_STATUS[integration]:-SKIP}
UI Tests:    ${STAGE_STATUS[ui]:-SKIP}
Performance: ${STAGE_STATUS[perf]:-SKIP}
Opus Review: $OPUS_STATUS

GATE DECISION: $OVERALL_DECISION
RESULTS_EOF

echo ""
cat .claude/tmp/pipeline-results.md

# ============================================================
# RBAC Verification (team and above)
# ============================================================

if stage_required "rbac-check"; then
    echo ""
    echo "Verifying RBAC setup..."
    RBAC_OK=true

    # Check roles table exists
    if [[ -f "supabase/migrations/00000000000001_rbac.sql" ]]; then
        echo "  + RBAC migration exists"
    else
        echo "  x RBAC migration not found"
        RBAC_OK=false
    fi

    # Check RBAC middleware exists
    if [[ -f "backend/middleware/rbac.py" ]]; then
        echo "  + RBAC middleware exists"
    else
        echo "  x backend/middleware/rbac.py not found"
        RBAC_OK=false
    fi

    # Check useRole composable exists
    if [[ -f "frontend/composables/useRole.ts" ]]; then
        echo "  + useRole composable exists"
    else
        echo "  x frontend/composables/useRole.ts not found"
        RBAC_OK=false
    fi

    if $RBAC_OK; then
        echo "  RBAC check: PASS"
    else
        echo "  RBAC check: WARNING — some RBAC files missing"
    fi
    echo ""
fi

# ============================================================
# Cloud Deploy (if DEPLOY_TARGET=cloud and pipeline passed)
# ============================================================

if [[ "${DEPLOY_TARGET:-}" == "cloud" ]] && [[ $FINAL_EXIT -eq 0 ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo " Pipeline passed — proceeding to cloud deployment"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    CLOUD_ENV="${ENVIRONMENT:-staging}"
    if [[ -f ".claude/scripts/deploy-cloud.sh" ]]; then
        bash .claude/scripts/deploy-cloud.sh "$CLOUD_ENV" || {
            echo "WARNING: Cloud deployment failed." >&2
            FINAL_EXIT=1
        }
    else
        echo "WARNING: deploy-cloud.sh not found. Run scaffold-cloud-configs.sh first." >&2
    fi
fi

# ============================================================
# Changelog Update (only on pipeline pass)
# ============================================================

if [[ $FINAL_EXIT -eq 0 ]]; then
    echo ""
    if [[ -f ".claude/scripts/write-changelog-entry.sh" ]]; then
        bash .claude/scripts/write-changelog-entry.sh || {
            echo "WARNING: Changelog update failed (does not affect pipeline result)." >&2
        }
    fi
fi

exit $FINAL_EXIT
