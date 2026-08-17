#!/usr/bin/env bats

# Unit tests for shell completion (completion/wt.bash, completion/wt.zsh)
# and the shared _wt_worktree_list helper in lib/wt-common.

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the library under test
    source "$TEST_HOME/.wt/lib/wt-common"
}

teardown() {
    teardown_test_env
}

skip_if_no_zsh() {
    if ! command -v zsh &>/dev/null; then
        skip "Test requires zsh"
    fi
}

# Put a stub fzf on PATH so the fzf code path is exercised deterministically
make_fake_fzf() {
    mkdir -p "$BATS_TEST_TMPDIR/fakebin"
    printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/fakebin/fzf"
    chmod +x "$BATS_TEST_TMPDIR/fakebin/fzf"
}

# Create a mock repo with one extra worktree; sets $repo, $wt_path
setup_repo_with_worktree() {
    repo=$(create_mock_repo)
    create_branch "$repo" "feature-x"
    create_worktree "$repo" "$BATS_TEST_TMPDIR/wt-x" "feature-x"
    wt_path="$(cd "$BATS_TEST_TMPDIR/wt-x" && pwd -P)"
}

# =============================================================================
# _wt_worktree_list shared helper
# =============================================================================

@test "_wt_worktree_list emits one path per registered worktree" {
    local repo wt_path
    setup_repo_with_worktree
    export WT_MAIN_REPO_ROOT="$repo"

    run _wt_worktree_list
    assert_success
    assert_line "$repo"
    assert_line "$wt_path"
}

@test "bash wt-metadata-import completion offers worktree paths" {
    local repo wt_path
    setup_repo_with_worktree
    mkdir -p "$BATS_TEST_TMPDIR/emptydir"

    run bash -c "
        cd '$BATS_TEST_TMPDIR/emptydir'
        source '$PROJECT_ROOT/completion/wt.bash'
        export WT_MAIN_REPO_ROOT='$repo'
        COMP_WORDS=('wt-metadata-import' '')
        COMP_CWORD=1
        _wt_metadata_import_complete
        printf '%s\n' \"\${COMPREPLY[@]}\"
    "
    assert_success
    assert_output --partial "$wt_path"
}

@test "zsh completion defines _wt_worktree_list after sourcing" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
print helper_defined: \$+functions[_wt_worktree_list]
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_output --partial "helper_defined: 1"
}

# =============================================================================
# No global TAB hijack in zsh when fzf is present
# =============================================================================

@test "zsh with fzf leaves TAB untouched and defines _wt_add" {
    skip_if_no_zsh
    make_fake_fzf

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
path=("$BATS_TEST_TMPDIR/fakebin" \$path)
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
print tab: \$(bindkey '^I')
print xa: \$(bindkey '^X^A')
print dispatch_defined: \$+functions[wt_tab_dispatch]
print wt_add_defined: \$+functions[_wt_add]
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    refute_output --partial "wt_tab_dispatch"
    assert_output --partial "dispatch_defined: 0"
    assert_output --partial "wt_add_defined: 1"
    assert_output --partial 'xa: "^X^A" wt_fzf_branch_complete'
}

# =============================================================================
# compdef guarded (silent without compinit, registered with compinit)
# =============================================================================

@test "zsh completion sources cleanly when compinit has not run" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh"
print SOURCED_OK
EOF
    run --separate-stderr zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_output --partial "SOURCED_OK"
    [[ "$stderr" != *"compdef"* ]] || fail "compdef errors on stderr: $stderr"
}

@test "zsh completion registers completers when compdef is available" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
autoload -Uz compinit
compinit -u -d "$BATS_TEST_TMPDIR/zcompdump"
source "$PROJECT_ROOT/completion/wt.zsh"
print wt: \${_comps[wt]:-none}
print adopt: \${_comps[wt-adopt]:-none}
print add: \${_comps[wt-add]:-none}
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_output --partial "wt: _wt_completion"
    assert_output --partial "adopt: _wt_adopt"
    assert_output --partial "add: _wt_add"
}

# =============================================================================
# wt-adopt completion (flags, exclude_main) and zsh context remove -y
# =============================================================================

@test "bash wt-adopt completion offers --force and --redo" {
    source "$PROJECT_ROOT/completion/wt.bash"

    COMP_WORDS=("wt-adopt" "--")
    COMP_CWORD=1
    _wt_adopt_complete
    [[ " ${COMPREPLY[*]} " == *" --force "* ]] || fail "missing --force in: ${COMPREPLY[*]}"
    [[ " ${COMPREPLY[*]} " == *" --redo "* ]] || fail "missing --redo in: ${COMPREPLY[*]}"
}

@test "bash wt-adopt completion excludes the main repo branch" {
    local repo wt_path
    setup_repo_with_worktree
    source "$PROJECT_ROOT/completion/wt.bash"
    export WT_MAIN_REPO_ROOT="$repo"

    COMP_WORDS=("wt-adopt" "")
    COMP_CWORD=1
    _wt_adopt_complete
    [[ " ${COMPREPLY[*]} " == *" feature-x "* ]] || fail "missing feature-x in: ${COMPREPLY[*]}"
    [[ " ${COMPREPLY[*]} " != *" main "* ]] || fail "main repo branch offered: ${COMPREPLY[*]}"
}

@test "bash unified wt adopt completion offers --force and --redo" {
    source "$PROJECT_ROOT/completion/wt.bash"

    COMP_WORDS=("wt" "adopt" "--")
    COMP_CWORD=2
    _wt_completion_bash
    [[ " ${COMPREPLY[*]} " == *" --force "* ]] || fail "missing --force in: ${COMPREPLY[*]}"
    [[ " ${COMPREPLY[*]} " == *" --redo "* ]] || fail "missing --redo in: ${COMPREPLY[*]}"
}

@test "zsh _wt_adopt offers flags and excludes the main repo" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
whence -f _wt_adopt
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_output --partial -- "--force"
    assert_output --partial -- "--redo"
    assert_output --partial "exclude_main"
}

@test "zsh context remove completion offers -y/--yes" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
whence -f _wt_context
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_output --partial -- "--yes"
}

# =============================================================================
# Completion reload uses ordered mode (git local config keeps priority)
# =============================================================================

@test "bash completion reload respects git local config priority" {
    unset _WT_SKIP_GIT_CONFIG

    local repo
    repo=$(create_mock_repo)
    create_test_context "ctx" "$repo"
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    source "$PROJECT_ROOT/completion/wt.bash"

    COMP_WORDS=("wt" "")
    COMP_CWORD=1
    _wt_completion_bash

    assert_equal "$WT_BASE_BRANCH" "git-branch"
}

@test "zsh completion reload does not force context-only mode" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
whence -f _wt_completion
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    refute_output --partial "mode=context"
    assert_output --partial "wt_read_config --force"
}
