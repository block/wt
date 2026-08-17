#!/usr/bin/env bats

# Integration tests for bin/wt-add

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo with remote (needed for pull operations)
    REPO=$(create_mock_repo_with_remote "$BATS_TEST_TMPDIR/repo")

    # Create test context and load its WT_* variables
    create_test_context "test" "$REPO"
    load_test_context "test"

    # Override: empty patterns so metadata operations are no-ops in tests
    export WT_METADATA_PATTERNS=""
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Existing branch mode tests
# =============================================================================

@test "wt-add creates worktree for existing branch" {
    # Create a branch first
    create_branch "$REPO" "existing-branch"

    run "$TEST_HOME/.wt/bin/wt-add" existing-branch
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/existing-branch"
    assert_is_adopted "$WT_WORKTREES_BASE/existing-branch"
    local branch=$(cd "$WT_WORKTREES_BASE/existing-branch" && git branch --show-current)
    assert_equal "$branch" "existing-branch"
}

@test "wt-add with path creates worktree at specified path" {
    create_branch "$REPO" "feature-path"
    local custom_path="$WT_WORKTREES_BASE/custom-location"

    run "$TEST_HOME/.wt/bin/wt-add" "$custom_path" feature-path
    assert_success
    assert_is_worktree "$custom_path"
    assert_is_adopted "$custom_path"
    local branch=$(cd "$custom_path" && git branch --show-current)
    assert_equal "$branch" "feature-path"
}

# =============================================================================
# New branch mode tests (-b)
# =============================================================================

@test "wt-add -b creates new branch and worktree" {
    run "$TEST_HOME/.wt/bin/wt-add" -b new-feature
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/new-feature"
    assert_is_adopted "$WT_WORKTREES_BASE/new-feature"
    local branch=$(cd "$WT_WORKTREES_BASE/new-feature" && git branch --show-current)
    assert_equal "$branch" "new-feature"
}

@test "wt-add --branch creates new branch and worktree" {
    run "$TEST_HOME/.wt/bin/wt-add" --branch long-flag-feature
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/long-flag-feature"
    local branch=$(cd "$WT_WORKTREES_BASE/long-flag-feature" && git branch --show-current)
    assert_equal "$branch" "long-flag-feature"
}

@test "wt-add --branch=NAME creates new branch and worktree" {
    run "$TEST_HOME/.wt/bin/wt-add" --branch=eq-long-feature
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/eq-long-feature"
    local branch=$(cd "$WT_WORKTREES_BASE/eq-long-feature" && git branch --show-current)
    assert_equal "$branch" "eq-long-feature"
}

@test "wt-add -b=NAME creates branch NAME, not =NAME" {
    run "$TEST_HOME/.wt/bin/wt-add" -b=eq-short-feature
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/eq-short-feature"
    local branch=$(cd "$WT_WORKTREES_BASE/eq-short-feature" && git branch --show-current)
    assert_equal "$branch" "eq-short-feature"

    # The literally-named "=eq-short-feature" branch must NOT exist
    run git -C "$REPO" show-ref --verify "refs/heads/=eq-short-feature"
    assert_failure
}

@test "wt-add -b never touches a dirty main repo (no stash, no checkout)" {
    # Make the main repo dirty
    make_repo_dirty "$REPO"
    local original_content original_status original_branch
    original_content=$(cat "$REPO/file.txt")
    original_status=$(git -C "$REPO" status --porcelain)
    original_branch=$(git -C "$REPO" branch --show-current)

    run "$TEST_HOME/.wt/bin/wt-add" -b preserve-test
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/preserve-test"

    # Main repo state must be byte-for-byte identical: same file content,
    # same dirty status, same branch, and no stash entry was ever created
    assert_equal "$(cat "$REPO/file.txt")" "$original_content"
    assert_equal "$(git -C "$REPO" status --porcelain)" "$original_status"
    assert_equal "$(git -C "$REPO" branch --show-current)" "$original_branch"
    assert_equal "$(git -C "$REPO" stash list)" ""
    refute_output --partial "stash"
}

