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
    local branch=$(cd "$WT_WORKTREES_BASE/existing-branch" && git branch --show-current)
    assert_equal "$branch" "existing-branch"
}

@test "wt-add with path creates worktree at specified path" {
    create_branch "$REPO" "feature-path"
    local custom_path="$WT_WORKTREES_BASE/custom-location"

    run "$TEST_HOME/.wt/bin/wt-add" "$custom_path" feature-path
    assert_success
    assert_is_worktree "$custom_path"
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
    local branch=$(cd "$WT_WORKTREES_BASE/new-feature" && git branch --show-current)
    assert_equal "$branch" "new-feature"
}

@test "wt-add -b preserves uncommitted changes in main repo" {
    # Make the main repo dirty
    make_repo_dirty "$REPO"
    local original_content
    original_content=$(cat "$REPO/file.txt")

    run "$TEST_HOME/.wt/bin/wt-add" -b preserve-test
    assert_success

    # Original repo should still have the uncommitted change
    local current_content
    current_content=$(cat "$REPO/file.txt")
    assert_equal "$current_content" "$original_content"
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
# Cleanup/state restoration tests
# =============================================================================

@test "wt-add restores original branch on failure" {
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

@test "wt-add -b restores original branch on failure" {
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
