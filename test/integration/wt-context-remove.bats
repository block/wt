#!/usr/bin/env bats

# Integration tests for wt context remove

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repos
    REPO1=$(create_mock_repo "$BATS_TEST_TMPDIR/repo1")
    REPO2=$(create_mock_repo "$BATS_TEST_TMPDIR/repo2")
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic removal tests
# =============================================================================

@test "remove deletes .conf file" {
    create_test_context "to-remove" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "to-remove"
    assert_success

    assert [ ! -f "$TEST_HOME/.wt/repos/to-remove.conf" ]
}

@test "remove shows success message" {
    create_test_context "to-remove" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "to-remove"
    assert_success
    assert_output --partial "Context 'to-remove' removed"
}

@test "remove non-existent context shows error" {
    run "$TEST_HOME/.wt/bin/wt-context" remove -y "nonexistent"
    assert_failure
    assert_output --partial "Context not found"
    assert_output --partial "nonexistent"
}

# =============================================================================
# Git config cleanup tests
# =============================================================================

@test "remove cleans up wt.* git config keys" {
    create_test_context "git-cfg-test" "$REPO1"

    # Set wt.* keys in the repo
    set_wt_git_config "$REPO1" \
        "wt.enabled" "true" \
        "wt.contextName" "git-cfg-test" \
        "wt.worktreesBase" "/some/path" \
        "wt.ideaFilesBase" "/some/other" \
        "wt.baseBranch" "main" \
        "wt.activeWorktree" "/some/link" \
        "wt.metadataPatterns" ".idea .ijwb"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "git-cfg-test"
    assert_success

    # All wt.* keys should be removed
    run git -C "$REPO1" config --local --get wt.enabled
    assert_failure
    run git -C "$REPO1" config --local --get wt.contextName
    assert_failure
    run git -C "$REPO1" config --local --get wt.worktreesBase
    assert_failure
    run git -C "$REPO1" config --local --get wt.ideaFilesBase
    assert_failure
    run git -C "$REPO1" config --local --get wt.baseBranch
    assert_failure
    run git -C "$REPO1" config --local --get wt.activeWorktree
    assert_failure
    run git -C "$REPO1" config --local --get wt.metadataPatterns
    assert_failure
}

# =============================================================================
# ~/.wt/current handling tests
# =============================================================================

@test "remove current context switches to another" {
    create_test_context "ctx-a" "$REPO1"
    create_test_context "ctx-b" "$REPO2"
    echo "ctx-b" > "$TEST_HOME/.wt/current"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "ctx-b"
    assert_success

    # Should switch to the remaining context
    local current
    current=$(cat "$TEST_HOME/.wt/current")
    assert_equal "$current" "ctx-a"
}

@test "remove last context deletes current file" {
    create_test_context "only-ctx" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "only-ctx"
    assert_success

    assert [ ! -f "$TEST_HOME/.wt/current" ]
}

@test "remove non-current context leaves current file unchanged" {
    create_test_context "keep-this" "$REPO1"
    create_test_context "remove-this" "$REPO2"
    echo "keep-this" > "$TEST_HOME/.wt/current"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "remove-this"
    assert_success

    local current
    current=$(cat "$TEST_HOME/.wt/current")
    assert_equal "$current" "keep-this"
}

# =============================================================================
# Confirmation prompt tests
# =============================================================================

@test "remove with -y skips confirmation" {
    create_test_context "skip-confirm" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "skip-confirm"
    assert_success
    assert_output --partial "Context 'skip-confirm' removed"
}

@test "remove with --yes skips confirmation" {
    create_test_context "skip-confirm2" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" remove --yes "skip-confirm2"
    assert_success
    assert_output --partial "Context 'skip-confirm2' removed"
}

@test "remove without -y shows confirmation and respects decline" {
    create_test_context "decline-test" "$REPO1"

    run bash -c 'echo "n" | "'"$TEST_HOME/.wt/bin/wt-context"'" remove "decline-test"'

    # Config file should still exist
    assert [ -f "$TEST_HOME/.wt/repos/decline-test.conf" ]
}

# =============================================================================
# Reverse repo migration tests
# =============================================================================

@test "remove moves main repo back to symlink location" {
    create_test_context "sym-test" "$REPO1"

    # Set up the symlink scenario: active_link -> REPO1 (main repo)
    local active_link="$TEST_HOME/active"
    rm -f "$active_link"
    ln -s "$REPO1" "$active_link"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "sym-test"
    assert_success

    # After remove: active_link should be a real directory (not a symlink)
    assert [ ! -L "$active_link" ]
    assert [ -d "$active_link" ]
    # The original main repo location should no longer exist
    assert [ ! -e "$REPO1" ]
    # The moved directory should be a valid git repo
    assert [ -d "$active_link/.git" ]
}

@test "remove with mismatched symlink removes symlink but does not move repo" {
    create_test_context "mismatch-test" "$REPO1"

    # Create symlink pointing to somewhere else (not the main repo)
    local active_link="$TEST_HOME/active"
    rm -f "$active_link"
    local other_dir="$BATS_TEST_TMPDIR/other-dir"
    mkdir -p "$other_dir"
    ln -s "$other_dir" "$active_link"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "mismatch-test"
    assert_success

    # Symlink should be removed
    assert [ ! -L "$active_link" ]
    assert [ ! -e "$active_link" ]
    # Main repo should still exist (not moved)
    assert [ -d "$REPO1" ]
    # Warning about mismatch
    assert_output --partial "expected"
}

