# Agent Instructions — systemDesign repo

## Mandatory Git Workflow

**Every** task that involves code changes (new files, edits, deletions) in this repository **MUST** follow this workflow. No exceptions.

### 1. Create a new branch before making any changes

Before writing, editing, or deleting any file, create and switch to a new branch:

```
git checkout main
git pull origin main
git checkout -b feature/<short-descriptive-topic>
```

- Branch name format: `feature/<topic>` (e.g., `feature/add-sync-service`, `feature/fix-chunk-upload`)
- Use kebab-case for the topic
- Never commit directly to `main`

### 2. Make changes and build

- Make all code changes on the feature branch
- **Before committing**, verify the project builds successfully:

```
cd dropbox-demo && ./mvnw clean compile
```

- If the build fails, fix the errors before committing
- Only proceed to commit once the build passes

### 3. Commit

- Commit with a clear, descriptive commit message (imperative mood, e.g., "Add sync service with SSE support")
- Stage and commit logically related changes together

```
git add <files>
git commit -m "<description>"
```

### 4. Push the feature branch to remote

```
git push -u origin feature/<topic>
```

### 5. Ask the user before merging

After all changes are complete and pushed, **stop and ask the user**:

> ✅ All changes are done and pushed to `feature/<topic>`.
> Should I merge this into `main` and push to remote?

**Do NOT merge without explicit confirmation from the user.**

### 6. Merge to main and push (only after user says yes)

```
git checkout main
git pull origin main
git merge feature/<topic>
git push origin main
```

### 7. Clean up (optional)

After a successful merge, offer to delete the feature branch:

```
git branch -d feature/<topic>
git push origin --delete feature/<topic>
```

---

## Rules Summary

| Step | Action | Automated? |
|------|--------|------------|
| 1 | Create `feature/<topic>` branch | ✅ Automatic |
| 2 | Make changes + **build** (`./mvnw clean compile`) | ✅ Automatic |
| 3 | Commit | ✅ Automatic |
| 4 | Push feature branch to remote | ✅ Automatic |
| 5 | Ask user: "Should I merge to main?" | ⏸️ Wait for user |
| 6 | Merge to main + push | ✅ Only after user confirms |
| 7 | Delete feature branch | ✅ After merge, offer to clean up |

## What NOT to do

- ❌ Never commit directly to `main`
- ❌ Never merge without asking the user first
- ❌ Never force-push to `main`
- ❌ Never skip the branch step, even for "small" changes
- ❌ Never push to `main` without merging through the workflow
- ❌ Never create a new project without `start.sh` and `stop.sh`

## Exceptions

- **Read-only tasks** (research, exploration, answering questions, running tests) do NOT require a branch
- If the user explicitly says "just commit to main" or "skip the branch", follow their instruction

---

## Local scratch projects (never commit)

- `../local-projects/` (sibling of this repo, e.g. `local-projects/color-corrector/`) is **private scratch**: personal experiments, photos, and one-off tools.
- NEVER `git add`, commit, or push anything under `local-projects/`. It lives outside this repo, and the root `.gitignore` (`ds-algo/.gitignore`) also excludes it in case the parent ever becomes a repo.
- Launcher entries may *reference* a local project by relative path (like `color-corrector` does), but the project's files themselves must stay uncommitted.

---

## New projects: `start.sh` and `stop.sh` (MANDATORY)

Every time a **new project** (demo, service, lab, app, etc.) is created in this repository,
the LLM **must** add two one-click scripts at the project root:

- `start.sh` — one-click **start**: builds/launches the application and every related
  service it depends on (databases, caches, message brokers, containers, etc.), waits for
  readiness, and prints the URLs to open.
- `stop.sh` — one-click **stop**: shuts down the application and all related services
  started by `start.sh`, and cleans up (containers/networks/temp files where applicable).

Rules:

1. Both scripts are **required** for every new project — no exceptions.
2. `start.sh` must be idempotent (safe to run repeatedly) and must not require manual
   extra steps after it finishes.
3. `stop.sh` must clean up everything `start.sh` created, so a fresh `start.sh` afterwards
   works from a clean slate.
4. Make them executable (`chmod +x start.sh stop.sh`).
5. If the project is a sub-folder (e.g. `dropbox-demo/`, `booking-demo/`), put the scripts
   inside that project folder.
6. Containerized projects should delegate to `docker compose up -d` / `docker compose down`
   (or the project's own compose file) inside the scripts.
7. Add a short comment at the top of each script describing what it starts/stops.

Example (containerized project):

```bash
#!/usr/bin/env bash
# start.sh — start <project> app + its database/cache services
set -euo pipefail
cd "$(dirname "$0")"
docker compose up -d --build
echo "App ready at http://localhost:8080"
```

```bash
#!/usr/bin/env bash
# stop.sh — stop <project> app + its database/cache services
set -euo pipefail
cd "$(dirname "$0")"
docker compose down
```
