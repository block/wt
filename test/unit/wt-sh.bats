#!/usr/bin/env bats

# Unit tests for wt.sh

setup() {
    load '../test_helper/common'
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for _WT_ROOT consistency
# =============================================================================

@test "wt.sh dispatches adopt subcommand" {
    grep -q 'adopt)' "$PROJECT_ROOT/wt.sh"
}

# =============================================================================
# Tests for wt cd help handling
# =============================================================================

@test "wt cd --help shows help and exits 0" {
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")
    create_test_context "test" "$REPO"

    # source returns nonzero when no completion file exists in the test HOME,
    # so chain with ";" to let the exit status reflect `wt cd --help` itself
    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; wt cd --help'
    assert_success
    assert_output --partial "Usage:"

    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; wt cd -h'
    assert_success
    assert_output --partial "Usage:"
}

@test "_WT_ROOT default in wt.sh matches INSTALL_DIR in install.sh" {
    # Extract the default path from wt.sh: _WT_ROOT="${_WT_ROOT:-$HOME/.wt}"
    local wt_line
    wt_line=$(grep '_WT_ROOT=.*HOME' "$PROJECT_ROOT/wt.sh" | head -1)
    # Pull out the $HOME/... portion
    local wt_path
    wt_path=$(echo "$wt_line" | sed 's/.*\(\$HOME\/[^}"]*\).*/\1/')

    # Extract INSTALL_DIR from install.sh: INSTALL_DIR="$HOME/.wt"
    local install_line
    install_line=$(grep 'INSTALL_DIR=.*HOME' "$PROJECT_ROOT/install.sh" | head -1)
    local install_path
    install_path=$(echo "$install_line" | sed 's/.*"\(\$HOME\/[^"]*\)".*/\1/')

    [ -n "$wt_path" ]
    [ -n "$install_path" ]
    [ "$wt_path" = "$install_path" ]
}
