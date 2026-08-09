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

### 2. Make changes and commit

- Make all code changes on the feature branch
- Commit with a clear, descriptive commit message (imperative mood, e.g., "Add sync service with SSE support")
- Stage and commit logically related changes together

```
git add <files>
git commit -m "<description>"
```

### 3. Push the feature branch to remote

```
git push -u origin feature/<topic>
```

### 4. Ask the user before merging

After all changes are complete and pushed, **stop and ask the user**:

> ✅ All changes are done and pushed to `feature/<topic>`.
> Should I merge this into `main` and push to remote?

**Do NOT merge without explicit confirmation from the user.**

### 5. Merge to main and push (only after user says yes)

```
git checkout main
git pull origin main
git merge feature/<topic>
git push origin main
```

### 6. Clean up (optional)

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
| 2 | Make changes + commit | ✅ Automatic |
| 3 | Push feature branch to remote | ✅ Automatic |
| 4 | Ask user: "Should I merge to main?" | ⏸️ Wait for user |
| 5 | Merge to main + push | ✅ Only after user confirms |
| 6 | Delete feature branch | ✅ After merge, offer to clean up |

## What NOT to do

- ❌ Never commit directly to `main`
- ❌ Never merge without asking the user first
- ❌ Never force-push to `main`
- ❌ Never skip the branch step, even for "small" changes
- ❌ Never push to `main` without merging through the workflow

## Exceptions

- **Read-only tasks** (research, exploration, answering questions, running tests) do NOT require a branch
- If the user explicitly says "just commit to main" or "skip the branch", follow their instruction