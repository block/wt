#!/usr/bin/env bats

# Integration tests for path validation in bin/wt-* scripts

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    # Create test context with valid config (don't load into env —
    # we want the subprocess to read from .conf, not inherited env)
    create_test_context "test" "$REPO"
}

teardown() {
    teardown_test_env
}

# Helper: unset all WT_* config vars so subprocess reads from .conf
_unset_wt_vars() {
    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE
    unset WT_ACTIVE_WORKTREE WT_BASE_BRANCH WT_METADATA_PATTERNS
    unset WT_CONTEXT_NAME
}

# =============================================================================
# bin scripts abort on invalid config
# =============================================================================

@test "wt-add aborts with relative WT_WORKTREES_BASE" {
    local conf="$TEST_HOME/.wt/repos/test.conf"
    sed -i.bak 's|^WT_WORKTREES_BASE=.*|WT_WORKTREES_BASE="relative/worktrees"|' "$conf"
    _unset_wt_vars

    run "$TEST_HOME/.wt/bin/wt-add" -b some-branch
    assert_failure
    assert_output --partial "WT_WORKTREES_BASE"
    assert_output --partial "must be an absolute path"
}

@test "wt-list aborts with glob in WT_MAIN_REPO_ROOT" {
    local conf="$TEST_HOME/.wt/repos/test.conf"
    sed -i.bak 's|^WT_MAIN_REPO_ROOT=.*|WT_MAIN_REPO_ROOT="/tmp/repo-*"|' "$conf"
    _unset_wt_vars

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_failure
    assert_output --partial "WT_MAIN_REPO_ROOT"
    assert_output --partial "must be an absolute path"
}

@test "wt-switch aborts with relative WT_IDEA_FILES_BASE" {
    local conf="$TEST_HOME/.wt/repos/test.conf"
    sed -i.bak 's|^WT_IDEA_FILES_BASE=.*|WT_IDEA_FILES_BASE="idea-files"|' "$conf"
    _unset_wt_vars

    run "$TEST_HOME/.wt/bin/wt-switch" "$REPO"
    assert_failure
    assert_output --partial "WT_IDEA_FILES_BASE"
    assert_output --partial "must be an absolute path"
}

@test "wt-context is not guarded and works with invalid config" {
    local conf="$TEST_HOME/.wt/repos/test.conf"
    sed -i.bak 's|^WT_WORKTREES_BASE=.*|WT_WORKTREES_BASE="relative/worktrees"|' "$conf"
    _unset_wt_vars

    run "$TEST_HOME/.wt/bin/wt-context" --list
    assert_success
}

@test "error message includes config file path" {
    local conf="$TEST_HOME/.wt/repos/test.conf"
    sed -i.bak 's|^WT_WORKTREES_BASE=.*|WT_WORKTREES_BASE="relative/worktrees"|' "$conf"
    _unset_wt_vars

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_failure
    assert_output --partial "test.conf"
}

@test "valid absolute paths pass validation normally" {
    _unset_wt_vars

    run "$TEST_HOME/.wt/bin/wt-list"
    assert_success
}