# =============================================================================
# Path traversal security tests
# =============================================================================

@test "wt-add rejects branch names containing .. (convenience mode)" {
    run "$TEST_HOME/.wt/bin/wt-add" "../bad-branch"
    assert_failure
    assert_output --partial "cannot contain '..'"

    run "$TEST_HOME/.wt/bin/wt-add" "feature/../escape"
    assert_failure
    assert_output --partial "cannot contain '..'"
}

@test "wt-add -b rejects branch names containing .." {
    run "$TEST_HOME/.wt/bin/wt-add" -b "../bad-branch"
    assert_failure
    assert_output --partial "cannot contain '..'"

    run "$TEST_HOME/.wt/bin/wt-add" -b "../../escape"
    assert_failure
    assert_output --partial "cannot contain '..'"
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-add fails for non-existent branch" {
    run "$TEST_HOME/.wt/bin/wt-add" nonexistent-branch-xyz
    assert_failure
    assert [ ! -d "$WT_WORKTREES_BASE/nonexistent-branch-xyz" ]
}

@test "wt-add fails when worktree directory already exists" {
    create_branch "$REPO" "existing-dir"
    mkdir -p "$WT_WORKTREES_BASE/existing-dir"

    run "$TEST_HOME/.wt/bin/wt-add" existing-dir
    assert_failure
    assert_output --partial "already exists"
}

@test "wt-add -b prompts when branch already exists and respects decline" {
    create_branch "$REPO" "already-exists"

    # Record initial state to verify no side effects
    local initial_worktree_count
    initial_worktree_count=$(git -C "$REPO" worktree list | wc -l | tr -d ' ')
    local initial_branch
    initial_branch=$(git -C "$REPO" branch --show-current)

    # Pipe "n" to decline the existing-branch prompt
    run bash -c 'echo "n" | "'"$TEST_HOME/.wt/bin/wt-add"'" -b already-exists'
    assert_failure
    # Verify the detection message was shown (not just the abort)
    assert_output --partial "already exists"
    assert_output --partial "Aborted"

    # Verify worktree directory was NOT created
    assert [ ! -d "$WT_WORKTREES_BASE/already-exists" ]

    # Verify no worktree was registered with git
    local final_worktree_count
    final_worktree_count=$(git -C "$REPO" worktree list | wc -l | tr -d ' ')
    assert_equal "$final_worktree_count" "$initial_worktree_count"

    # Verify main repo stayed on original branch (state restoration)
    local final_branch
    final_branch=$(git -C "$REPO" branch --show-current)
    assert_equal "$final_branch" "$initial_branch"
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-add with no args shows usage" {
    run "$TEST_HOME/.wt/bin/wt-add"
    assert_failure
    assert_output --partial "Usage:"
}

@test "wt-add -h/--help shows usage and exits 0" {
    run "$TEST_HOME/.wt/bin/wt-add" -h
    assert_success
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-add" --help
    assert_success
    assert_output --partial "Usage:"
}

@test "wt-add -y auto-confirms existing-branch prompt non-interactively" {
    create_branch "$REPO" "already-there"

    run bash -c '"'"$TEST_HOME/.wt/bin/wt-add"'" -y -b already-there < /dev/null'
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/already-there"
    local branch=$(cd "$WT_WORKTREES_BASE/already-there" && git branch --show-current)
    assert_equal "$branch" "already-there"
}

@test "wt-add passes git worktree flags through correctly" {
    # Test that wt-add passes recognized git worktree flags through to git
    # Use --lock flag which is a valid git worktree add option
    # Note: Full positional format (path + branch) is required for flag passthrough
    create_branch "$REPO" "locked-branch"
    local wt_path="$WT_WORKTREES_BASE/locked-branch"

    run "$TEST_HOME/.wt/bin/wt-add" "$wt_path" "locked-branch" --lock
    assert_success
    assert [ -d "$wt_path" ]

    # Verify the worktree was actually locked (git worktree list shows locked status)
    run git -C "$REPO" worktree list --porcelain
    assert_output --partial "locked"
}

