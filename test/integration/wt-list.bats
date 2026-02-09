#!/usr/bin/env bats

# Integration tests for bin/wt-list

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    # Create test context and load its WT_* variables
    create_test_context "test" "$REPO"
    load_test_context "test"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic functionality tests
# =============================================================================

@test "wt-list shows main repo with branch name and [main] indicator" {
    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success

    assert_output --partial "$REPO"
    assert_output --partial "(main)"

    # Verify [main] indicator is on the same line as the repo path
    local main_line
    main_line=$(echo "$output" | grep -F "$REPO" | head -1)
    [[ "$main_line" == *"[main]"* ]] || fail "Expected [main] on same line as repo path, got: $main_line"
    [[ "$main_line" == *"(main)"* ]] || fail "Expected (main) branch on same line as repo path, got: $main_line"
}

# =============================================================================
# Multiple worktrees tests
# =============================================================================

@test "wt-list shows multiple worktrees" {
    # Create a branch and worktree
    create_branch "$REPO" "feature-1"
    local wt_path="$WT_WORKTREES_BASE/feature-1"
    create_worktree "$REPO" "$wt_path" "feature-1"

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success
    assert_output --partial "main"
    assert_output --partial "feature-1"
}

@test "wt-list shows linked indicator for active worktree" {
    # Create a branch and worktree
    create_branch "$REPO" "feature-linked"
    local wt_path="$WT_WORKTREES_BASE/feature-linked"
    create_worktree "$REPO" "$wt_path" "feature-linked"

    # Create symlink to worktree (makes it the "active" worktree)
    ln -s "$wt_path" "$WT_ACTIVE_WORKTREE"

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success

    # Verify branch name appears
    assert_output --partial "feature-linked"

    # Verify [linked] indicator appears
    [[ "$output" == *"[linked]"* ]] || fail "Expected [linked] indicator in output: $output"

    # Ensure [linked] indicator is associated with the correct worktree entry
    local linked_line
    linked_line=$(echo "$output" | grep "feature-linked" | head -1)
    [[ "$linked_line" == *"[linked]"* ]] || fail "Expected [linked] on same line as feature-linked, got: $linked_line"

    # Verify * prefix appears on the linked worktree line
    [[ "$linked_line" == *"*"* ]] || fail "Expected * prefix on linked worktree line, got: $linked_line"

    # Verify main repo does NOT have [linked] indicator
    local main_line
    main_line=$(echo "$output" | grep -F "$REPO" | grep "\[main\]" | head -1)
    [[ "$main_line" != *"[linked]"* ]] || fail "Main repo should not have [linked] indicator"
}

# =============================================================================
# Verbose mode tests (-v)
# =============================================================================

@test "wt-list -v shows dirty indicator for modified repo" {
    # Make the repo dirty
    make_repo_dirty "$REPO"

    run "$TEST_HOME/.wt/bin/wt-list" -v
    assert_success
    assert_output --partial "[dirty]"
}

@test "wt-list -v shows clean repo without dirty indicator" {
    # Repo is clean by default
    run "$TEST_HOME/.wt/bin/wt-list" -v
    assert_success
    # Should not contain [dirty]
    refute_output --partial "[dirty]"
}

@test "wt-list without -v does not show dirty indicator" {
    # Make the repo dirty
    make_repo_dirty "$REPO"

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success
    # Without -v, should not show dirty status
    refute_output --partial "[dirty]"
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-list shows error when WT_MAIN_REPO_ROOT is missing" {
    # Remove context to prevent it from overriding our test variable
    rm -f "$TEST_HOME/.wt/current"

    # Set invalid path
    export WT_MAIN_REPO_ROOT="/nonexistent/path"

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_failure
    assert_output --partial "does not exist"
}

@test "wt-list handles WT_MAIN_REPO_ROOT that is not a git repo" {
    local not_git="$BATS_TEST_TMPDIR/not-a-git-repo"
    mkdir -p "$not_git"

    # Remove context to prevent override
    rm -f "$TEST_HOME/.wt/current"
    export WT_MAIN_REPO_ROOT="$not_git"

    run "$TEST_HOME/.wt/bin/wt-list"
    # Should fail for non-git directory
    assert_failure
    assert_output --partial "not a git"
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-list -h/--help shows usage" {
    run "$TEST_HOME/.wt/bin/wt-list" -h
    assert_success
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-list" --help
    assert_success
    assert_output --partial "Usage:"
}

# =============================================================================
# Edge cases
# =============================================================================

@test "wt-list handles worktree with special characters in path" {
    # Create a branch and worktree with spaces in directory name
    create_branch "$REPO" "feature-spaces"
    local wt_path="$WT_WORKTREES_BASE/feature spaces test"
    mkdir -p "$(dirname "$wt_path")"
    create_worktree "$REPO" "$wt_path" "feature-spaces"

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success
    assert_output --partial "feature-spaces"
}
