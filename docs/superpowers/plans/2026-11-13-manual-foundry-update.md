# Manual Transactional Foundry Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-shot manual update command that installs an explicit Foundry VTT 14 build or infers it from a temporary release URL without risking the existing application or user data.

**Architecture:** Keep normal startup in `run.sh`, move update-specific validation, download, staging, promotion, and rollback functions into `update.sh`, and add a small PID 1 launch supervisor that confirms the new server becomes reachable before deleting the previous application. Updates are staged on the same `/config` filesystem, promoted by rename, and tracked with non-secret request state for idempotence.

**Tech Stack:** Bash, jq, curl, unzip/zipinfo, Home Assistant add-on YAML, felddy/foundryvtt 14 image.

**Spec:** `docs/superpowers/specs/2026-11-13-manual-foundry-update-design.md`

## Global Constraints

- Updates are manual and one-shot; never search for or install the latest release during ordinary startup.
- Accept only versions matching `14.<build>`.
- Never delete or move `/config/Data`, `/config/Config`, `/config/Backups`, or `/config/Logs`.
- A failed download, validation, extraction, promotion, or first launch must leave or restore the previous application.
- Never log credentials, license keys, administrator keys, or signed release URLs.
- `force_download` continues to mean reinstall the version supplied by the container image.
- Do not install or manage Docker manually on the Home Assistant host.
- Preserve UID/GID `1000:1000` for the persistent application.
- Version and URL together mean “download from this URL and require this exact version.”
- URL without a version means infer the version from the archive; version without URL means resolve the exact release with Foundry credentials.

## Review Focus

- An expired or HTTP-error signed URL must fail before promotion and preserve the current application; Task 2 tests this.
- A valid ZIP whose internal version differs from `foundry_target_version` must be rejected; Task 1 tests this.
- Both Node.js and Linux Foundry archive layouts must stage into the same `resources/app` shape; Task 1 tests this.
- Leaving `install_target_version: true` after success must not download or reinstall again; Task 2 tests request idempotence.
- A promoted application that exits or never opens port 30000 must restore the previous application and forward shutdown signals correctly; Task 3 tests this.

---

### Task 1: Archive inspection and staging library

**Files:**
- Create: `foundryvtt/update.sh`
- Create: `tests/test_update_archive.sh`
- Create: `tests/helpers/make_foundry_fixture.sh`

**Interfaces:**
- Produces: `validate_foundry_version VERSION`, `archive_foundry_version ARCHIVE`, `stage_foundry_archive ARCHIVE EXPECTED_VERSION DESTINATION`.
- `archive_foundry_version` prints `generation.build`.
- `stage_foundry_archive` prints the validated version and creates `DESTINATION/resources/app`.

- [ ] **Step 1: Create fixture helper**

Implement `make_foundry_fixture.sh OUTPUT VERSION LAYOUT`, where `LAYOUT` is `node` or `linux`, producing minimal ZIPs containing `package.json` and `main.mjs` in the corresponding upstream layout.

- [ ] **Step 2: Write failing archive tests**

Cover: `14.370` accepted; malformed versions rejected; generation 15 rejected; target/archive mismatch rejected; malformed ZIP rejected; Node.js and Linux layouts both produce `resources/app/package.json` and `resources/app/main.mjs`.

- [ ] **Step 3: Run archive tests and verify failure**

Run: `bash tests/test_update_archive.sh`  
Expected: FAIL because `foundryvtt/update.sh` and its functions do not exist.

- [ ] **Step 4: Implement the archive functions**

Use `unzip -p` plus jq to read `.release.generation` and `.release.build`; accept only `^14\.[0-9]+$`. Extract to a caller-provided empty directory and normalize both upstream archive layouts without touching the live application.

- [ ] **Step 5: Run archive tests and verify success**

Run: `bash tests/test_update_archive.sh`  
Expected: all archive cases PASS.

- [ ] **Step 6: Commit**

```bash
git add foundryvtt/update.sh tests/test_update_archive.sh tests/helpers/make_foundry_fixture.sh
git commit -m "test: define safe Foundry archive staging"
```

### Task 2: One-shot request resolution and transactional promotion

