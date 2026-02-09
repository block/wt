#!/usr/bin/env bats

# Integration tests for bin/wt-switch

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    # Create test context and load its WT_* variables
    create_test_context "test" "$REPO"
    load_test_context "test"

    # Create a worktree to switch to
    create_branch "$REPO" "feature-1"
    WORKTREE="$WT_WORKTREES_BASE/feature-1"
    create_worktree "$REPO" "$WORKTREE" "feature-1"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic switching tests
# =============================================================================

@test "wt-switch creates symlink pointing to correct target" {
    # Ensure no existing symlink
    rm -f "$WT_ACTIVE_WORKTREE" 2>/dev/null || true

    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE"
    assert_success
    assert [ -L "$WT_ACTIVE_WORKTREE" ]

    local target
    target=$(readlink "$WT_ACTIVE_WORKTREE")
    assert_equal "$target" "$WORKTREE"
}

@test "wt-switch can switch to main repo" {
    rm -f "$WT_ACTIVE_WORKTREE" 2>/dev/null || true

    run "$TEST_HOME/.wt/bin/wt-switch" "$REPO"
    assert_success

    local target
    target=$(readlink "$WT_ACTIVE_WORKTREE")
    assert_equal "$target" "$REPO"
}

@test "wt-switch updates existing symlink" {
    # Create initial symlink to main repo
    ln -s "$REPO" "$WT_ACTIVE_WORKTREE"

    # Switch to worktree
    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE"
    assert_success

    local target
    target=$(readlink "$WT_ACTIVE_WORKTREE")
    assert_equal "$target" "$WORKTREE"
}

@test "wt-switch can switch between worktrees" {
    # Create second worktree
    create_branch "$REPO" "feature-2"
    local worktree2="$WT_WORKTREES_BASE/feature-2"
    create_worktree "$REPO" "$worktree2" "feature-2"

    # Switch to first worktree
    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE"
    assert_success

    # Switch to second worktree
    run "$TEST_HOME/.wt/bin/wt-switch" "$worktree2"
    assert_success

    local target
    target=$(readlink "$WT_ACTIVE_WORKTREE")
    assert_equal "$target" "$worktree2"
}

# =============================================================================
# Safety tests - non-symlink handling
# =============================================================================

@test "wt-switch refuses to overwrite non-symlink file" {
    # Create a regular file instead of symlink
    rm -f "$WT_ACTIVE_WORKTREE" 2>/dev/null || true
    echo "regular file" > "$WT_ACTIVE_WORKTREE"

    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE"
    assert_failure
    assert_output --partial "not a symlink"
}

@test "wt-switch refuses to overwrite non-symlink directory" {
    # Create a regular directory instead of symlink
    rm -rf "$WT_ACTIVE_WORKTREE" 2>/dev/null || true
    mkdir -p "$WT_ACTIVE_WORKTREE/subdir"
    echo "content" > "$WT_ACTIVE_WORKTREE/subdir/file.txt"

    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE"
    assert_failure
    assert_output --partial "not a symlink"

    # Original directory should still exist
    assert [ -d "$WT_ACTIVE_WORKTREE/subdir" ]
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-switch fails for non-existent path" {
    run "$TEST_HOME/.wt/bin/wt-switch" "/nonexistent/path"
    assert_failure
    assert_output --partial "does not exist"
}

@test "wt-switch fails for non-worktree directory" {
    local not_worktree="$BATS_TEST_TMPDIR/not-a-worktree"
    mkdir -p "$not_worktree"

    run "$TEST_HOME/.wt/bin/wt-switch" "$not_worktree"
    assert_failure
    assert_output --partial "not a git"
}

@test "wt-switch fails with empty argument" {
    # Create a known symlink so we can verify it's not modified
    ln -sf "$REPO" "$WT_ACTIVE_WORKTREE"

    run "$TEST_HOME/.wt/bin/wt-switch" "" < /dev/null
    assert_failure

    # Verify symlink was not modified
    local current_target
    current_target=$(readlink "$WT_ACTIVE_WORKTREE")
    assert_equal "$current_target" "$REPO"
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-switch -h/--help shows help" {
    run "$TEST_HOME/.wt/bin/wt-switch" -h
    assert_success
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-switch" --help
    assert_success
    assert_output --partial "Usage:"
}

# =============================================================================
# Path handling tests
# =============================================================================

@test "wt-switch handles paths with trailing slash" {
    rm -f "$WT_ACTIVE_WORKTREE" 2>/dev/null || true

    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE/"
    assert_success
    assert [ -L "$WT_ACTIVE_WORKTREE" ]

    local target
    target=$(readlink "$WT_ACTIVE_WORKTREE")
    assert_equal "$target" "$WORKTREE"
}

# =============================================================================
# State verification tests
# =============================================================================

@test "wt-switch symlink points to correct branch" {
    rm -f "$WT_ACTIVE_WORKTREE" 2>/dev/null || true

    run "$TEST_HOME/.wt/bin/wt-switch" "$WORKTREE"
    assert_success

    local branch
    branch=$(cd "$WT_ACTIVE_WORKTREE" && git branch --show-current)
    assert_equal "$branch" "feature-1"
}
