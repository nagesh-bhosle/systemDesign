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

## Exceptions

- **Read-only tasks** (research, exploration, answering questions, running tests) do NOT require a branch
- If the user explicitly says "just commit to main" or "skip the branch", follow their instruction

---

## Hello Interview implementations

When adding or extending a system-design **demo** from Hello Interview (or similar):

1. Read [`.cursor/skills/hello-interview-system-design/SKILL.md`](.cursor/skills/hello-interview-system-design/SKILL.md).
2. Default to the breakdown’s “great” path; expose other named alternatives as `application.yml` flags.
3. Place code in `<problem>-demo/` with Docker, `./start.sh`, and a short original design note (`<Problem>.md`).