# =============================================================================
# Branch naming tests
# =============================================================================

@test "wt-add handles branch with forward slashes" {
    # Create a branch with slashes (common pattern)
    (cd "$REPO" && git checkout -b "feature/nested/branch" && git checkout main) >/dev/null 2>&1

    run "$TEST_HOME/.wt/bin/wt-add" "feature/nested/branch"
    assert_success
    # Worktree directory preserves the full branch name with slashes
    assert [ -d "$WT_WORKTREES_BASE/feature/nested/branch" ]
}

@test "wt-add -b handles branch with forward slashes" {
    run "$TEST_HOME/.wt/bin/wt-add" -b "feature/new/branch"
    assert_success
    # Verify worktree was created at the correct path
    assert [ -d "$WT_WORKTREES_BASE/feature/new/branch" ]
}

# =============================================================================
# Main-repo isolation tests
# =============================================================================

@test "wt-add leaves main repo branch untouched on failure" {
    # Get original branch
    local original_branch
    original_branch=$(cd "$REPO" && git branch --show-current)

    # Try to create worktree for nonexistent branch (should fail)
    run "$TEST_HOME/.wt/bin/wt-add" nonexistent-branch-abc
    assert_failure

    # Should still be on original branch
    local current_branch
    current_branch=$(cd "$REPO" && git branch --show-current)
    assert_equal "$current_branch" "$original_branch"
}

@test "wt-add -b leaves main repo branch untouched on failure" {
    # Get original branch
    local original_branch
    original_branch=$(cd "$REPO" && git branch --show-current)

    # Existing branch + EOF on prompt → abort
    create_branch "$REPO" "causes-failure"

    run bash -c '"'"$TEST_HOME/.wt/bin/wt-add"'" -b "causes-failure" < /dev/null'
    assert_failure

    # Should still be on original branch
    local current_branch
    current_branch=$(cd "$REPO" && git branch --show-current)
    assert_equal "$current_branch" "$original_branch"
}

# =============================================================================
# Base-ref / fetch behavior tests
# =============================================================================

# Advance origin/main from a second clone so the local repo's main and
# refs/remotes/origin/main both become stale.
# Usage: advance_origin
advance_origin() {
    (
        git clone "$BATS_TEST_TMPDIR/bare_repo" "$BATS_TEST_TMPDIR/other"
        cd "$BATS_TEST_TMPDIR/other"
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "newer" > newer.txt
        git add newer.txt
        git commit -m "Advance origin"
        git push origin main
    ) >/dev/null 2>&1
}

@test "wt-add -b creates from origin/base, not a stale local base" {
    advance_origin
    local origin_tip stale_local_tip
    origin_tip=$(git -C "$BATS_TEST_TMPDIR/bare_repo" rev-parse main)
    stale_local_tip=$(git -C "$REPO" rev-parse main)
    assert [ "$origin_tip" != "$stale_local_tip" ]

    run "$TEST_HOME/.wt/bin/wt-add" -b fresh-base
    assert_success
    assert_equal "$(git -C "$WT_WORKTREES_BASE/fresh-base" rev-parse HEAD)" "$origin_tip"

    # The local base branch itself is not pulled/moved
    assert_equal "$(git -C "$REPO" rev-parse main)" "$stale_local_tip"
}

@test "wt-add -b with WT_SKIP_PULL=1 skips the fetch" {
    advance_origin
    local stale_tracking_tip
    stale_tracking_tip=$(git -C "$REPO" rev-parse refs/remotes/origin/main)

    run env WT_SKIP_PULL=1 "$TEST_HOME/.wt/bin/wt-add" -b skip-fetch
    assert_success
    assert_output --partial "Skipping git fetch (WT_SKIP_PULL=1)"

    # Created from the last-known origin/main; the tracking ref was not updated
    assert_equal "$(git -C "$WT_WORKTREES_BASE/skip-fetch" rev-parse HEAD)" "$stale_tracking_tip"
    assert_equal "$(git -C "$REPO" rev-parse refs/remotes/origin/main)" "$stale_tracking_tip"
}

