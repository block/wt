#!/usr/bin/env bats

# Unit tests for lib/wt-common

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the library under test
    source "$TEST_HOME/.wt/lib/wt-common"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for echoerr()
# =============================================================================

@test "echoerr outputs message to stderr" {
    run --separate-stderr echoerr "test message"
    assert_success
    assert_output ""  # stdout should be empty
    assert_equal "$stderr" "test message"
}

@test "echoerr handles empty message" {
    run --separate-stderr echoerr ""
    assert_success
    assert_output ""
    assert_equal "$stderr" ""
}

# =============================================================================
# Tests for error(), success(), warn(), info()
# =============================================================================

@test "error() outputs error message to stderr" {
    run --separate-stderr error "something went wrong"
    assert_success
    assert_output ""  # stdout should be empty
    [[ "$stderr" == *"something went wrong"* ]] || fail "stderr should contain message, got: $stderr"
    [[ "$stderr" == *"Error:"* ]] || fail "stderr should contain 'Error:' prefix, got: $stderr"
}

@test "success() outputs success message" {
    run success "operation completed"
    assert_success
    assert_output --partial "operation completed"
}

@test "warn() outputs warning message to stderr" {
    run --separate-stderr warn "be careful"
    assert_success
    assert_output ""  # stdout should be empty
    [[ "$stderr" == *"be careful"* ]] || fail "stderr should contain message, got: $stderr"
    [[ "$stderr" == *"⚠"* ]] || fail "stderr should contain warning symbol, got: $stderr"
}

@test "info() outputs info message" {
    run info "here is some info"
    assert_success
    assert_output --partial "here is some info"
}

# =============================================================================
# Tests for wt_source()
# =============================================================================

@test "wt_source loads library from LIB_DIR" {
    # Create a test library file
    echo 'TEST_LIB_LOADED=true' > "$TEST_HOME/.wt/lib/test-lib"

    export LIB_DIR="$TEST_HOME/.wt/lib"
    wt_source "test-lib"

    assert_equal "$TEST_LIB_LOADED" "true"
}

@test "wt_source fails for non-existent library" {
    export LIB_DIR="$TEST_HOME/.wt/lib"
    run wt_source "nonexistent-lib"
    assert_failure
}

# =============================================================================
# Tests for wt_has_uncommitted_changes()
# =============================================================================

@test "wt_has_uncommitted_changes returns true for repo with unstaged changes" {
    local repo
    repo=$(create_mock_repo)
    make_repo_dirty "$repo"

    run wt_has_uncommitted_changes "$repo"
    assert_success
}

@test "wt_has_uncommitted_changes returns true for repo with staged changes" {
    local repo
    repo=$(create_mock_repo)
    make_repo_dirty "$repo"
    stage_changes "$repo"

    run wt_has_uncommitted_changes "$repo"
    assert_success
}

@test "wt_has_uncommitted_changes returns false for clean repo" {
    local repo
    repo=$(create_mock_repo)

    run wt_has_uncommitted_changes "$repo"
    assert_failure
}

# =============================================================================
# Tests for wt_uncommitted_summary()
# =============================================================================

@test "wt_uncommitted_summary returns empty for clean repo" {
    local repo
    repo=$(create_mock_repo)

    run wt_uncommitted_summary "$repo"
    assert_success
    assert_output ""
}

@test "wt_uncommitted_summary counts unstaged and untracked changes" {
    local repo
    repo=$(create_mock_repo)
    echo "change1" >> "$repo/file.txt"
    echo "new file" > "$repo/newfile.txt"

    run wt_uncommitted_summary "$repo"
    assert_success
    # Should show "N modified N untracked" format
    assert_output --partial "modified"
    assert_output --partial "untracked"
}

@test "wt_uncommitted_summary counts staged changes" {
    local repo
    repo=$(create_mock_repo)
    echo "change1" >> "$repo/file.txt"
    stage_changes "$repo"

    run wt_uncommitted_summary "$repo"
    assert_success
    assert_output --partial "staged"
}

# =============================================================================
# Tests for wt_get_linked_worktree()
# =============================================================================

@test "wt_get_linked_worktree returns empty when WT_ACTIVE_WORKTREE not set" {
    unset WT_ACTIVE_WORKTREE

    run wt_get_linked_worktree
    assert_success
    assert_output ""
}

@test "wt_get_linked_worktree returns empty when symlink doesn't exist" {
    export WT_ACTIVE_WORKTREE="$TEST_HOME/nonexistent"

    run wt_get_linked_worktree
    assert_success
    assert_output ""
}

@test "wt_get_linked_worktree returns empty when path is not a symlink" {
    mkdir -p "$TEST_HOME/not-a-symlink"
    export WT_ACTIVE_WORKTREE="$TEST_HOME/not-a-symlink"

    run wt_get_linked_worktree
    assert_success
    assert_output ""
}

@test "wt_get_linked_worktree resolves symlink target" {
    local repo
    repo=$(create_mock_repo)
    ln -s "$repo" "$TEST_HOME/active"
    export WT_ACTIVE_WORKTREE="$TEST_HOME/active"

    run wt_get_linked_worktree
    assert_success
    # wt_get_linked_worktree uses pwd -P to return physical path
    # so we need to compare against normalized path (handles macOS /var -> /private/var)
    local expected_physical_path
    expected_physical_path="$(cd "$repo" && pwd -P)"
    assert_output "$expected_physical_path"
}

# =============================================================================
# Tests for wt_format_worktree()
# =============================================================================

@test "wt_format_worktree shows [main] for main repo" {
    local repo
    repo=$(create_mock_repo)

    # wt_format_worktree args: <worktree_path> [main_repo_abs] [linked_worktree] [verbose]
    run wt_format_worktree "$repo" "$repo" ""
    assert_success
    assert_output --partial "[main]"
}

@test "wt_format_worktree shows [linked] for active worktree" {
    local repo
    repo=$(create_mock_repo)
    local wt_path="$BATS_TEST_TMPDIR/worktree1"
    create_branch "$repo" "feature-1"
    create_worktree "$repo" "$wt_path" "feature-1"

    # wt_format_worktree args: <worktree_path> [main_repo_abs] [linked_worktree] [verbose]
    run wt_format_worktree "$wt_path" "$repo" "$wt_path"
    assert_success
    assert_output --partial "[linked]"
}

@test "wt_format_worktree shows branch name" {
    local repo
    repo=$(create_mock_repo)

    run wt_format_worktree "$repo" "" ""
    assert_success
    # Should show (main) as that's the branch
    assert_output --partial "(main)"
}

# =============================================================================
# Tests for prompt_confirm()
# =============================================================================

@test "prompt_confirm accepts y/Y and rejects n/N/empty" {
    # Accepts lowercase and uppercase 'y'
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "y" | prompt_confirm "Continue?"'
    assert_success
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "Y" | prompt_confirm "Continue?"'
    assert_success

    # Rejects lowercase and uppercase 'n'
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "n" | prompt_confirm "Continue?"'
    assert_failure
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "N" | prompt_confirm "Continue?"'
    assert_failure

    # Rejects empty input (no default)
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "" | prompt_confirm "Continue?"'
    assert_failure
}

