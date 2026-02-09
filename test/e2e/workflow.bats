#!/usr/bin/env bats

# End-to-end workflow tests for wt toolkit

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create a comprehensive mock repo with remote
    REPO=$(create_mock_repo_with_remote "$BATS_TEST_TMPDIR/repo")

    # Add some IDE metadata to the repo
    create_metadata_dirs "$REPO" ".idea" ".ijwb"

    # Create test context and load its WT_* variables
    create_test_context "workflow-test" "$REPO"
    load_test_context "workflow-test"

    # Update .conf directly — scripts re-source wt-common on execution
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea .ijwb"/' "$TEST_HOME/.wt/repos/workflow-test.conf"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Full workflow: Create worktree, switch, work, remove
# =============================================================================

@test "e2e: complete worktree lifecycle" {
    # Step 1: Create a new worktree
    create_branch "$REPO" "feature-lifecycle"
    run "$TEST_HOME/.wt/bin/wt-add" "feature-lifecycle"
    assert_success
    assert [ -d "$WT_WORKTREES_BASE/feature-lifecycle" ]

    # Step 2: Switch to the new worktree
    run "$TEST_HOME/.wt/bin/wt-switch" "$WT_WORKTREES_BASE/feature-lifecycle"
    assert_success
    assert [ -L "$WT_ACTIVE_WORKTREE" ]

    # Step 3: Verify we can work in the worktree via symlink
    local branch
    branch=$(cd "$WT_ACTIVE_WORKTREE" && git branch --show-current)
    assert_equal "$branch" "feature-lifecycle"

    # Step 4: Make some changes
    echo "new feature code" > "$WT_ACTIVE_WORKTREE/feature.txt"
    (cd "$WT_ACTIVE_WORKTREE" && git add . && git commit -m "Add feature") >/dev/null 2>&1

    # Step 5: Switch back to main
    run "$TEST_HOME/.wt/bin/wt-switch" "$REPO"
    assert_success
    branch=$(cd "$WT_ACTIVE_WORKTREE" && git branch --show-current)
    assert_equal "$branch" "main"

    # Step 6: Remove the worktree
    run "$TEST_HOME/.wt/bin/wt-remove" -y "$WT_WORKTREES_BASE/feature-lifecycle"
    assert_success
    assert [ ! -d "$WT_WORKTREES_BASE/feature-lifecycle" ]
}

# =============================================================================
# Multiple worktrees workflow
# =============================================================================

@test "e2e: managing multiple worktrees simultaneously" {
    # Create three worktrees for different tasks
    for branch in hotfix bugfix feature; do
        create_branch "$REPO" "$branch"
        run "$TEST_HOME/.wt/bin/wt-add" "$branch"
        assert_success
    done

    # Verify all exist
    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success
    assert_output --partial "hotfix"
    assert_output --partial "bugfix"
    assert_output --partial "feature"

    # Switch between them
    for branch in hotfix bugfix feature; do
        run "$TEST_HOME/.wt/bin/wt-switch" "$WT_WORKTREES_BASE/$branch"
        assert_success

        local current
        current=$(cd "$WT_ACTIVE_WORKTREE" && git branch --show-current)
        assert_equal "$current" "$branch"
    done

    # Clean up all
    for branch in hotfix bugfix feature; do
        run "$TEST_HOME/.wt/bin/wt-remove" -y "$WT_WORKTREES_BASE/$branch"
        assert_success
    done

    # Only main should remain
    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success
    refute_output --partial "hotfix"
    refute_output --partial "bugfix"
    refute_output --partial "feature"
}

# =============================================================================
# New branch workflow (-b flag)
# =============================================================================

@test "e2e: create new branch and worktree from main" {
    # Step 1: Ensure we're on main with clean state
    cd "$REPO"
    local original_branch
    original_branch=$(git branch --show-current)
    assert_equal "$original_branch" "main"

    # Step 2: Create new branch worktree
    run "$TEST_HOME/.wt/bin/wt-add" -b "new-feature-branch"
    assert_success

    # Step 3: Verify worktree exists and has correct branch
    assert [ -d "$WT_WORKTREES_BASE/new-feature-branch" ]
    local wt_branch
    wt_branch=$(cd "$WT_WORKTREES_BASE/new-feature-branch" && git branch --show-current)
    assert_equal "$wt_branch" "new-feature-branch"

    # Step 4: Main repo should still be on main
    local main_branch
    main_branch=$(cd "$REPO" && git branch --show-current)
    assert_equal "$main_branch" "main"

    # Step 5: Branch should exist in main repo
    run git -C "$REPO" branch --list "new-feature-branch"
    assert_success
    assert_output --partial "new-feature-branch"
}

# =============================================================================
# Context switching workflow
# =============================================================================