@test "wt-add -b warns and falls back when git fetch fails" {
    # Stub timeout(1) so "timeout 30 git fetch ..." fails without running git
    mkdir -p "$BATS_TEST_TMPDIR/stubs"
    printf '#!/usr/bin/env bash\nexit 130\n' > "$BATS_TEST_TMPDIR/stubs/timeout"
    chmod +x "$BATS_TEST_TMPDIR/stubs/timeout"

    local last_known_tip
    last_known_tip=$(git -C "$REPO" rev-parse refs/remotes/origin/main)

    run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" "$TEST_HOME/.wt/bin/wt-add" -b fetch-fails
    assert_success
    assert_output --partial "Fetch failed or timed out"
    assert_is_worktree "$WT_WORKTREES_BASE/fetch-fails"
    assert_equal "$(git -C "$WT_WORKTREES_BASE/fetch-fails" rev-parse HEAD)" "$last_known_tip"
}

@test "wt-add -b works without a remote (creates from local base branch)" {
    local repo2
    repo2=$(create_mock_repo "$BATS_TEST_TMPDIR/no_remote_repo")
    create_test_context "noremote" "$repo2"
    load_test_context "noremote"

    local local_tip
    local_tip=$(git -C "$repo2" rev-parse main)

    run "$TEST_HOME/.wt/bin/wt-add" -b no-remote-feature
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/no-remote-feature"
    assert_equal "$(git -C "$WT_WORKTREES_BASE/no-remote-feature" rev-parse HEAD)" "$local_tip"
}

@test "wt-add -b created branch has no upstream (--no-track)" {
    run "$TEST_HOME/.wt/bin/wt-add" -b untracked-feature
    assert_success

    run git -C "$WT_WORKTREES_BASE/untracked-feature" rev-parse --abbrev-ref --symbolic-full-name "@{upstream}"
    assert_failure

    run git -C "$REPO" config --get "branch.untracked-feature.remote"
    assert_failure
}

@test "wt-add -b respects a user-supplied start point verbatim" {
    create_branch "$REPO" "other-base"
    local other_tip main_tip
    other_tip=$(git -C "$REPO" rev-parse other-base)
    main_tip=$(git -C "$REPO" rev-parse main)
    assert [ "$other_tip" != "$main_tip" ]

    local wt_path="$WT_WORKTREES_BASE/from-other"
    run "$TEST_HOME/.wt/bin/wt-add" -b from-other "$wt_path" other-base
    assert_success
    assert_equal "$(git -C "$wt_path" rev-parse HEAD)" "$other_tip"
}

# =============================================================================
# Seed file tests (WT_SEED_FILES)
# =============================================================================

@test "wt-add seeds configured root files into the new worktree" {
    create_branch "$REPO" "seed-branch"
    echo "7.1.0" > "$REPO/.bazelversion"
    export WT_SEED_FILES=".bazelversion"

    run "$TEST_HOME/.wt/bin/wt-add" seed-branch
    assert_success
    assert [ -f "$WT_WORKTREES_BASE/seed-branch/.bazelversion" ]
    assert_equal "$(cat "$WT_WORKTREES_BASE/seed-branch/.bazelversion")" "7.1.0"
}

@test "wt-add -b seeds gitignored files from main repo" {
    (cd "$REPO" && echo "user.bazelrc" > .gitignore \
        && git add .gitignore && git commit -m "ignore user.bazelrc") >/dev/null 2>&1
    echo "build --config=dev" > "$REPO/user.bazelrc"
    export WT_SEED_FILES="user.bazelrc"

    run "$TEST_HOME/.wt/bin/wt-add" -b seed-new-branch
    assert_success
    assert [ -f "$WT_WORKTREES_BASE/seed-new-branch/user.bazelrc" ]
    assert_equal "$(cat "$WT_WORKTREES_BASE/seed-new-branch/user.bazelrc")" "build --config=dev"
}
