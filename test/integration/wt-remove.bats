#!/usr/bin/env bats

# Integration tests for bin/wt-remove

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
# Helper to create a removable worktree
# =============================================================================

create_removable_worktree() {
    local branch_name="${1:-feature-remove}"
    create_branch "$REPO" "$branch_name"
    local wt_path="$WT_WORKTREES_BASE/$branch_name"
    create_worktree "$REPO" "$wt_path" "$branch_name"
    echo "$wt_path"
}

# =============================================================================
# Basic removal tests
# =============================================================================

@test "wt-remove -y removes worktree directory and unregisters from git" {
    local wt_path
    wt_path=$(create_removable_worktree "to-remove")

    run "$TEST_HOME/.wt/bin/wt-remove" -y "$wt_path"
    assert_success
    assert [ ! -d "$wt_path" ]

    # Verify worktree is also unregistered from git
    run git -C "$REPO" worktree list
    assert_success
    refute_output --partial "to-remove"
}

# =============================================================================
# Main repository protection tests
# =============================================================================

@test "wt-remove refuses to remove main repo" {
    run "$TEST_HOME/.wt/bin/wt-remove" -y "$WT_MAIN_REPO_ROOT"
    assert_failure
    assert_output --regexp "(Cannot remove|main repo|main repository)"
    # Main repo should still exist
    assert [ -d "$REPO" ]
}

# =============================================================================
# Currently linked worktree tests
#
# When removing the currently linked worktree, wt-remove should:
# 1. Warn the user about the linked worktree
# 2. Auto-switch symlink to main repo after removal
# =============================================================================

@test "wt-remove warns when removing currently linked worktree" {
    local wt_path
    wt_path=$(create_removable_worktree "linked-wt")

    # Link to this worktree
    ln -sf "$wt_path" "$WT_ACTIVE_WORKTREE"

    run "$TEST_HOME/.wt/bin/wt-remove" -y "$wt_path"
    assert_success
    assert_output --partial "currently linked"
    # Worktree should be removed
    assert [ ! -d "$wt_path" ]
    # Symlink should either be removed or repointed (not pointing to removed worktree)
    if [ -L "$WT_ACTIVE_WORKTREE" ]; then
        local target
        target=$(readlink "$WT_ACTIVE_WORKTREE")
        [[ "$target" != "$wt_path" ]]
    fi
}

@test "wt-remove auto-switches symlink to main repo when removing linked worktree" {
    local wt_path
    wt_path=$(create_removable_worktree "auto-switch")

    # Link to this worktree
    ln -sf "$wt_path" "$WT_ACTIVE_WORKTREE"

    run "$TEST_HOME/.wt/bin/wt-remove" -y "$wt_path"
    assert_success

    # Symlink should now point to main repo or not exist
    if [ -L "$WT_ACTIVE_WORKTREE" ]; then
        local target
        target=$(readlink "$WT_ACTIVE_WORKTREE")
        assert_equal "$target" "$REPO"
    fi
}

# =============================================================================
# Uncommitted changes tests
#
# SAFETY DESIGN: The -y flag skips the normal "are you sure?" confirmation,
# but worktrees with uncommitted changes ALWAYS require explicit confirmation.
# This is intentional to prevent accidental data loss - even automated scripts
# must acknowledge they're deleting uncommitted work.
# =============================================================================

@test "wt-remove -y still prompts for dirty worktrees and removes after confirmation" {
    local wt_path
    wt_path=$(create_removable_worktree "dirty-wt")

    # Make the worktree dirty
    echo "uncommitted" >> "$wt_path/file.txt"

    # Declining should preserve the worktree
    run bash -c 'echo "n" | "'"$TEST_HOME/.wt/bin/wt-remove"'" -y "'"$wt_path"'"'
    assert_output --partial "uncommitted changes"
    assert [ -d "$wt_path" ]

    # Confirming should remove the worktree
    run bash -c 'echo "y" | "'"$TEST_HOME/.wt/bin/wt-remove"'" -y "'"$wt_path"'"'
    assert_success
    assert_output --partial "uncommitted changes"
    assert [ ! -d "$wt_path" ]
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-remove fails for non-existent path" {
    run "$TEST_HOME/.wt/bin/wt-remove" -y "/nonexistent/worktree/path"
    assert_failure
    assert_output --partial "not found"
}

@test "wt-remove fails for path that is not a worktree" {
    local not_worktree="$BATS_TEST_TMPDIR/not-a-worktree"
    mkdir -p "$not_worktree"

    run "$TEST_HOME/.wt/bin/wt-remove" -y "$not_worktree"
    assert_failure
    assert_output --partial "not a git repository or worktree"
    # Directory should not have been deleted
    assert [ -d "$not_worktree" ]
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-remove -h/--help shows help" {
    run "$TEST_HOME/.wt/bin/wt-remove" -h
    assert_success
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-remove" --help
    assert_success
    assert_output --partial "Usage:"
}

# =============================================================================
# --merged mode tests
# =============================================================================

@test "wt-remove --merged removes merged branch worktrees" {
    # Create a branch, merge it, then create worktree
    (cd "$REPO" && git checkout -b merged-branch && git checkout main && git merge merged-branch) >/dev/null 2>&1
    local wt_path="$WT_WORKTREES_BASE/merged-branch"
    create_worktree "$REPO" "$wt_path" "merged-branch"

    run "$TEST_HOME/.wt/bin/wt-remove" --merged -y
    assert_success
    # Merged worktree should be removed
    assert [ ! -d "$wt_path" ]
}

@test "wt-remove --merged excludes main repo" {
    # Even if main is on a merged branch, should never remove it
    run "$TEST_HOME/.wt/bin/wt-remove" --merged -y
    assert_success
    # Main repo should still exist
    assert [ -d "$REPO" ]
}

@test "wt-remove --merged preserves unmerged branch worktrees" {
    # Create an unmerged branch worktree
    create_branch "$REPO" "unmerged-feature"
    local wt_path="$WT_WORKTREES_BASE/unmerged-feature"
    create_worktree "$REPO" "$wt_path" "unmerged-feature"

    # Add unique commit to make it unmerged
    (cd "$wt_path" && echo "unique" > unique.txt && git add . && git commit -m "Unique commit") >/dev/null 2>&1

    run "$TEST_HOME/.wt/bin/wt-remove" --merged -y
    assert_success
    # Unmerged worktree should still exist
    assert [ -d "$wt_path" ]
}

# =============================================================================
# Multiple worktree removal tests
# =============================================================================

@test "wt-remove handles multiple removals sequentially" {
    local wt1 wt2
    wt1=$(create_removable_worktree "multi-1")
    wt2=$(create_removable_worktree "multi-2")

    run "$TEST_HOME/.wt/bin/wt-remove" -y "$wt1"
    assert_success
    assert [ ! -d "$wt1" ]

    run "$TEST_HOME/.wt/bin/wt-remove" -y "$wt2"
    assert_success
    assert [ ! -d "$wt2" ]
}
