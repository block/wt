# Examples

Concrete scenarios for using `wt` in AI agent workflows.

## 1. Create a feature worktree

```bash
# Create worktree with new branch
wt add -b guodong/add-logging

# Enter the worktree
cd /path/printed/by/wt-add

# Work on the feature
# ... make changes, run tests ...

# Commit and push
git add -A
git commit -m "feat: add structured logging to order service"
git push -u origin guodong/add-logging

# Create PR
gh pr create --title "Add structured logging" --body "..."
```

## 2. Parallel subagents

Spawn multiple subagents, each working in their own worktree:

```
# Parent agent spawns 3 subagents in parallel:

Subagent 1:
  wt add -b guodong/refactor-auth
  cd <worktree-path>
  # ... refactor auth module ...
  git commit -m "refactor: extract auth middleware"

Subagent 2:
  wt add -b guodong/add-tests
  cd <worktree-path>
  # ... write tests ...
  git commit -m "test: add integration tests for order flow"

Subagent 3:
  wt add -b guodong/fix-docs
  cd <worktree-path>
  # ... update documentation ...
  git commit -m "docs: update API reference"
```

After all subagents complete, the parent reviews each worktree's changes.

## 3. Cleanup after PR merge

```bash
# See what's out there
wt list -v

# Remove all worktrees whose branches have been merged
wt remove --merged

# Also delete the git branches
wt remove --merged -b

# Skip dirty worktrees (don't prompt)
wt remove --merged --on-dirty=skip -b
```

## 4. Review a PR in a worktree

```bash
# Fetch the PR branch
git fetch origin pull/1234/head:pr-1234-review

# Create worktree for the PR branch
wt add pr-1234-review

# Enter and test
cd <worktree-path>
# ... run tests, inspect code ...

# Clean up when done
wt remove pr-1234-review -b
```

## 5. Multi-repo context switch

```bash
# Check current context
wt list
# [Context: java]  ...

# Switch to iOS repo
wt context ios
wt list
# [Context: ios]  ...

# Work on iOS, then switch back
wt context java
```