**Files:**
- Modify: `foundryvtt/update.sh`
- Create: `tests/test_update_transaction.sh`

**Interfaces:**
- Consumes: Task 1 archive functions.
- Produces: `perform_requested_update TARGET_VERSION RELEASE_URL USERNAME PASSWORD CONFIG_ROOT`.
- Returns success with no change when the current installation or completed request already matches.
- Writes pending state under `/config/.foundry-update/`, candidate data under `/config/foundry_app.candidate`, and previous application under `/config/foundry_app.previous`.

- [ ] **Step 1: Write failing request and transaction tests**

Cover the four selection rules: version+URL exact match; version+credentials; URL-only inference; neither rejected. Also cover expired URL, target mismatch, interrupted extraction, failed rename, completed-request idempotence, and preservation of sentinel files in `Data`, `Config`, `Backups`, and `Logs`.

- [ ] **Step 2: Run transaction tests and verify failure**

Run: `bash tests/test_update_transaction.sh`  
Expected: FAIL because `perform_requested_update` is undefined.

- [ ] **Step 3: Implement request fingerprinting**

Add helpers that hash only non-secret request state. A target-based request uses the target version; URL-only uses a SHA-256 digest of the URL without persisting or logging the URL itself. Store completed and pending JSON state with version and fingerprint.

- [ ] **Step 4: Implement URL and credential resolution**

For a supplied URL, download with curl using fail/location/silent error handling into a unique temporary file. For target+credentials, call the image’s existing `authenticate.js` and `get_release_url.js` for that exact target, delete the cookie jar on every exit path, and never echo secrets or the resolved signed URL.

- [ ] **Step 5: Implement staging and promotion**

Validate before promotion, stage on `/config`, apply `1000:1000`, rename the live application to `foundry_app.previous`, and rename the candidate to `foundry_app`. Write pending state only after successful promotion. On every pre-launch error, restore the previous directory if promotion began.

- [ ] **Step 6: Run transaction tests and verify success**

Run: `bash tests/test_update_transaction.sh`  
Expected: all request, failure, idempotence, and preservation cases PASS.

- [ ] **Step 7: Commit**

```bash
git add foundryvtt/update.sh tests/test_update_transaction.sh
git commit -m "feat: stage manual Foundry updates transactionally"
```

### Task 3: First-launch confirmation and rollback supervisor

**Files:**
- Create: `foundryvtt/launch.sh`
- Modify: `foundryvtt/update.sh`
- Create: `tests/test_update_launch.sh`

**Interfaces:**
- Consumes: pending/previous state produced by Task 2.
- Produces: `confirm_pending_update CONFIG_ROOT`, `rollback_pending_update CONFIG_ROOT`, and executable `launch.sh`.
- `launch.sh` starts the upstream entrypoint as `node:node`, polls TCP port 30000 for at most 180 seconds, forwards TERM/INT, and returns the child exit code.

- [ ] **Step 1: Write failing launch tests**

Use fake entrypoints for: port becomes reachable; child exits before health; timeout without health; TERM forwarding. Assert success removes the previous application and writes completed state; each failure restores the previous application and leaves all data directories unchanged.

- [ ] **Step 2: Run launch tests and verify failure**

Run: `bash tests/test_update_launch.sh`  
Expected: FAIL because `launch.sh` and confirmation/rollback functions do not exist.

- [ ] **Step 3: Implement confirmation and rollback state transitions**

On confirmed health, delete `foundry_app.previous`, move pending state to completed state, and retain the downloaded release cache. On failure, remove the failed candidate/live application, restore `foundry_app.previous`, and clear pending state while preserving an error marker for logs.

- [ ] **Step 4: Implement the launch supervisor**

Start the upstream entrypoint in the background, use Bash TCP probing against `127.0.0.1:30000`, forward TERM/INT exactly once, wait for the child, and invoke confirmation or rollback only when pending state exists. Normal startups remain a transparent child-process wrapper.

- [ ] **Step 5: Run launch tests and verify success**

Run: `bash tests/test_update_launch.sh`  
Expected: all health, exit, timeout, rollback, and signal cases PASS.

- [ ] **Step 6: Commit**

