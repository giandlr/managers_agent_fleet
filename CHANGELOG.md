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