@test "remove updates worktree .git pointers after repo move" {
    create_test_context "ptr-test" "$REPO1"

    # Create a branch and worktree
    create_branch "$REPO1" "ptr-branch"
    local wt_path="$BATS_TEST_TMPDIR/wt-ptr"
    create_worktree "$REPO1" "$wt_path" "ptr-branch"
    # Normalize worktree path
    wt_path="$(cd "$wt_path" && pwd -P)"

    # Mark the worktree as adopted by this context — remove only updates
    # worktrees adopted by the context being removed
    source "$TEST_HOME/.wt/lib/wt-adopt"
    WT_CONTEXT_NAME="ptr-test" wt_mark_adopted "$wt_path"

    # Verify the worktree's .git file points to the OLD location
    local dot_git_content
    dot_git_content="$(cat "$wt_path/.git")"
    assert_equal "$dot_git_content" "gitdir: ${REPO1}/.git/worktrees/wt-ptr"

    # Set up the symlink scenario: active_link -> REPO1 (main repo)
    local active_link="$TEST_HOME/active"
    rm -f "$active_link"
    ln -s "$REPO1" "$active_link"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "ptr-test"
    assert_success

    # After remove: active_link should be a real directory
    assert [ ! -L "$active_link" ]
    assert [ -d "$active_link" ]

    # The worktree's .git file should now point to the NEW location
    dot_git_content="$(cat "$wt_path/.git")"
    assert_equal "$dot_git_content" "gitdir: ${active_link}/.git/worktrees/wt-ptr"

    # Verify git operations work in the worktree
    run git -C "$wt_path" status
    assert_success
}

@test "remove leaves non-symlink active worktree unchanged with warning" {
    create_test_context "nosym-test" "$REPO1"

    # Create the active worktree as a real directory
    local active_link="$TEST_HOME/active"
    rm -f "$active_link"
    mkdir -p "$active_link"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "nosym-test"
    assert_success

    # Should still be a directory, not a symlink
    assert [ -d "$active_link" ]
    assert [ ! -L "$active_link" ]
    # Should warn about it
    assert_output --partial "not a symlink"
}

# =============================================================================
# Adoption marker cleanup tests
# =============================================================================

@test "remove cleans up adoption markers from worktrees" {
    create_test_context "adopt-test" "$REPO1"

    # Create a branch and worktree
    create_branch "$REPO1" "feature-branch"
    local wt_path="$BATS_TEST_TMPDIR/wt-feature"
    create_worktree "$REPO1" "$wt_path" "feature-branch"

    # Mark the worktree as adopted by this context
    local git_dir
    git_dir="$(git -C "$wt_path" rev-parse --git-dir)"
    if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$wt_path/$git_dir" && pwd -P)"
    fi
    mkdir -p "$git_dir/wt"
    echo "adopt-test" > "$git_dir/wt/adopted"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "adopt-test"
    assert_success

    # Adoption marker should be removed
    assert [ ! -f "$git_dir/wt/adopted" ]
}

@test "remove does not clean up adoption markers from other contexts" {
    create_test_context "ctx-remove" "$REPO1"

    # Create a branch and worktree
    create_branch "$REPO1" "other-branch"
    local wt_path="$BATS_TEST_TMPDIR/wt-other"
    create_worktree "$REPO1" "$wt_path" "other-branch"

    # Mark the worktree as adopted by a DIFFERENT context
    local git_dir
    git_dir="$(git -C "$wt_path" rev-parse --git-dir)"
    if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$wt_path/$git_dir" && pwd -P)"
    fi
    mkdir -p "$git_dir/wt"
    echo "other-context" > "$git_dir/wt/adopted"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "ctx-remove"
    assert_success

    # Adoption marker for the OTHER context should remain
    assert [ -f "$git_dir/wt/adopted" ]
    local content
    content="$(cat "$git_dir/wt/adopted")"
    assert_equal "$content" "other-context"
}

@test "remove cleans up old empty adoption markers" {
    create_test_context "old-marker-test" "$REPO1"

    # Create a branch and worktree
    create_branch "$REPO1" "legacy-branch"
    local wt_path="$BATS_TEST_TMPDIR/wt-legacy"
    create_worktree "$REPO1" "$wt_path" "legacy-branch"

    # Create an old-format empty adoption marker
    local git_dir
    git_dir="$(git -C "$wt_path" rev-parse --git-dir)"
    if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$wt_path/$git_dir" && pwd -P)"
    fi
    mkdir -p "$git_dir/wt"
    touch "$git_dir/wt/adopted"

    run "$TEST_HOME/.wt/bin/wt-context" remove -y "old-marker-test"
    assert_success

    # Empty marker should be removed
    assert [ ! -f "$git_dir/wt/adopted" ]
}

# =============================================================================
# Help tests
# =============================================================================

@test "remove -h shows help" {
    run "$TEST_HOME/.wt/bin/wt-context" remove -h
    assert_success
    assert_output --partial "Usage:"
}
