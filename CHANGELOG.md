# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** This file is auto-maintained by the Claude Code pipeline.
> Entries are added automatically when the pipeline passes.
> Manual edits to the Unreleased section will be overwritten on the next
> pipeline run. To add human commentary, use release notes when tagging
> a version with `.claude/scripts/tag-release.sh`.

## [Unreleased]
<!-- UNRELEASED_INSERT_POINT -->

## [v1.2.0] — 2026-03-14

### Added
- **Cloud deployment:** Four new scripts (`scaffold-cloud-configs.sh`, `deploy-cloud.sh`, `generate-handoff-doc.sh`, `setup-supabase-cloud.sh`) for deploying to Vercel + Supabase Cloud
- **Cloud Deploy Mode:** Discovery flow with three paths — self-service, IT handoff, and guided setup; triggered by "deploy to cloud", "make this live"
- **Vercel integration:** `vercel.json` with Nuxt 3 SSR + FastAPI serverless functions at `/api/*`; `api/index.py` adapter wraps existing backend with zero refactoring
- **IT handoff document:** Auto-generated `docs/deployment-guide.md` with Vercel setup, Supabase Cloud setup, env var mapping, security checklist, monitoring/rollback guide
- **CORS cloud support:** Dynamic origin list in `backend/main.py` reads `VERCEL_URL` and `PRODUCTION_URL` from environment
- **Security headers:** X-Content-Type-Options, X-Frame-Options, HSTS, Referrer-Policy configured in `vercel.json`
- **Playwright e2e testing:** Bootstrap installs `@playwright/test` + `@axe-core/playwright` with chromium-only for speed
- **Playwright config:** `frontend/playwright.config.ts` with sensible defaults — JSON reporter for CI, HTML for local, screenshots on failure, video on retry
- **Starter e2e tests:** Three test pattern files (`auth.spec.ts`, `smoke.spec.ts`, `forms.spec.ts`) in `frontend/tests/e2e/` — Claude adapts to actual app during build
- **Accessibility testing:** `@axe-core/playwright` integration in smoke tests for WCAG compliance checks
- **RBAC foundation:** `supabase/migrations/00000000000001_rbac.sql` creates `roles` and `user_roles` tables with 4 default roles (admin, manager, member, viewer)
- **RBAC middleware:** `backend/middleware/rbac.py` with `require_role()` FastAPI dependency for protected endpoints
- **useRole composable:** `frontend/composables/useRole.ts` with `hasRole()`, `isAdmin()`, `isManager()` for role-aware UI
- **RBAC RLS policies:** Row Level Security on `roles` (authenticated read, admin modify) and `user_roles` (own read, admin manage all) tables
- **Dev user admin role:** Bootstrap assigns admin role to `dev@sprout.local` after RBAC migration
- **RBAC pipeline check:** Verifies `roles` table, RBAC middleware, and useRole composable exist at Team+ gates
- **GitHub Actions workflow:** Optional `deploy.yml` for CI/CD with Vercel (`--with-github-actions` flag)

### Changed
- **Deploy gates:** Team gate now requires `ui-tests` and `rbac-check`; all gates include `cloud` config section
- **Deploy state:** Added `cloud` object tracking provider, deploy URL, Supabase project ref
- **Pipeline:** Added RBAC verification stage and cloud deploy stage (triggered by `DEPLOY_TARGET=cloud`)
- **Bootstrap:** Now creates RBAC migration, middleware, composable, Playwright config, and starter tests
- **Architecture diagram:** Updated to show Vercel hosting both frontend SSR and FastAPI serverless
- **Tech stack:** Added hosting sections for Vercel and Supabase Cloud
- **Install script:** Copies cloud deployment scripts alongside existing toolkit files
- **Gitignore:** Added `.vercel/` and `.env.production`
- **Manual:** Added 2 new slides (Cloud Deployment, Roles & Permissions), updated to version 1.5 with 22 slides

## [v1.1.0] — 2026-03-14

### Added
- **Discovery mode:** Claude asks 2-3 rounds of clickable questions before building greenfield projects, producing a structured brief for approval
- **Session persistence:** Auto-checkpoint on session end (`.claude/session/latest.json`), file-log tracking on every edit, crash recovery with resume offer on next session start
- **Gate-aware deploy pipeline:** `run-pipeline.sh` accepts `mvp|team|production` argument and runs only the stages required for that gate level
- **Security scan script:** Standalone `security-scan.sh` wrapping gitleaks + secret pattern detection
- **Two-part error messages:** Every block message now shows what was blocked AND what Claude will do instead (`friendly_block_with_action()`)
- **Secret type detection:** Pre-write guard identifies specific secret types (AWS key, GitHub token, JWT, etc.) in block messages
- **6 new hook detections:** Unsafe CORS (`allow_origins=["*"]`), missing RLS on CREATE TABLE, unindexed foreign keys, console.log blocking in deploy mode (excluding test files), missing error handling in route handlers, `SELECT *` without `.limit()`
- **Configurable smoke test pages:** `SMOKE_PAGES` environment variable for custom page paths
- **Opus reviewer timeout:** 5-minute timeout with `OPUS_TIMEOUT` override; `--allowedTools` flag auto-detection
- **Packaging script:** `scripts/package.sh` builds distributable zip with correct `managers-agent-fleet/` top-level directory
- **Manual updates:** 3 new slides (Start With Discovery, Deploy Flow, Tips for Working With Claude), offline fonts, version 1.4

### Changed
- **Token efficiency (~56% reduction):** Compressed CLAUDE.md, all 5 rules files, and global ~/.claude/CLAUDE.md — removed narration examples, tone headers, redundant code blocks, and duplicated rules
- **CLAUDE.md restructured:** Discovery Mode, Build Mode, Deploy Mode, Session Lifecycle sections; architectural rules deduplicated to rules files; sub-agent section replaced with pointer
- **Deploy pipeline refactored:** Mode switching via trap (auto-restores build mode on exit), tmp directory cleanup, stage-aware parallel execution
- **Stop hook streamlined:** All mid-process stderr removed; only final summary line printed; details go to audit.log only
- **Manual installation instructions:** Clarified that unzip creates `managers-agent-fleet/` subdirectory; added explanation of automatic cleanup
- **Gitignore entries:** Streamlined comments in install.sh gitignore block

### Fixed
- **Zip structure:** Zip now extracts into `managers-agent-fleet/` subdirectory (was extracting flat into project root, mismatching install.sh expectations)
- **deploy-state.json:** Nulled out contradictory populated fields (`deployed_at`, `deployed_by`, `deployed_version`) that conflicted with `deployment_status: "not-deployed"`
- **Opus reviewer:** Fixed `--allowedTools` flag check (now auto-detects if claude CLI supports it)

## [v1.0.0] — 2026-03-14
