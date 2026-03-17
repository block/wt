#!/usr/bin/env bats

# Unit tests for wt_list_porcelain (lib/wt-common)

setup() {
    load '../test_helper/common'
    setup_test_env
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-adopt"

    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    create_test_context "test" "$REPO"
    load_test_context "test"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic porcelain output
# =============================================================================

@test "wt_list_porcelain outputs native git porcelain lines verbatim" {
    run wt_list_porcelain
    assert_success

    # Should contain the worktree line with the repo path
    assert_output --partial "worktree $REPO"
    # Should contain HEAD line
    assert_output --partial "HEAD "
    # Should contain branch line
    assert_output --partial "branch refs/heads/main"
}

@test "wt_list_porcelain first entry is the main repo" {
    create_branch "$REPO" "feature-1"
    create_worktree "$REPO" "$WT_WORKTREES_BASE/feature-1" "feature-1"

    run wt_list_porcelain
    assert_success

    # First worktree line should be the main repo
    local first_worktree
    first_worktree=$(echo "$output" | grep "^worktree " | head -1)
    [[ "$first_worktree" == "worktree $REPO" ]] || fail "Expected first entry to be main repo, got: $first_worktree"
}

@test "wt_list_porcelain entries separated by blank lines" {
    create_branch "$REPO" "feature-1"
    create_worktree "$REPO" "$WT_WORKTREES_BASE/feature-1" "feature-1"

    run wt_list_porcelain
    assert_success

    # Should have exactly 2 worktree entries
    local count
    count=$(echo "$output" | grep -c "^worktree ")
    [[ "$count" -eq 2 ]] || fail "Expected 2 worktree entries, got: $count"
}

# =============================================================================
# wt.active indicator
# =============================================================================

@test "wt_list_porcelain includes wt.active for active worktree" {
    create_branch "$REPO" "feature-active"
    local wt_path="$WT_WORKTREES_BASE/feature-active"
    create_worktree "$REPO" "$wt_path" "feature-active"
    local norm_wt_path
    norm_wt_path="$(cd "$wt_path" && pwd -P)"

    # Create the active symlink
    ln -s "$norm_wt_path" "$WT_ACTIVE_WORKTREE"

    run wt_list_porcelain
    assert_success
    assert_output --partial "wt.active"

    # wt.active should appear in the feature-active entry, not the main repo entry
    local active_entry
    active_entry=$(echo "$output" | awk "/^worktree .*feature-active/,/^$/" | head -10)
    [[ "$active_entry" == *"wt.active"* ]] || fail "Expected wt.active in feature-active entry, got: $active_entry"
}

@test "wt_list_porcelain omits wt.active when no symlink exists" {
    run wt_list_porcelain
    assert_success
    refute_output --partial "wt.active"
}

# =============================================================================
# wt.adopted indicator
# =============================================================================

@test "wt_list_porcelain includes wt.adopted for adopted worktrees" {
    create_branch "$REPO" "feature-adopted"
    local wt_path="$WT_WORKTREES_BASE/feature-adopted"
    create_worktree "$REPO" "$wt_path" "feature-adopted"
    local norm_wt_path
    norm_wt_path="$(cd "$wt_path" && pwd -P)"

    # Mark as adopted
    wt_mark_adopted "$norm_wt_path"

    run wt_list_porcelain
    assert_success

    # wt.adopted should appear in the adopted entry
    local adopted_entry
    adopted_entry=$(echo "$output" | awk "/^worktree .*feature-adopted/,/^$/" | head -10)
    [[ "$adopted_entry" == *"wt.adopted"* ]] || fail "Expected wt.adopted in feature-adopted entry, got: $adopted_entry"
}

@test "wt_list_porcelain omits wt.adopted for non-adopted worktrees" {
    create_branch "$REPO" "feature-fresh"
    create_worktree "$REPO" "$WT_WORKTREES_BASE/feature-fresh" "feature-fresh"

    run wt_list_porcelain
    assert_success
    refute_output --partial "wt.adopted"
}

# =============================================================================
# Verbose mode
# =============================================================================

@test "wt_list_porcelain without --verbose omits wt.dirty" {
    make_repo_dirty "$REPO"

    run wt_list_porcelain
    assert_success
    refute_output --partial "wt.dirty"
}

@test "wt_list_porcelain --verbose includes wt.dirty for dirty worktree" {
    make_repo_dirty "$REPO"

    run wt_list_porcelain --verbose
    assert_success
    assert_output --partial "wt.dirty"
}

@test "wt_list_porcelain --verbose omits wt.dirty for clean worktree" {
    # Repo is clean by default
    run wt_list_porcelain --verbose
    assert_success
    refute_output --partial "wt.dirty"
}

@test "wt_list_porcelain without --verbose omits wt.ahead and wt.behind" {
    REPO_WITH_REMOTE=$(create_mock_repo_with_remote "$BATS_TEST_TMPDIR/repo-remote")
    export WT_MAIN_REPO_ROOT="$REPO_WITH_REMOTE"

    # Create a local commit ahead of origin
    (cd "$REPO_WITH_REMOTE" && echo "new" >> file.txt && git add file.txt && git commit -m "ahead") >/dev/null 2>&1

    run wt_list_porcelain
    assert_success
    refute_output --partial "wt.ahead"
    refute_output --partial "wt.behind"
}

@test "wt_list_porcelain --verbose includes wt.ahead when ahead of upstream" {
    REPO_WITH_REMOTE=$(create_mock_repo_with_remote "$BATS_TEST_TMPDIR/repo-remote")
    export WT_MAIN_REPO_ROOT="$REPO_WITH_REMOTE"

    # Create a local commit ahead of origin
    (cd "$REPO_WITH_REMOTE" && echo "new" >> file.txt && git add file.txt && git commit -m "ahead") >/dev/null 2>&1

    run wt_list_porcelain --verbose
    assert_success
    assert_output --partial "wt.ahead 1"
}