```bash
git add foundryvtt/launch.sh foundryvtt/update.sh tests/test_update_launch.sh
git commit -m "feat: roll back failed Foundry update launches"
```

### Task 4: Add-on integration and user-facing configuration

**Files:**
- Modify: `foundryvtt/config.yaml`
- Modify: `foundryvtt/Dockerfile`
- Modify: `foundryvtt/run.sh`
- Modify: `foundryvtt/README.md`
- Modify: `foundryvtt/DOCS.md`
- Modify: `foundryvtt/CHANGELOG.md`
- Modify: `README.md`
- Modify: `HAOS.md`

**Interfaces:**
- Consumes: `perform_requested_update` and `launch.sh`.
- Produces: add-on options `foundry_target_version: str?` and `install_target_version: bool`.

- [ ] **Step 1: Write an integration assertion script**

Add checks to the existing shell tests asserting defaults are empty/false, schema types are correct, Dockerfile copies both new scripts, `run.sh` sources `update.sh`, invokes updates only when requested, and delegates startup to `launch.sh`.

- [ ] **Step 2: Run integration assertions and verify failure**

Run: `bash tests/test_addon_integration.sh`  
Expected: FAIL because the add-on files do not expose the new interface.

- [ ] **Step 3: Update add-on configuration**

Add the two options and schemas, bump the add-on version from `1.1.0` to `1.2.0`, and keep `force_download: false` unchanged.

- [ ] **Step 4: Update image assembly and startup**

Copy/chmod `update.sh` and `launch.sh` in the Dockerfile. In `run.sh`, read the new options, preserve normal installed-version detection, execute the transactional updater before the upstream entrypoint, and use `launch.sh` for startup/rollback supervision.

- [ ] **Step 5: Document the workflow**

Document exact UI steps, the priority of version and URL, URL expiration, credentials fallback, the one-shot/idempotent behavior, generation-14 restriction, backup requirement, rollback behavior, and the distinction from `force_download`.

- [ ] **Step 6: Run integration assertions and verify success**

Run: `bash tests/test_addon_integration.sh`  
Expected: all add-on interface and wiring assertions PASS.

- [ ] **Step 7: Commit**

```bash
git add foundryvtt/config.yaml foundryvtt/Dockerfile foundryvtt/run.sh foundryvtt/README.md foundryvtt/DOCS.md foundryvtt/CHANGELOG.md README.md HAOS.md tests/test_addon_integration.sh
git commit -m "feat: expose one-shot Foundry update controls"
```

### Task 5: Full verification and release readiness

**Files:**
- Modify only if verification reveals a defect in files owned by Tasks 1–4.

**Interfaces:**
- Consumes: complete add-on implementation.
- Produces: verified release candidate for branch `develop`.

- [ ] **Step 1: Run all shell tests**

Run: `for test_file in tests/test_*.sh; do bash "$test_file"; done`  
Expected: every test PASS.

- [ ] **Step 2: Run static checks**

Run: `bash -n foundryvtt/run.sh foundryvtt/update.sh foundryvtt/launch.sh tests/test_*.sh tests/helpers/*.sh`  
Expected: no output and exit 0.

- [ ] **Step 3: Validate YAML**

Run: `ruby -e 'require "yaml"; %w[repository.yaml foundryvtt/config.yaml .github/FUNDING.yml].each { |f| YAML.load_file(f); puts "OK #{f}" }'`  
Expected: one `OK` line per file.

- [ ] **Step 4: Review destructive paths**

Search every `rm`, `mv`, and recursive ownership change. Confirm each resolved target is confined to `foundry_app`, `foundry_app.candidate`, `foundry_app.previous`, `.foundry-update`, or `container_cache`; no command can resolve to `/config` or a user-data directory.

- [ ] **Step 5: Verify repository diff and version documentation**

Run: `git diff --check` and inspect the final diff against the approved spec.  
Expected: no whitespace errors; every spec requirement maps to code, tests, or documentation.

- [ ] **Step 6: Commit verification fixes if needed**

```bash
git add <only-files-corrected-during-verification>
git commit -m "fix: harden transactional Foundry update flow"
```
