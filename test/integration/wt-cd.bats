#!/usr/bin/env bats

# Integration tests for bin/wt-cd

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    # Create test context and load its WT_* variables
    create_test_context "test" "$REPO"
    load_test_context "test"

    # Create a worktree to navigate to
    create_branch "$REPO" "feature-cd"
    WORKTREE="$WT_WORKTREES_BASE/feature-cd"
    create_worktree "$REPO" "$WORKTREE" "feature-cd"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic functionality tests
# =============================================================================

@test "wt-cd outputs clean path usable with cd" {
    # Verify stdout contains exactly the worktree path
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$WORKTREE"
    assert_success
    assert_output "$WORKTREE"
    # Output must be a single line (clean for command substitution)
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    assert_equal "$line_count" "1"

    # Verify the path actually works with cd
    run bash -c "cd '$output' && pwd"
    assert_success
    assert_output "$WORKTREE"
}

@test "wt-cd outputs main repo path to stdout" {
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$REPO"
    assert_success
    assert_output "$REPO"
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-cd fails for non-existent path" {
    run "$TEST_HOME/.wt/bin/wt-cd" "/nonexistent/path/xyz"
    assert_failure
    assert_output --partial "not found"
}

@test "wt-cd fails for non-worktree directory" {
    local not_worktree="$BATS_TEST_TMPDIR/not-a-worktree"
    mkdir -p "$not_worktree"

    run "$TEST_HOME/.wt/bin/wt-cd" "$not_worktree"
    assert_failure
    assert_output --partial "not a git"
}

@test "wt-cd fails with empty argument" {
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "" < /dev/null
    assert_failure
    # No path should be written to stdout
    assert_output ""
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-cd -h/--help shows help" {
    run "$TEST_HOME/.wt/bin/wt-cd" -h
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-cd" --help
    assert_output --partial "Usage:"
}

# =============================================================================
# Path resolution tests
# =============================================================================

@test "wt-cd handles paths with trailing slash" {
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$WORKTREE/"
    assert_success
    # Should output path (normalized without trailing slash)
    assert_output "$WORKTREE"
}

# =============================================================================
# Multiple worktrees tests
# =============================================================================

@test "wt-cd can navigate to different worktrees" {
    # Create second worktree
    create_branch "$REPO" "feature-cd-2"
    local worktree2="$WT_WORKTREES_BASE/feature-cd-2"
    create_worktree "$REPO" "$worktree2" "feature-cd-2"

    # Navigate to first
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$WORKTREE"
    assert_success
    assert_output "$WORKTREE"

    # Navigate to second
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$worktree2"
    assert_success
    assert_output "$worktree2"

    # Navigate to main
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$REPO"
    assert_success
    assert_output "$REPO"
}

# =============================================================================
# Symlink resolution tests
# =============================================================================

@test "wt-cd works when called through symlinked path" {
    # Create symlink to worktree
    local symlink_path="$BATS_TEST_TMPDIR/symlinked-wt"
    ln -s "$WORKTREE" "$symlink_path"

    # wt-cd should still work with the worktree
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$WORKTREE"
    assert_success
    assert_output "$WORKTREE"
}

# =============================================================================
# Usability with shell cd
# =============================================================================

@test "wt-cd handles worktree with spaces in path" {
    # Create worktree with spaces
    create_branch "$REPO" "feature-spaces"
    local wt_spaces="$WT_WORKTREES_BASE/feature with spaces"
    mkdir -p "$(dirname "$wt_spaces")"
    create_worktree "$REPO" "$wt_spaces" "feature-spaces"

    # Use --separate-stderr to verify stdout is ONLY the path (clean for command substitution)
    run --separate-stderr "$TEST_HOME/.wt/bin/wt-cd" "$wt_spaces"
    assert_success
    # stdout should be exactly the path, nothing else
    assert_output "$wt_spaces"

    # Verify stdout is a single line (no extra content)
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    assert_equal "$line_count" "1"

    # Verify the path works with cd command substitution
    run bash -c "cd '$output' && pwd"
    assert_success
    assert_output "$wt_spaces"
}