@test "e2e: switching between multiple repository contexts" {
    # Create second repository
    REPO2=$(create_mock_repo "$BATS_TEST_TMPDIR/repo2")
    create_test_context "second-repo" "$REPO2"

    # Switch to second context
    run "$TEST_HOME/.wt/bin/wt-context" "second-repo"
    assert_success

    # Verify context changed
    local current
    current=$(cat "$TEST_HOME/.wt/current")
    assert_equal "$current" "second-repo"

    # Load and verify variables (wt_load_context_config reads from ~/.wt/current)
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-context"
    wt_load_context_config
    assert_equal "$WT_MAIN_REPO_ROOT" "$REPO2"

    # Switch back
    run "$TEST_HOME/.wt/bin/wt-context" "workflow-test"
    assert_success
    wt_load_context_config
    assert_equal "$WT_MAIN_REPO_ROOT" "$REPO"
}

# =============================================================================
# Dirty worktree handling
# =============================================================================

@test "e2e: handling uncommitted changes across operations" {
    # Create a worktree
    create_branch "$REPO" "dirty-test"
    run "$TEST_HOME/.wt/bin/wt-add" "dirty-test"
    assert_success

    # Make it dirty
    echo "uncommitted" > "$WT_WORKTREES_BASE/dirty-test/dirty.txt"

    # Switch to it
    run "$TEST_HOME/.wt/bin/wt-switch" "$WT_WORKTREES_BASE/dirty-test"
    assert_success

    # List should show dirty indicator with -v
    run "$TEST_HOME/.wt/bin/wt-list" -v
    assert_success
    assert_output --partial "[dirty]"

    # Remove dirty worktree - requires confirmation even with -y (safety feature)
    # Provide 'y' to confirm removal despite uncommitted changes
    run bash -c 'echo "y" | "'"$TEST_HOME/.wt/bin/wt-remove"'" -y "'"$WT_WORKTREES_BASE/dirty-test"'"'
    assert_success
    # Verify the safety prompt about uncommitted changes was shown
    assert_output --partial "uncommitted changes"
    # Verify worktree was actually removed
    assert [ ! -d "$WT_WORKTREES_BASE/dirty-test" ]
}

# =============================================================================
# Navigation workflow (wt-cd)
# =============================================================================

@test "e2e: navigation between worktrees using wt-cd" {
    # Create multiple worktrees
    create_branch "$REPO" "nav-test-1"
    create_branch "$REPO" "nav-test-2"
    run "$TEST_HOME/.wt/bin/wt-add" "nav-test-1"
    assert_success
    run "$TEST_HOME/.wt/bin/wt-add" "nav-test-2"
    assert_success

    # Navigate to first worktree
    local path1
    path1=$("$TEST_HOME/.wt/bin/wt-cd" "$WT_WORKTREES_BASE/nav-test-1")
    assert_equal "$path1" "$WT_WORKTREES_BASE/nav-test-1"

    # Use path with cd
    cd "$path1"
    assert_equal "$(pwd)" "$WT_WORKTREES_BASE/nav-test-1"

    # Navigate to second worktree
    local path2
    path2=$("$TEST_HOME/.wt/bin/wt-cd" "$WT_WORKTREES_BASE/nav-test-2")
    assert_equal "$path2" "$WT_WORKTREES_BASE/nav-test-2"

    cd "$path2"
    assert_equal "$(pwd)" "$WT_WORKTREES_BASE/nav-test-2"

    # Navigate to main
    local main_path
    main_path=$("$TEST_HOME/.wt/bin/wt-cd" "$REPO")
    assert_equal "$main_path" "$REPO"
}

# =============================================================================
# Symlink consistency
# =============================================================================

@test "e2e: active worktree symlink stays consistent" {
    # Create and switch between multiple worktrees
    local worktrees=()
    for i in 1 2 3; do
        create_branch "$REPO" "consistency-$i"
        run "$TEST_HOME/.wt/bin/wt-add" "consistency-$i"
        assert_success
        worktrees+=("$WT_WORKTREES_BASE/consistency-$i")
    done

    # Switch multiple times
    for wt in "${worktrees[@]}" "$REPO" "${worktrees[@]}"; do
        run "$TEST_HOME/.wt/bin/wt-switch" "$wt"
        assert_success

        # Symlink should always be valid
        assert [ -L "$WT_ACTIVE_WORKTREE" ]

        # Symlink should point to correct target
        local target
        target=$(readlink "$WT_ACTIVE_WORKTREE")
        assert_equal "$target" "$wt"

        # Should be able to navigate through symlink
        assert [ -d "$WT_ACTIVE_WORKTREE" ]
        assert [ -f "$WT_ACTIVE_WORKTREE/file.txt" ]
    done
}

# =============================================================================
# Error recovery
# =============================================================================

@test "e2e: system recovers from failed operations" {
    # Get initial state
    local initial_branch
    initial_branch=$(cd "$REPO" && git branch --show-current)

    # Try to create worktree with invalid branch (should fail)
    run "$TEST_HOME/.wt/bin/wt-add" "nonexistent-branch-xyz"
    assert_failure

    # System should be in consistent state
    local current_branch
    current_branch=$(cd "$REPO" && git branch --show-current)
    assert_equal "$current_branch" "$initial_branch"

    # Should still be able to create valid worktrees
    create_branch "$REPO" "recovery-test"
    run "$TEST_HOME/.wt/bin/wt-add" "recovery-test"
    assert_success
}
