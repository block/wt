#!/usr/bin/env bats

# Unit tests for lib/wt-context

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the libraries under test
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-context"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for wt_get_repos_dir()
# =============================================================================

@test "wt_get_repos_dir returns ~/.wt/repos" {
    run wt_get_repos_dir
    assert_success
    assert_output "$TEST_HOME/.wt/repos"
}

# =============================================================================
# Tests for wt_get_current_file()
# =============================================================================

@test "wt_get_current_file returns ~/.wt/current" {
    run wt_get_current_file
    assert_success
    assert_output "$TEST_HOME/.wt/current"
}

# =============================================================================
# Tests for wt_list_contexts()
# =============================================================================

@test "wt_list_contexts returns empty for no contexts" {
    # Ensure no .conf files exist
    rm -f "$TEST_HOME/.wt/repos"/*.conf 2>/dev/null || true

    run wt_list_contexts
    assert_success
    assert_output ""
}

@test "wt_list_contexts returns single context" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "test-ctx" "$repo"

    run wt_list_contexts
    assert_success
    assert_output "test-ctx"
}

@test "wt_list_contexts returns multiple contexts in glob order" {
    local repo1 repo2 repo3
    repo1=$(create_mock_repo "$BATS_TEST_TMPDIR/repo1")
    repo2=$(create_mock_repo "$BATS_TEST_TMPDIR/repo2")
    repo3=$(create_mock_repo "$BATS_TEST_TMPDIR/repo3")

    create_test_context "zebra" "$repo1"
    create_test_context "alpha" "$repo2"
    create_test_context "middle" "$repo3"

    run wt_list_contexts
    assert_success
    # Shell glob expansion returns files in alphabetical order
    assert_line --index 0 "alpha"
    assert_line --index 1 "middle"
    assert_line --index 2 "zebra"
}

# =============================================================================
# Tests for wt_get_current_context()
# =============================================================================

@test "wt_get_current_context returns empty when no current file" {
    rm -f "$TEST_HOME/.wt/current" 2>/dev/null || true

    run wt_get_current_context
    assert_success
    assert_output ""
}

@test "wt_get_current_context returns current context name" {
    echo "my-context" > "$TEST_HOME/.wt/current"

    run wt_get_current_context
    assert_success
    assert_output "my-context"

    # Trailing newline in file should be stripped
    printf "other-context\n" > "$TEST_HOME/.wt/current"
    run wt_get_current_context
    assert_success
    assert_output "other-context"
}

# =============================================================================
# Tests for wt_context_exists()
# =============================================================================

@test "wt_context_exists returns success for existing context" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    run wt_context_exists "myctx"
    assert_success
}

@test "wt_context_exists returns failure for missing context" {
    run wt_context_exists "nonexistent"
    assert_failure
}

@test "wt_context_exists returns failure for empty name" {
    run wt_context_exists ""
    assert_failure
}

# =============================================================================
# Tests for wt_get_context_config_path()
# =============================================================================

@test "wt_get_context_config_path returns correct path" {
    run wt_get_context_config_path "myctx"
    assert_success
    assert_output "$TEST_HOME/.wt/repos/myctx.conf"
}

@test "wt_get_context_config_path handles dashes and underscores" {
    run wt_get_context_config_path "my-context_name"
    assert_success
    assert_output "$TEST_HOME/.wt/repos/my-context_name.conf"
}

# =============================================================================
# Tests for wt_set_current_context()
# =============================================================================

@test "wt_set_current_context creates current file for existing context" {
    # wt_set_current_context requires the context to exist
    local repo
    repo=$(create_mock_repo)
    create_test_context "new-context" "$repo"
    rm -f "$TEST_HOME/.wt/current" 2>/dev/null || true

    run wt_set_current_context "new-context"
    assert_success
    assert [ -f "$TEST_HOME/.wt/current" ]
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "new-context"
}

@test "wt_set_current_context overwrites existing context" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "old-context" "$repo"
    create_test_context "new-context" "$repo"
    echo "old-context" > "$TEST_HOME/.wt/current"

    run wt_set_current_context "new-context"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "new-context"
}

# =============================================================================
# Tests for wt_load_context_config()
# =============================================================================

@test "wt_load_context_config sets WT_* variables" {
    local repo
    repo=$(create_mock_repo)
    # create_test_context sets up the context AND sets it as current (writes to ~/.wt/current)
    create_test_context "test-ctx" "$repo"

    # Clear any existing values
    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_ACTIVE_WORKTREE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    wt_load_context_config

    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_BASE_BRANCH" "main"
    assert [ -n "$WT_WORKTREES_BASE" ]
    assert [ -n "$WT_ACTIVE_WORKTREE" ]
    assert [ -n "$WT_IDEA_FILES_BASE" ]
}

@test "wt_load_context_config returns failure when current file points to missing context" {
    echo "nonexistent-context" > "$TEST_HOME/.wt/current"
    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_ACTIVE_WORKTREE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    # Should fail because nonexistent-context.conf doesn't exist
    run wt_load_context_config
    assert_failure
}

# =============================================================================
# Tests for wt_get_context_repo_root()
# =============================================================================

@test "wt_get_context_repo_root returns repo root for valid context" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "test-ctx" "$repo"

    run wt_get_context_repo_root "test-ctx"
    assert_success
    assert_output "$repo"
}

@test "wt_get_context_repo_root returns empty for invalid context" {
    run wt_get_context_repo_root "nonexistent"
    # Function returns empty string (not failure) when context doesn't exist
    assert_success
    assert_output ""
}

# =============================================================================
# Tests for wt_show_context_banner()
# =============================================================================

@test "wt_show_context_banner shows context name when contexts exist" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "my-context" "$repo"

    # Banner goes to stderr, use --separate-stderr to capture both
    run --separate-stderr wt_show_context_banner
    assert_success
    # Banner should contain context name in stderr (UI output)
    [[ "$stderr" == *"my-context"* ]] || fail "Expected stderr to contain 'my-context', got: $stderr"
}

@test "wt_show_context_banner shows nothing when no contexts configured" {
    # Remove all context files to ensure no contexts exist
    rm -f "$TEST_HOME/.wt/current" 2>/dev/null || true
    rm -f "$TEST_HOME/.wt/repos"/*.conf 2>/dev/null || true

    run --separate-stderr wt_show_context_banner
    assert_success
    # With no contexts configured, banner should produce no output
    assert_output ""
    assert_equal "$stderr" ""
}

# =============================================================================
# Integration tests for context workflow
# =============================================================================

@test "full context workflow: create, set, load, get" {
    local repo
    repo=$(create_mock_repo)

    # Create context (also sets it as current via ~/.wt/current)
    create_test_context "workflow-test" "$repo"

    # Verify it exists
    run wt_context_exists "workflow-test"
    assert_success

    # Verify it's in list
    run wt_list_contexts
    assert_output --partial "workflow-test"

    # Verify it's current
    run wt_get_current_context
    assert_output "workflow-test"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_ACTIVE_WORKTREE WT_IDEA_FILES_BASE WT_BASE_BRANCH
    wt_load_context_config
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

@test "multiple contexts can coexist" {
    local repo1 repo2
    repo1=$(create_mock_repo "$BATS_TEST_TMPDIR/repo1")
    repo2=$(create_mock_repo "$BATS_TEST_TMPDIR/repo2")

    create_test_context "ctx1" "$repo1"
    create_test_context "ctx2" "$repo2"

    # Both should exist
    run wt_context_exists "ctx1"
    assert_success
    run wt_context_exists "ctx2"
    assert_success

    # Can get repo root for each via wt_get_context_repo_root
    run wt_get_context_repo_root "ctx1"
    assert_success
    assert_output "$repo1"

    run wt_get_context_repo_root "ctx2"
    assert_success
    assert_output "$repo2"
}

# =============================================================================
# Tests for context config file format (validates test helper creates
# configs matching the format that production code expects)
# =============================================================================

@test "config file is sourceable and contains all required WT_* variables" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "test-ctx" "$repo"

    local config_path="$TEST_HOME/.wt/repos/test-ctx.conf"

    # Config must be valid bash that sets WT_MAIN_REPO_ROOT correctly
    run bash -c "source '$config_path' && echo \"\$WT_MAIN_REPO_ROOT\""
    assert_success
    assert_output "$repo"

    # Verify all required fields are present with expected values
    local repo_root worktrees_base base_branch
    repo_root=$(grep '^WT_MAIN_REPO_ROOT=' "$config_path" | cut -d'"' -f2)
    worktrees_base=$(grep '^WT_WORKTREES_BASE=' "$config_path" | cut -d'"' -f2)
    base_branch=$(grep '^WT_BASE_BRANCH=' "$config_path" | cut -d'"' -f2)

    assert_equal "$repo_root" "$repo"
    [[ "$worktrees_base" == *"test-ctx"* ]] || fail "WT_WORKTREES_BASE should contain context name, got: $worktrees_base"
    assert_equal "$base_branch" "main"
}
