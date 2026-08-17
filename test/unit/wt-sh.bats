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
# Tests for bin/ registry dispatch
# =============================================================================

@test "wt dispatches subcommands via the bin/ registry" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/wt.sh"
        __wt_run() { echo "run:$*"; }
        wt add -b feature/x
        wt adopt --redo
        wt switch foo
        wt list -v
        wt metadata-export
        wt metadata-import
    '
    assert_success
    assert_line "run:wt-add -b feature/x"
    assert_line "run:wt-adopt --redo"
    assert_line "run:wt-switch foo"
    assert_line "run:wt-list -v"
    assert_line "run:wt-metadata-export"
    assert_line "run:wt-metadata-import"
}

@test "executable dropped into bin/ becomes dispatchable without wt.sh changes" {
    cat > "$TEST_HOME/.wt/bin/wt-frobnicate" <<'EOF'
#!/usr/bin/env bash
echo "frobnicated:$*"
EOF
    chmod +x "$TEST_HOME/.wt/bin/wt-frobnicate"

    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; wt frobnicate --flag arg1'
    assert_success
    assert_output --partial "frobnicated:--flag arg1"
}

@test "wt unknown command errors with the unknown-command message" {
    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; wt no-such-command'
    assert_failure
    assert_output --partial "wt: unknown command 'no-such-command'"
    assert_output --partial "Run 'wt help' for usage information."
}

@test "non-executable file in bin/ is not dispatchable" {
    echo "echo nope" > "$TEST_HOME/.wt/bin/wt-notexec"

    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; wt notexec'
    assert_failure
    assert_output --partial "wt: unknown command 'notexec'"
}

@test "command names containing a slash are rejected" {
    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; wt ../lib/wt-common'
    assert_failure
    assert_output --partial "unknown command"
}

@test "cd, remove, and context route to shell-integrated helpers" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/wt.sh"
        __wt_do_cd()     { echo "do_cd:$*"; }
        __wt_do_remove() { echo "do_remove:$*"; }
        __wt_run()       { echo "run:$*"; }
        wt_read_config() { echo "reload:$*"; }
        wt cd foo
        wt remove bar
        wt context baz
    '
    assert_success
    assert_line "do_cd:foo"
    assert_line "do_remove:bar"
    assert_line "run:wt-context baz"
    assert_line "reload:--force"
}

@test "legacy ijwb aliases route to metadata commands" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/wt.sh"
        __wt_run() { echo "run:$*"; }
        wt ijwb-export src vault
        wt ijwb-import vault
    '
    assert_success
    assert_line "run:wt-metadata-export src vault"
    assert_line "run:wt-metadata-import vault"
}

# =============================================================================
# Tests for __wt_source_lib
# =============================================================================

@test "__wt_source_lib errors for a missing library" {
    run bash -c 'source "'"$PROJECT_ROOT"'/wt.sh"; __wt_source_lib no-such-lib'
    assert_failure
    assert_output --partial "wt: cannot find required library: no-such-lib"
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

@test "wt with no arguments prints help under set -u" {
    cp "$PROJECT_ROOT/wt.sh" "$TEST_HOME/.wt/wt.sh"

    run bash -c '
        set -u
        source "$HOME/.wt/wt.sh"
        wt
    '
    assert_success
    assert_output --partial "Unified Worktree Toolkit"
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
