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
# Dynamic top-level command list (_wt_command_list) from the bin/ registry
# =============================================================================

@test "bash _wt_command_list derives commands from bin/ plus aliases and help" {
    printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.wt/bin/wt-frobnicate"
    chmod +x "$TEST_HOME/.wt/bin/wt-frobnicate"
    echo "not a command" > "$TEST_HOME/.wt/bin/wt-notexec"

    source "$PROJECT_ROOT/completion/wt.bash"

    run _wt_command_list
    assert_success
    assert_line "add"
    assert_line "adopt"
    assert_line "list"
    assert_line "frobnicate"
    assert_line "ijwb-export"
    assert_line "ijwb-import"
    assert_line "help"
    refute_line "notexec"
}

@test "bash _wt_command_list tolerates a missing bin dir" {
    source "$PROJECT_ROOT/completion/wt.bash"
    __WT_ROOT="$BATS_TEST_TMPDIR/no-such-root"

    run _wt_command_list
    assert_success
    assert_line "help"
    assert_line "ijwb-export"
    refute_line "add"
}

@test "bash unified wt completion offers commands from the bin/ registry" {
    printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.wt/bin/wt-frobnicate"
    chmod +x "$TEST_HOME/.wt/bin/wt-frobnicate"

    source "$PROJECT_ROOT/completion/wt.bash"

    COMP_WORDS=("wt" "")
    COMP_CWORD=1
    _wt_completion_bash
    [[ " ${COMPREPLY[*]} " == *" add "* ]] || fail "missing add in: ${COMPREPLY[*]}"
    [[ " ${COMPREPLY[*]} " == *" frobnicate "* ]] || fail "missing frobnicate in: ${COMPREPLY[*]}"
    [[ " ${COMPREPLY[*]} " == *" help "* ]] || fail "missing help in: ${COMPREPLY[*]}"
    [[ " ${COMPREPLY[*]} " == *" ijwb-export "* ]] || fail "missing ijwb-export in: ${COMPREPLY[*]}"
}

@test "zsh _wt_command_list derives commands from bin/ plus aliases and help" {
    skip_if_no_zsh

    printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.wt/bin/wt-frobnicate"
    chmod +x "$TEST_HOME/.wt/bin/wt-frobnicate"
    echo "not a command" > "$TEST_HOME/.wt/bin/wt-notexec"

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
_wt_command_list
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_line "add"
    assert_line "adopt"
    assert_line "frobnicate"
    assert_line "help:Show help message"
    assert_output --partial "ijwb-export:"
    assert_output --partial "ijwb-import:"
    refute_line "notexec"
}

@test "zsh _wt_command_list tolerates a missing bin dir" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
__WT_ROOT="$BATS_TEST_TMPDIR/no-such-root"
_wt_command_list
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_line "help:Show help message"
    refute_line "add"
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

# =============================================================================
# Context enumeration uses the shared wt_list_contexts helper
# =============================================================================

@test "bash _wt_context_list emits context names via shared helper" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "ctx-one" "$repo"

    run bash -c "
        source '$PROJECT_ROOT/completion/wt.bash'
        _wt_context_list
    "
    assert_success
    assert_line "ctx-one"
}

@test "zsh context completion offers each context as a separate candidate" {
    skip_if_no_zsh

    local repo
    repo=$(create_mock_repo)
    create_test_context "ctx-one" "$repo"
    create_test_context "ctx-two" "$repo"

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
source "$PROJECT_ROOT/completion/wt.zsh" 2>/dev/null
_arguments() { state=first; return 1 }
_describe() {
  local item
  for item in "\${(@P)2}"; do
    print -r -- "ITEM:\$item"
  done
}
_wt_context
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_line "ITEM:ctx-one"
    assert_line "ITEM:ctx-two"
}

@test "zsh wt_list_contexts is null-glob safe with no contexts" {
    skip_if_no_zsh

    cat > "$BATS_TEST_TMPDIR/t.zsh" <<EOF
setopt nomatch
source "$TEST_HOME/.wt/lib/wt-common" 2>/dev/null
wt_list_contexts
print LIST_OK
EOF
    run zsh -f "$BATS_TEST_TMPDIR/t.zsh"
    assert_success
    assert_output --partial "LIST_OK"
}
