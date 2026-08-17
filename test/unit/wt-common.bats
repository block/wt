#!/usr/bin/env bats

# Unit tests for lib/wt-common

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the library under test
    source "$TEST_HOME/.wt/lib/wt-common"

    # Re-enable wt_read_git_config for unit tests that exercise it directly.
    # The guard was needed during source-time to prevent host repo config bleed,
    # but unit tests cd into their own mock repos before calling the function.
    unset _WT_SKIP_GIT_CONFIG
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
# Tests for wt_status_probe() and wt_run_status_probes()
# =============================================================================

@test "wt_status_probe emits dirty for a dirty repo and nothing for a clean one" {
    local clean dirty
    clean=$(create_mock_repo "$BATS_TEST_TMPDIR/clean_repo")
    dirty=$(create_mock_repo "$BATS_TEST_TMPDIR/dirty_repo")
    make_repo_dirty "$dirty"

    run wt_status_probe "$dirty" "main"
    assert_success
    assert_output "dirty"

    run wt_status_probe "$clean" "main"
    assert_success
    assert_output ""
}

@test "wt_status_probe skips ahead/behind when branch is empty" {
    local repo
    repo=$(create_mock_repo_with_remote "$BATS_TEST_TMPDIR/remote_repo")
    (cd "$repo" && echo "new" >> file.txt && git add file.txt && git commit -m "ahead") >/dev/null 2>&1

    run wt_status_probe "$repo" "main"
    assert_success
    assert_output "ahead 1"

    run wt_status_probe "$repo" ""
    assert_success
    assert_output ""
}

@test "wt_run_status_probes writes probe results keyed by index" {
    local clean dirty dir
    clean=$(create_mock_repo "$BATS_TEST_TMPDIR/clean_repo")
    dirty=$(create_mock_repo "$BATS_TEST_TMPDIR/dirty_repo")
    make_repo_dirty "$dirty"
    dir="$BATS_TEST_TMPDIR/probes"
    mkdir -p "$dir"

    printf '0\t%s\t\n1\t%s\t\n' "$clean" "$dirty" | wt_run_status_probes "$dir"

    [[ -f "$dir/0" && -f "$dir/1" ]] || fail "Expected probe files 0 and 1 in $dir"
    [[ ! -s "$dir/0" ]] || fail "Clean repo probe should be empty: $(cat "$dir/0")"
    assert_equal "$(cat "$dir/1")" "dirty"
}

@test "wt_run_status_probes completes all probes with more input than the pool size" {
    local repo dir i input=""
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/pool_repo")
    dir="$BATS_TEST_TMPDIR/probes-pool"
    mkdir -p "$dir"
    make_repo_dirty "$repo"

    for i in 0 1 2 3 4 5 6 7; do
        input="${input}${i}"$'\t'"${repo}"$'\t'$'\n'
    done
    WT_STATUS_PROBE_JOBS=2 wt_run_status_probes "$dir" <<< "$input"

    for i in 0 1 2 3 4 5 6 7; do
        assert_equal "$(cat "$dir/$i")" "dirty"
    done
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

# =============================================================================
# Tests for wt_read_git_config()
# =============================================================================

# --- Core behavior ---

@test "wt_read_git_config reads all required keys from local git config" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    # Clear variables that were set when wt-common was sourced in setup()
    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    wt_read_git_config

    # mainRepoRoot is auto-derived from git-common-dir
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_WORKTREES_BASE" "/worktrees"
    assert_equal "$WT_IDEA_FILES_BASE" "/idea"
    assert_equal "$WT_BASE_BRANCH" "develop"
}

@test "wt_read_git_config returns failure outside a git repo" {
    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$non_git_dir"
    run wt_read_git_config
    assert_failure

    assert_equal "${WT_MAIN_REPO_ROOT:-}" ""
    assert_equal "${WT_WORKTREES_BASE:-}" ""
    assert_equal "${WT_IDEA_FILES_BASE:-}" ""
    assert_equal "${WT_BASE_BRANCH:-}" ""
}

@test "wt_read_git_config returns failure when no wt keys are set" {
    local repo
    repo=$(create_mock_repo)

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run --separate-stderr wt_read_git_config

    assert_failure
    assert_equal "$stderr" ""
    assert_equal "${WT_MAIN_REPO_ROOT:-}" ""
}

@test "wt_read_git_config returns failure when wt.enabled is not true" {
    local repo
    repo=$(create_mock_repo)

    # Set all required keys but don't enable
    set_wt_git_config "$repo" \
        "wt.worktreesBase" "/worktrees" \
        "wt.ideaFilesBase" "/idea" \
        "wt.baseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run wt_read_git_config
    assert_failure

    assert_equal "${WT_WORKTREES_BASE:-}" ""
    assert_equal "${WT_BASE_BRANCH:-}" ""
}

@test "wt_read_git_config returns failure when wt.enabled is false" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config "$repo" \
        "wt.enabled" "false" \
        "wt.worktreesBase" "/worktrees" \
        "wt.ideaFilesBase" "/idea" \
        "wt.baseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run wt_read_git_config
    assert_failure

    assert_equal "${WT_WORKTREES_BASE:-}" ""
}

@test "wt_read_git_config supersedes env variables" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "from-git"

    export WT_BASE_BRANCH="from-env"
    export WT_MAIN_REPO_ROOT="/env-main"
    export WT_WORKTREES_BASE="/env-wt"
    export WT_IDEA_FILES_BASE="/env-idea"

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_BASE_BRANCH" "from-git"
    # mainRepoRoot auto-derived, supersedes env
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

# --- Validation ---

@test "wt_read_git_config warns on partial config and applies nothing" {
    local repo
    repo=$(create_mock_repo)

    # Set only one of three required keys (plus enabled gate)
    set_wt_git_config "$repo" "wt.enabled" "true" "wt.baseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run --separate-stderr bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        wt_read_git_config || true
        echo "WT_BASE_BRANCH=${WT_BASE_BRANCH:-UNSET}"
        echo "WT_MAIN_REPO_ROOT=${WT_MAIN_REPO_ROOT:-UNSET}"
    '

    assert_success
    [[ "$stderr" == *"incomplete git local config"* ]] || fail "Expected partial config warning, got: $stderr"
    [[ "$stderr" == *"wt.worktreesBase"* ]] || fail "Expected missing key name in warning, got: $stderr"
}

@test "wt_read_git_config warns listing specific missing keys" {
    local repo
    repo=$(create_mock_repo)

    # Set 1 of 3 required keys (baseBranch present, worktreesBase + ideaFilesBase missing)
    set_wt_git_config "$repo" "wt.enabled" "true" "wt.baseBranch" "develop"

    cd "$repo"
    run --separate-stderr bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        wt_read_git_config || true
    '

    assert_success
    [[ "$stderr" == *"wt.worktreesBase"* ]] || fail "Expected wt.worktreesBase in missing list, got: $stderr"
    [[ "$stderr" == *"wt.ideaFilesBase"* ]] || fail "Expected wt.ideaFilesBase in missing list, got: $stderr"
    # These should NOT be listed as missing
    [[ "$stderr" != *"wt.mainRepoRoot"* ]] || fail "wt.mainRepoRoot should not be listed as missing (it is auto-derived)"
    [[ "$stderr" != *"wt.baseBranch"* ]] || fail "wt.baseBranch should not be listed as missing"
}

@test "wt_read_git_config returns failure on incomplete config" {
    local repo
    repo=$(create_mock_repo)

    # Set 2 of 3 required keys (missing ideaFilesBase)
    set_wt_git_config "$repo" \
        "wt.enabled" "true" \
        "wt.worktreesBase" "/worktrees" \
        "wt.baseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run --separate-stderr bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        wt_read_git_config
    '

    assert_failure
    [[ "$stderr" == *"incomplete git local config"* ]] || fail "Expected partial config warning, got: $stderr"
    [[ "$stderr" == *"wt.ideaFilesBase"* ]] || fail "Expected wt.ideaFilesBase in missing list, got: $stderr"
}

# --- Optional keys ---

@test "wt_read_git_config applies optional keys when required keys are present" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"
    set_wt_git_config "$repo" \
        "wt.activeWorktree" "/active/wt" \
        "wt.metadataPatterns" ".idea .ijwb .vscode"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH
    unset WT_ACTIVE_WORKTREE WT_METADATA_PATTERNS

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_ACTIVE_WORKTREE" "/active/wt"
    assert_equal "$WT_METADATA_PATTERNS" ".idea .ijwb .vscode"
}

@test "wt_read_git_config handles values with spaces" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"
    set_wt_git_config "$repo" "wt.metadataPatterns" ".idea .ijwb .vscode"

    unset WT_METADATA_PATTERNS

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_METADATA_PATTERNS" ".idea .ijwb .vscode"
}

# --- Case insensitivity ---

@test "wt_read_git_config is case-insensitive for key names" {
    local repo
    repo=$(create_mock_repo)

    # git config normalizes section names to lowercase but preserves
    # subsection case. For our flat wt.* keys, git stores them lowercase.
    # We test by writing directly to .git/config with mixed case section.
    git -C "$repo" config --local "wt.enabled" "true"
    git -C "$repo" config --local "wt.WorktreesBase" "/worktrees"
    git -C "$repo" config --local "wt.ideafilesbase" "/idea"
    git -C "$repo" config --local "wt.BaseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_WORKTREES_BASE" "/worktrees"
    assert_equal "$WT_IDEA_FILES_BASE" "/idea"
    assert_equal "$WT_BASE_BRANCH" "develop"
}

# --- Worktree support ---

@test "wt_read_git_config reads config from worktree" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    # Create a worktree
    create_branch "$repo" "feature-wt"
    local wt_path="$BATS_TEST_TMPDIR/wt-feature"
    create_worktree "$repo" "$wt_path" "feature-wt"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$wt_path"
    wt_read_git_config

    # mainRepoRoot auto-derived via git-common-dir resolves to the main repo,
    # even when CWD is inside a worktree
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_WORKTREES_BASE" "/worktrees"
    assert_equal "$WT_IDEA_FILES_BASE" "/idea"
    assert_equal "$WT_BASE_BRANCH" "develop"
}

# --- Precedence integration tests ---

@test "git local config takes precedence over .conf file" {
    local repo
    repo=$(create_mock_repo)

    # Set up .conf file via context system
    create_test_context "myctx" "$repo"

    # Set git config with different values
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    wt_read_config --force

    # Git config should win — mainRepoRoot auto-derived, rest from git config
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_WORKTREES_BASE" "/git-wt"
    assert_equal "$WT_IDEA_FILES_BASE" "/git-idea"
    assert_equal "$WT_BASE_BRANCH" "git-branch"
}

@test "conf file fills gaps not covered by git config" {
    local repo
    repo=$(create_mock_repo)

    # Set up .conf file with all values
    create_test_context "myctx" "$repo"

    # Set all 3 required git config keys but no optional keys
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    wt_read_config --force

    # Git config wins for required keys
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_BASE_BRANCH" "git-branch"

    # .conf file fills optional keys (WT_ACTIVE_WORKTREE is set in the .conf)
    local norm_test_home
    norm_test_home="$(cd "$TEST_HOME" && pwd -P)"
    assert_equal "$WT_ACTIVE_WORKTREE" "$norm_test_home/active"
}

@test "partial git config falls back to .conf entirely" {
    local repo
    repo=$(create_mock_repo)

    # Set up .conf file with all values
    create_test_context "myctx" "$repo"

    # Set only 1 of 3 required git config keys (incomplete, but enabled)
    set_wt_git_config "$repo" "wt.enabled" "true" "wt.baseBranch" "git-branch"

    cd "$repo"
    wt_read_config --force 2>/dev/null

    # Since git config was incomplete, .conf values should be used
    local norm_repo_path
    norm_repo_path="$(cd "$repo" && pwd -P)"
    assert_equal "$WT_MAIN_REPO_ROOT" "$norm_repo_path"
    assert_equal "$WT_BASE_BRANCH" "main"
}

# --- Auto-derivation and explicit override of mainRepoRoot ---

@test "wt_read_git_config auto-derives mainRepoRoot from git-common-dir" {
    local repo
    repo=$(create_mock_repo)

    # Only set the 3 required keys, no wt.mainRepoRoot
    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    unset WT_MAIN_REPO_ROOT

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

@test "wt_read_git_config auto-derives mainRepoRoot correctly from worktree" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    create_branch "$repo" "feature-derive"
    local wt_path="$BATS_TEST_TMPDIR/wt-derive"
    create_worktree "$repo" "$wt_path" "feature-derive"

    unset WT_MAIN_REPO_ROOT

    # CWD is the worktree, but mainRepoRoot should resolve to the main repo
    cd "$wt_path"
    wt_read_git_config

    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

# =============================================================================
# Tests for wt_read_config() orchestrator
# =============================================================================

# --- Default mode (ordered) ---

@test "wt_read_config default mode loads git config then context" {
    local repo
    repo=$(create_mock_repo)

    create_test_context "myctx" "$repo"
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    wt_read_config --force

    # Git config wins for required keys
    assert_equal "$WT_WORKTREES_BASE" "/git-wt"
    assert_equal "$WT_BASE_BRANCH" "git-branch"
    # Context fills gaps (WT_ACTIVE_WORKTREE from .conf)
    assert [ -n "$WT_ACTIVE_WORKTREE" ]
}

@test "wt_read_config default mode falls back to context when not in git repo" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"

    cd "$non_git_dir"
    wt_read_config --force

    # Should get context values since git config is unavailable
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_BASE_BRANCH" "main"
}

@test "wt_read_config default mode falls back to context when wt.enabled is not true" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    # Set git config but don't enable
    set_wt_git_config "$repo" \
        "wt.worktreesBase" "/git-wt" \
        "wt.ideaFilesBase" "/git-idea" \
        "wt.baseBranch" "git-branch"

    cd "$repo"
    wt_read_config --force

    # Should get context values since git config is not enabled
    assert_equal "$WT_BASE_BRANCH" "main"
}

# --- --mode=git ---

@test "wt_read_config --mode=git loads only git config" {
    local repo
    repo=$(create_mock_repo)

    create_test_context "myctx" "$repo"
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    wt_read_config --mode=git --force

    assert_equal "$WT_WORKTREES_BASE" "/git-wt"
    # Context values should NOT be loaded
    assert_equal "${WT_CONTEXT_NAME:-}" ""
}

# --- --mode=context ---

@test "wt_read_config --mode=context loads only context config" {
    local repo
    repo=$(create_mock_repo)

    create_test_context "myctx" "$repo"
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    wt_read_config --mode=context --force

    # Should get context values, NOT git config
    assert_equal "$WT_BASE_BRANCH" "main"
    assert_equal "$WT_CONTEXT_NAME" "myctx"
}

# --- --force ---

@test "wt_read_config --force clears stale config-loaded variables" {
    # Simulate config-loaded values: set without the export attribute
    unset WT_BASE_BRANCH WT_WORKTREES_BASE
    WT_BASE_BRANCH="stale-value"
    WT_WORKTREES_BASE="stale-wt"

    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"

    # No context configured, no git config — force should clear vars
    # (returns non-zero since both sources fail) and re-apply defaults
    rm -f "$HOME/.wt/current"
    wt_read_config --force || true

    # Variables should be reset to the fallback defaults (not "stale-value")
    assert_equal "${WT_BASE_BRANCH:-}" "master"
    assert_equal "${WT_WORKTREES_BASE:-}" "$HOME/.wt/repos/repo/worktrees"
}

@test "wt_read_config --force re-applies fallback defaults after load failure" {
    unset WT_MAIN_REPO_ROOT WT_ACTIVE_WORKTREE

    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"

    rm -f "$HOME/.wt/current"
    wt_read_config --force || true

    assert_equal "${WT_MAIN_REPO_ROOT:-}" "$HOME/.wt/repos/repo/base"
    assert_equal "${WT_ACTIVE_WORKTREE:-}" "$HOME/Development/java"
}

@test "wt_read_config --force preserves user-exported WT_* overrides" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    export WT_BASE_BRANCH="user-override"

    cd "$repo"
    wt_read_config --force

    # Exported override survives the forced reload...
    assert_equal "$WT_BASE_BRANCH" "user-override"
    # ...while non-exported variables still reload from the context config
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

@test "wt_read_config --force keeps user overrides visible to child processes" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    export WT_BASE_BRANCH="user-override"

    cd "$repo"
    wt_read_config --force

    # bin/wt-* run as child processes and must still see the override
    run bash -c 'printf "%s" "${WT_BASE_BRANCH:-}"'
    assert_output "user-override"
}

@test "wt_read_config without --force preserves existing variables" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    export WT_BASE_BRANCH="pre-existing"

    cd "$repo"
    wt_read_config

    # Without force, pre-existing env var should be preserved
    # (wt_read_context_config only sets vars not already set)
    assert_equal "$WT_BASE_BRANCH" "pre-existing"
}

# --- WT_CONFIG_SOURCE recording ---

@test "wt_read_config records WT_CONFIG_SOURCE=git when git config loads" {
    local repo
    repo=$(create_mock_repo)

    create_test_context "myctx" "$repo"
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    cd "$repo"
    wt_read_config --force

    assert_equal "$WT_CONFIG_SOURCE" "git"
}

@test "wt_read_config records WT_CONFIG_SOURCE=context when only context loads" {
    local repo
    repo=$(create_mock_repo)
    create_test_context "myctx" "$repo"

    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"

    cd "$non_git_dir"
    wt_read_config --force

    assert_equal "$WT_CONFIG_SOURCE" "context"
}

@test "wt_read_config leaves WT_CONFIG_SOURCE unset when no source loads" {
    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"

    rm -f "$HOME/.wt/current"
    wt_read_config --force || true

    assert_equal "${WT_CONFIG_SOURCE:-}" ""
}

@test "wt_read_config leaves WT_CONFIG_SOURCE unset when current names a missing .conf" {
    mkdir -p "$HOME/.wt/repos"
    echo "ghost" > "$HOME/.wt/current"

    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"

    wt_read_config --force || true

    assert_equal "${WT_CONFIG_SOURCE:-}" ""
    # Context name is still recorded so errors can point at the stale context
    assert_equal "${WT_CONTEXT_NAME:-}" "ghost"
}

# --- Cross-context gap-fill scoping ---

@test "ordered mode does not gap-fill optional keys from a different context" {
    local repo_a repo_b
    repo_a=$(create_mock_repo "$BATS_TEST_TMPDIR/repoA")
    repo_b=$(create_mock_repo "$BATS_TEST_TMPDIR/repoB")

    # Current context belongs to repo B; its .conf sets WT_ACTIVE_WORKTREE
    create_test_context "ctxB" "$repo_b"
    echo 'WT_SEED_FILES="ctxb.bazelrc"' >> "$HOME/.wt/repos/ctxB.conf"

    # Repo A is wt.enabled with its own context name but no wt.activeWorktree
    set_wt_git_config_required "$repo_a" "/git-wt" "/git-idea" "git-branch"
    set_wt_git_config "$repo_a" "wt.contextName" "ctxA"

    cd "$repo_a"
    wt_read_config --force

    # Required keys come from repo A's git config
    assert_equal "$WT_WORKTREES_BASE" "/git-wt"
    assert_equal "$WT_BASE_BRANCH" "git-branch"
    assert_equal "$WT_CONTEXT_NAME" "ctxA"

    # Optional keys must NOT be borrowed from ctxB's .conf
    local norm_test_home
    norm_test_home="$(cd "$TEST_HOME" && pwd -P)"
    [[ "$WT_ACTIVE_WORKTREE" != "$norm_test_home/active" ]] || \
        fail "WT_ACTIVE_WORKTREE borrowed from ctxB: $WT_ACTIVE_WORKTREE"
    assert_equal "$WT_ACTIVE_WORKTREE" "$HOME/Development/java"
    assert_equal "${WT_SEED_FILES:-}" ""
}

@test "ordered mode still gap-fills when git contextName matches current context" {
    local repo
    repo=$(create_mock_repo)

    create_test_context "myctx" "$repo"
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"
    set_wt_git_config "$repo" "wt.contextName" "myctx"

    cd "$repo"
    wt_read_config --force

    assert_equal "$WT_WORKTREES_BASE" "/git-wt"
    local norm_test_home
    norm_test_home="$(cd "$TEST_HOME" && pwd -P)"
    assert_equal "$WT_ACTIVE_WORKTREE" "$norm_test_home/active"
}

# =============================================================================
# Tests for wt_read_context_config() value parsing
# =============================================================================

@test "wt_read_context_config strips trailing whitespace after quoted value" {
    mkdir -p "$HOME/.wt/repos"
    printf 'WT_BASE_BRANCH="develop"   \n' > "$HOME/.wt/repos/wsctx.conf"
    echo "wsctx" > "$HOME/.wt/current"

    unset WT_BASE_BRANCH WT_CONTEXT_NAME
    wt_read_context_config

    assert_equal "$WT_BASE_BRANCH" "develop"
}

@test "wt_read_context_config strips inline comment after quoted value" {
    mkdir -p "$HOME/.wt/repos"
    printf 'WT_BASE_BRANCH="develop"  # deployment branch\n' > "$HOME/.wt/repos/cmtctx.conf"
    echo "cmtctx" > "$HOME/.wt/current"

    unset WT_BASE_BRANCH WT_CONTEXT_NAME
    wt_read_context_config

    assert_equal "$WT_BASE_BRANCH" "develop"
}

@test "wt_read_context_config preserves whitespace inside quoted value" {
    mkdir -p "$HOME/.wt/repos"
    printf 'WT_METADATA_PATTERNS=".idea .ijwb"\n' > "$HOME/.wt/repos/patctx.conf"
    echo "patctx" > "$HOME/.wt/current"

    unset WT_METADATA_PATTERNS WT_CONTEXT_NAME
    wt_read_context_config

    assert_equal "$WT_METADATA_PATTERNS" ".idea .ijwb"
}

# =============================================================================
# Tests for _wt_prune_nested_paths()
# =============================================================================

@test "_wt_prune_nested_paths removes nested paths" {
    result=$(printf '%s\n' "/a/.ijwb" "/a/.ijwb/.idea" "/b/.idea" | _wt_prune_nested_paths)
    assert_equal "$result" "$(printf '%s\n' "/a/.ijwb" "/b/.idea")"
}

@test "_wt_prune_nested_paths keeps siblings" {
    result=$(printf '%s\n' "/a/.idea" "/a/.ijwb" | _wt_prune_nested_paths)
    assert_equal "$result" "$(printf '%s\n' "/a/.idea" "/a/.ijwb")"
}

@test "_wt_prune_nested_paths handles empty input" {
    result=$(printf '' | _wt_prune_nested_paths)
    assert_equal "$result" ""
}

@test "_wt_prune_nested_paths handles single path" {
    result=$(printf '%s\n' "/a/.idea" | _wt_prune_nested_paths)
    assert_equal "$result" "/a/.idea"
}

@test "_wt_prune_nested_paths handles multi-level nesting" {
    result=$(printf '%s\n' "/a/.ijwb" "/a/.ijwb/.idea" "/a/.ijwb/.idea/.run" | _wt_prune_nested_paths)
    assert_equal "$result" "/a/.ijwb"
}

# =============================================================================
# Tests for _wt_is_valid_path_config()
# =============================================================================

@test "_wt_is_valid_path_config accepts absolute path" {
    run _wt_is_valid_path_config "/home/user/worktrees"
    assert_success
}

@test "_wt_is_valid_path_config accepts absolute path with spaces" {
    run _wt_is_valid_path_config "/tmp/my worktrees"
    assert_success
}

@test "_wt_is_valid_path_config rejects relative path" {
    run _wt_is_valid_path_config "worktrees/foo"
    assert_failure
}

@test "_wt_is_valid_path_config rejects dot-relative path" {
    run _wt_is_valid_path_config "./worktrees"
    assert_failure
}

@test "_wt_is_valid_path_config rejects parent-relative path" {
    run _wt_is_valid_path_config "../worktrees"
    assert_failure
}

@test "_wt_is_valid_path_config rejects glob with asterisk" {
    run _wt_is_valid_path_config "/tmp/wt-*"
    assert_failure
}

@test "_wt_is_valid_path_config rejects glob with question mark" {
    run _wt_is_valid_path_config "/tmp/wt-?"
    assert_failure
}

@test "_wt_is_valid_path_config rejects glob with bracket" {
    run _wt_is_valid_path_config "/tmp/wt-[0-9]"
    assert_failure
}

@test "_wt_is_valid_path_config rejects empty string" {
    run _wt_is_valid_path_config ""
    assert_failure
}

# =============================================================================
# Tests for wt_require_valid_config()
# =============================================================================

@test "wt_require_valid_config passes when a source loaded and repo is a git work tree" {
    local repo
    repo=$(create_mock_repo)

    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="$repo"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_success
    assert_equal "$stderr" ""
}

@test "wt_require_valid_config fails for relative WT_MAIN_REPO_ROOT" {
    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="relative/repo"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"WT_MAIN_REPO_ROOT"* ]]
    [[ "$stderr" == *"relative/repo"* ]]
}

@test "wt_require_valid_config fails for glob in WT_WORKTREES_BASE" {
    local repo
    repo=$(create_mock_repo)

    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="$repo"
    export WT_WORKTREES_BASE="/home/user/wt-*"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"WT_WORKTREES_BASE"* ]]
}

@test "wt_require_valid_config reports all invalid vars" {
    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="relative/repo"
    export WT_WORKTREES_BASE="../worktrees"
    export WT_IDEA_FILES_BASE="/valid/path"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"WT_MAIN_REPO_ROOT"* ]]
    [[ "$stderr" == *"WT_WORKTREES_BASE"* ]]
}

@test "wt_require_valid_config shows config file path when context is set" {
    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="relative/repo"
    export WT_WORKTREES_BASE="/valid/path"
    export WT_IDEA_FILES_BASE="/valid/path"
    export WT_CONTEXT_NAME="mycontext"

    # Create the config file so the message references it
    mkdir -p "$HOME/.wt/repos"
    echo 'WT_MAIN_REPO_ROOT="relative/repo"' > "$HOME/.wt/repos/mycontext.conf"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"mycontext.conf"* ]]
}

@test "wt_require_valid_config skips empty path variables when a source loaded" {
    local repo
    repo=$(create_mock_repo)

    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="$repo"
    unset WT_WORKTREES_BASE
    unset WT_IDEA_FILES_BASE

    run --separate-stderr wt_require_valid_config
    assert_success
}

@test "wt_require_valid_config fails when no config source loaded" {
    unset WT_CONFIG_SOURCE WT_CONTEXT_NAME
    export WT_MAIN_REPO_ROOT="/home/user/repo"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"No wt configuration loaded"* ]]
    [[ "$stderr" == *"wt context add"* ]]
}

@test "wt_require_valid_config names the missing .conf for a stale current context" {
    unset WT_CONFIG_SOURCE
    export WT_CONTEXT_NAME="ghost"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"ghost"* ]]
    [[ "$stderr" == *"ghost.conf"* ]]
    [[ "$stderr" == *"wt context add"* ]]
}

@test "wt_require_valid_config fails when WT_MAIN_REPO_ROOT does not exist" {
    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="$BATS_TEST_TMPDIR/gone"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"does not exist"* ]]
    [[ "$stderr" == *"$BATS_TEST_TMPDIR/gone"* ]]
}

@test "wt_require_valid_config fails when WT_MAIN_REPO_ROOT is not a git work tree" {
    local not_git="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$not_git"

    export WT_CONFIG_SOURCE="context"
    export WT_MAIN_REPO_ROOT="$not_git"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"not a git repository or worktree"* ]]
}

# =============================================================================
# Tests for wt_atomic_symlink()
# =============================================================================

@test "wt_atomic_symlink creates a new symlink where none existed" {
    local target_dir="$BATS_TEST_TMPDIR/target"
    local link_path="$BATS_TEST_TMPDIR/mylink"
    mkdir -p "$target_dir"

    run wt_atomic_symlink "$target_dir" "$link_path"
    assert_success
    assert [ -L "$link_path" ]
    assert_equal "$(readlink "$link_path")" "$target_dir"
}

@test "wt_atomic_symlink replaces an existing symlink" {
    local target1="$BATS_TEST_TMPDIR/target1"
    local target2="$BATS_TEST_TMPDIR/target2"
    local link_path="$BATS_TEST_TMPDIR/mylink"
    mkdir -p "$target1" "$target2"

    ln -s "$target1" "$link_path"
    assert_equal "$(readlink "$link_path")" "$target1"

    run wt_atomic_symlink "$target2" "$link_path"
    assert_success
    assert [ -L "$link_path" ]
    assert_equal "$(readlink "$link_path")" "$target2"
}

@test "wt_atomic_symlink creates parent directories" {
    local target_dir="$BATS_TEST_TMPDIR/target"
    local link_path="$BATS_TEST_TMPDIR/nested/deep/dir/mylink"
    mkdir -p "$target_dir"

    assert [ ! -d "$BATS_TEST_TMPDIR/nested/deep/dir" ]

    run wt_atomic_symlink "$target_dir" "$link_path"
    assert_success
    assert [ -L "$link_path" ]
    assert_equal "$(readlink "$link_path")" "$target_dir"
}

@test "wt_atomic_symlink does not leave temp link on success" {
    local target_dir="$BATS_TEST_TMPDIR/target"
    local link_path="$BATS_TEST_TMPDIR/mylink"
    mkdir -p "$target_dir"

    wt_atomic_symlink "$target_dir" "$link_path"

    # No .wt-tmp.* files should remain in the parent directory
    local leftover
    leftover=$(find "$(dirname "$link_path")" -maxdepth 1 -name "*.wt-tmp.*" 2>/dev/null)
    assert_equal "$leftover" ""
}


# =============================================================================
# Tests for wt_is_worktree_root(), wt_resolve_worktree(), wt_resolve_and_validate()
# =============================================================================

setup_resolver_fixture() {
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")
    export WT_MAIN_REPO_ROOT="$REPO"
    create_branch "$REPO" "docs"
    DOCS_WT="$BATS_TEST_TMPDIR/worktrees/docs"
    create_worktree "$REPO" "$DOCS_WT" "docs"
    DOCS_WT="$(cd "$DOCS_WT" && pwd -P)"
}

@test "wt_is_worktree_root accepts main repo and registered worktree roots" {
    setup_resolver_fixture

    run wt_is_worktree_root "$REPO"
    assert_success

    run wt_is_worktree_root "$DOCS_WT"
    assert_success
}

@test "wt_is_worktree_root rejects subdirectories and unrelated directories" {
    setup_resolver_fixture
    mkdir -p "$REPO/docs" "$BATS_TEST_TMPDIR/unrelated"

    run wt_is_worktree_root "$REPO/docs"
    assert_failure

    run wt_is_worktree_root "$BATS_TEST_TMPDIR/unrelated"
    assert_failure

    run wt_is_worktree_root "$BATS_TEST_TMPDIR/does-not-exist"
    assert_failure
}

@test "wt_resolve_worktree prefers branch over same-named non-worktree directory" {
    setup_resolver_fixture
    mkdir -p "$REPO/docs"
    cd "$REPO"

    run wt_resolve_worktree "docs"
    assert_success
    assert_output "$DOCS_WT"
}

@test "wt_resolve_worktree resolves slashed branch names shadowed by a directory" {
    setup_resolver_fixture
    git -C "$REPO" branch "user/feature"
    local slashed_wt="$BATS_TEST_TMPDIR/worktrees/user-feature"
    create_worktree "$REPO" "$slashed_wt" "user/feature"
    slashed_wt="$(cd "$slashed_wt" && pwd -P)"

    mkdir -p "$REPO/user/feature"
    cd "$REPO"

    run wt_resolve_worktree "user/feature"
    assert_success
    assert_output "$slashed_wt"
}

@test "wt_resolve_worktree still resolves registered worktree paths" {
    setup_resolver_fixture

    run wt_resolve_worktree "$DOCS_WT"
    assert_success
    assert_output "$DOCS_WT"

    run wt_resolve_worktree "$REPO"
    assert_success
    assert_output "$REPO"
}

@test "wt_resolve_and_validate rejects repo subdirectory that is not a worktree root" {
    setup_resolver_fixture
    mkdir -p "$REPO/subdir"

    run wt_resolve_and_validate "$REPO/subdir"
    assert_failure
    assert_output --partial "not a git repository or worktree"
}

@test "wt_resolve_and_validate rejects unrelated git repo" {
    setup_resolver_fixture
    local other_repo
    other_repo=$(create_mock_repo "$BATS_TEST_TMPDIR/other_repo")

    run wt_resolve_and_validate "$other_repo"
    assert_failure
    assert_output --partial "not a git repository or worktree"
}

@test "wt_resolve_and_validate falls through directory collision to branch" {
    setup_resolver_fixture
    mkdir -p "$REPO/docs"
    cd "$REPO"

    run wt_resolve_and_validate "docs"
    assert_success
    assert_output "$DOCS_WT"
}

# =============================================================================
# Tests for _wt_md5_string()
# =============================================================================

@test "_wt_md5_string hashes the string itself, not a file" {
    run _wt_md5_string "hello"
    assert_success
    assert_output "5d41402abc4b2a76b9719d911017c592"
}

@test "_wt_md5_string produces bazel-style output base names for paths" {
    # Bazel names output bases md5("/absolute/workspace/path")
    run _wt_md5_string "/Users/someone/worktrees/feature/foo"
    assert_success
    assert_output --regexp '^[0-9a-f]{32}$'
}

@test "_wt_md5_string handles the empty string" {
    run _wt_md5_string ""
    assert_success
    assert_output "d41d8cd98f00b204e9800998ecf8427e"
}

@test "_wt_md5_string falls back to md5sum when md5 is unavailable" {
    if ! command -v md5sum >/dev/null 2>&1; then
        skip "md5sum not available"
    fi

    # Hide md5 so the md5sum branch is exercised
    md5_path="$(command -v md5 || true)"
    [[ -n "$md5_path" ]] || skip "md5 not on PATH; fallback already default"

    mkdir -p "$BATS_TEST_TMPDIR/restricted-bin"
    for tool in md5sum printf cut command bash sh; do
        tool_path="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$tool_path" && -x "$tool_path" ]] && ln -sf "$tool_path" "$BATS_TEST_TMPDIR/restricted-bin/$tool"
    done

    run env PATH="$BATS_TEST_TMPDIR/restricted-bin" bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'" 2>/dev/null
        _wt_md5_string "hello"
    '
    assert_success
    assert_output --partial "5d41402abc4b2a76b9719d911017c592"
}

# =============================================================================
# Tests for wt_worktree_entries()
# =============================================================================

setup_entries_fixture() {
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")
    export WT_MAIN_REPO_ROOT="$REPO"
    create_branch "$REPO" "feature-a"
    WT_A="$BATS_TEST_TMPDIR/worktrees/feature-a"
    create_worktree "$REPO" "$WT_A" "feature-a"
    WT_A="$(cd "$WT_A" && pwd -P)"
}

@test "wt_worktree_entries emits path, kind, and branch per worktree" {
    setup_entries_fixture

    run wt_worktree_entries
    assert_success
    assert_line "$(printf '%s\t%s\t%s' "$REPO" "branch" "main")"
    assert_line "$(printf '%s\t%s\t%s' "$WT_A" "branch" "feature-a")"
}

@test "wt_worktree_entries marks detached worktrees with empty branch" {
    setup_entries_fixture
    local det="$BATS_TEST_TMPDIR/worktrees/det"
    (cd "$REPO" && git worktree add --detach "$det") >/dev/null 2>&1
    det="$(cd "$det" && pwd -P)"

    run wt_worktree_entries
    assert_success
    assert_line "$(printf '%s\t%s\t' "$det" "detached")"

    # The empty branch field must survive an IFS=tab read: tab is IFS
    # whitespace, so an empty field anywhere but last would be swallowed
    local wt_path kind branch found=false
    while IFS=$'\t' read -r wt_path kind branch; do
        if [[ "$wt_path" == "$det" ]]; then
            found=true
            assert_equal "$kind" "detached"
            assert_equal "$branch" ""
        fi
    done < <(wt_worktree_entries)
    [[ "$found" == true ]] || fail "detached worktree $det not enumerated"
}

@test "wt_worktree_entries passes through the registered path for missing worktrees" {
    setup_entries_fixture
    rm -rf "$WT_A"

    run wt_worktree_entries
    assert_success
    assert_line "$(printf '%s\t%s\t%s' "$WT_A" "branch" "feature-a")"
}

@test "wt_worktree_entries accepts an explicit repo root argument" {
    setup_entries_fixture
    local other
    other=$(create_mock_repo "$BATS_TEST_TMPDIR/other_repo")

    run wt_worktree_entries --raw "$other"
    assert_success
    assert_line "$(printf '%s\t%s\t%s' "$other" "branch" "main")"
    refute_output --partial "feature-a"
}

# =============================================================================
# Tests for _wt_readlink_abs()
# =============================================================================

@test "_wt_readlink_abs resolves absolute symlink targets" {
    mkdir -p "$BATS_TEST_TMPDIR/target-dir"
    local physical
    physical="$(cd "$BATS_TEST_TMPDIR/target-dir" && pwd -P)"
    ln -s "$physical" "$BATS_TEST_TMPDIR/abs-link"

    run _wt_readlink_abs "$BATS_TEST_TMPDIR/abs-link"
    assert_success
    assert_output "$physical"
}

@test "_wt_readlink_abs anchors relative targets at the symlink parent" {
    mkdir -p "$BATS_TEST_TMPDIR/parent/target-dir"
    ln -s "target-dir" "$BATS_TEST_TMPDIR/parent/rel-link"

    run _wt_readlink_abs "$BATS_TEST_TMPDIR/parent/rel-link"
    assert_success
    assert_output "$(cd "$BATS_TEST_TMPDIR/parent" && pwd -P)/target-dir"
}

@test "_wt_readlink_abs fails on non-symlinks" {
    mkdir -p "$BATS_TEST_TMPDIR/plain-dir"

    run _wt_readlink_abs "$BATS_TEST_TMPDIR/plain-dir"
    assert_failure
}

# =============================================================================
# Tests for wt_adopted_worktree_paths()
# =============================================================================

@test "wt_adopted_worktree_paths lists only adopted worktrees" {
    setup_entries_fixture
    create_branch "$REPO" "feature-b"
    local wt_b="$BATS_TEST_TMPDIR/worktrees/feature-b"
    create_worktree "$REPO" "$wt_b" "feature-b"
    wt_b="$(cd "$wt_b" && pwd -P)"

    # Adopt only feature-a (marker beside the gitdir file in .git/worktrees)
    local git_dir
    git_dir="$(git -C "$WT_A" rev-parse --git-dir)"
    [[ "$git_dir" == /* ]] || git_dir="$(cd "$WT_A" && cd "$git_dir" && pwd -P)"
    mkdir -p "$git_dir/wt"
    echo "test" > "$git_dir/wt/adopted"

    run wt_adopted_worktree_paths
    assert_success
    assert_line "$WT_A"
    refute_line "$wt_b"
    refute_line "$REPO"
}

@test "wt_adopted_worktree_paths returns nothing when no worktrees exist" {
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/solo_repo")
    export WT_MAIN_REPO_ROOT="$REPO"

    run wt_adopted_worktree_paths
    assert_success
    assert_output ""
}

# =============================================================================
# Tests for wt_worktree_prefix_and_badge()
# =============================================================================

@test "wt_worktree_prefix_and_badge marks linked adopted worktree with * and no badge" {
    wt_worktree_prefix_and_badge "/wt/a" "/main" "/wt/a" "/wt/a"
    assert_equal "$WT_ROW_PREFIX" "* "
    assert_equal "$WT_ROW_BADGE" ""
}

@test "wt_worktree_prefix_and_badge adds unadopted badge for unadopted worktrees" {
    wt_worktree_prefix_and_badge "/wt/a" "/main" "" ""
    assert_equal "$WT_ROW_PREFIX" "  "
    assert_equal "$WT_ROW_BADGE" "[unadopted] "

    wt_worktree_prefix_and_badge "/wt/a" "/main" "/wt/a" ""
    assert_equal "$WT_ROW_PREFIX" "* "
    assert_equal "$WT_ROW_BADGE" "[unadopted] "
}

@test "wt_worktree_prefix_and_badge never badges the main repo" {
    wt_worktree_prefix_and_badge "/main" "/main" "" ""
    assert_equal "$WT_ROW_PREFIX" "  "
    assert_equal "$WT_ROW_BADGE" ""
}

@test "wt_format_worktree uses the supplied branch instead of rev-parse" {
    local repo
    repo=$(create_mock_repo)

    # Actual branch is "main" — a passed branch must win (no git spawn needed)
    run wt_format_worktree "$repo" "" "" "false" "passed-branch"
    assert_success
    assert_output --partial "(passed-branch)"
}

# =============================================================================
# Tests for wt_worktree_branch_list()
# =============================================================================

@test "wt_worktree_branch_list lists branches of all worktrees" {
    setup_entries_fixture

    run wt_worktree_branch_list
    assert_success
    assert_line "main"
    assert_line "feature-a"
}

@test "wt_worktree_branch_list exclude_main omits the main repo branch" {
    setup_entries_fixture

    run wt_worktree_branch_list exclude_main
    assert_success
    refute_line "main"
    assert_line "feature-a"
}

@test "wt_worktree_branch_list skips detached and missing worktrees" {
    setup_entries_fixture
    (cd "$REPO" && git worktree add --detach "$BATS_TEST_TMPDIR/worktrees/det") >/dev/null 2>&1
    create_branch "$REPO" "feature-gone"
    create_worktree "$REPO" "$BATS_TEST_TMPDIR/worktrees/feature-gone" "feature-gone"
    rm -rf "$BATS_TEST_TMPDIR/worktrees/feature-gone"

    run wt_worktree_branch_list
    assert_success
    assert_line "feature-a"
    refute_line "feature-gone"
}

# =============================================================================
# Tests for wt_source() default lib dir
# =============================================================================

@test "wt_source falls back to ~/.wt/lib when LIB_DIR is unset" {
    echo 'TEST_DEFAULT_LIB_LOADED=true' > "$TEST_HOME/.wt/lib/test-default-lib"

    unset LIB_DIR
    wt_source "test-default-lib"

    assert_equal "$TEST_DEFAULT_LIB_LOADED" "true"
}

# =============================================================================
# Tests for wt_conf_get()
# =============================================================================

@test "wt_conf_get reads a quoted value" {
    printf '# comment\nWT_MAIN_REPO_ROOT="/tmp/repo"\n' > "$BATS_TEST_TMPDIR/x.conf"

    run wt_conf_get "$BATS_TEST_TMPDIR/x.conf" WT_MAIN_REPO_ROOT
    assert_success
    assert_output "/tmp/repo"
}

@test "wt_conf_get reads an unquoted value" {
    printf 'WT_WORKTREES_BASE=/unquoted/path\n' > "$BATS_TEST_TMPDIR/x.conf"

    run wt_conf_get "$BATS_TEST_TMPDIR/x.conf" WT_WORKTREES_BASE
    assert_success
    assert_output "/unquoted/path"
}

@test "wt_conf_get normalizes trailing whitespace and inline comments" {
    printf 'WT_MAIN_REPO_ROOT="/tmp/repo" \nWT_BASE_BRANCH="main"  # my comment\n' > "$BATS_TEST_TMPDIR/x.conf"

    run wt_conf_get "$BATS_TEST_TMPDIR/x.conf" WT_MAIN_REPO_ROOT
    assert_success
    assert_output "/tmp/repo"

    run wt_conf_get "$BATS_TEST_TMPDIR/x.conf" WT_BASE_BRANCH
    assert_success
    assert_output "main"
}

@test "wt_conf_get uses the first match when a key repeats" {
    printf 'WT_BASE_BRANCH="first"\nWT_BASE_BRANCH="second"\n' > "$BATS_TEST_TMPDIR/x.conf"

    run wt_conf_get "$BATS_TEST_TMPDIR/x.conf" WT_BASE_BRANCH
    assert_success
    assert_output "first"
}

@test "wt_conf_get returns empty for missing key or missing file" {
    printf 'WT_BASE_BRANCH="main"\n' > "$BATS_TEST_TMPDIR/x.conf"

    run wt_conf_get "$BATS_TEST_TMPDIR/x.conf" WT_NOPE
    assert_success
    assert_output ""

    run wt_conf_get "$BATS_TEST_TMPDIR/does-not-exist.conf" WT_BASE_BRANCH
    assert_success
    assert_output ""
}

# =============================================================================
# Tests for wt_find_metadata_dirs()
# =============================================================================

@test "wt_find_metadata_dirs matches dirs and files in one traversal and prunes nested" {
    local root="$BATS_TEST_TMPDIR/scanroot"
    mkdir -p "$root/.ijwb/.idea" "$root/sub/.idea"
    touch "$root/.bazelproject"

    export WT_METADATA_PATTERNS=".ijwb .idea .bazelproject"
    run wt_find_metadata_dirs "$root"
    assert_success
    assert_line "$root/.bazelproject"
    assert_line "$root/.ijwb"
    assert_line "$root/sub/.idea"
    refute_line "$root/.ijwb/.idea"
}

@test "wt_find_metadata_dirs caps scanning at depth 5" {
    local root="$BATS_TEST_TMPDIR/depthroot"
    mkdir -p "$root/a/b/c/d/.idea"
    mkdir -p "$root/a/b/c/d/e/.idea"

    export WT_METADATA_PATTERNS=".idea"
    run wt_find_metadata_dirs "$root"
    assert_success
    assert_line "$root/a/b/c/d/.idea"
    refute_line "$root/a/b/c/d/e/.idea"
}

@test "wt_find_metadata_dirs --follow finds vault symlinks to dirs and files" {
    local src="$BATS_TEST_TMPDIR/linksrc" vault="$BATS_TEST_TMPDIR/linkvault"
    mkdir -p "$src/.idea" "$vault"
    touch "$src/.bazelproject"
    ln -s "$src/.idea" "$vault/.idea"
    ln -s "$src/.bazelproject" "$vault/.bazelproject"

    export WT_METADATA_PATTERNS=".idea .bazelproject"
    run wt_find_metadata_dirs --follow "$vault"
    assert_success
    assert_line "$vault/.idea"
    assert_line "$vault/.bazelproject"
}

@test "wt_find_metadata_dirs is silent for empty patterns or missing root" {
    export WT_METADATA_PATTERNS=""
    run wt_find_metadata_dirs "$BATS_TEST_TMPDIR"
    assert_success
    assert_output ""

    export WT_METADATA_PATTERNS=".idea"
    run wt_find_metadata_dirs "$BATS_TEST_TMPDIR/does-not-exist"
    assert_success
    assert_output ""
}

# =============================================================================
# Tests for wt_find_bin()
# =============================================================================

@test "wt_find_bin searches SCRIPT_DIR, BIN_DIR, ~/.wt/bin in order" {
    local name="wt-fakebin-test"
    mkdir -p "$BATS_TEST_TMPDIR/sdir" "$BATS_TEST_TMPDIR/bdir"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/sdir/$name"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/bdir/$name"
    printf '#!/bin/sh\n' > "$TEST_HOME/.wt/bin/$name"
    chmod +x "$BATS_TEST_TMPDIR/sdir/$name" "$BATS_TEST_TMPDIR/bdir/$name" "$TEST_HOME/.wt/bin/$name"

    export SCRIPT_DIR="$BATS_TEST_TMPDIR/sdir"
    export BIN_DIR="$BATS_TEST_TMPDIR/bdir"

    run wt_find_bin "$name"
    assert_success
    assert_output "$BATS_TEST_TMPDIR/sdir/$name"

    rm "$BATS_TEST_TMPDIR/sdir/$name"
    run wt_find_bin "$name"
    assert_success
    assert_output "$BATS_TEST_TMPDIR/bdir/$name"

    rm "$BATS_TEST_TMPDIR/bdir/$name"
    run wt_find_bin "$name"
    assert_success
    assert_output "$TEST_HOME/.wt/bin/$name"

    rm "$TEST_HOME/.wt/bin/$name"
    run wt_find_bin "$name"
    assert_failure
}

@test "wt_find_bin falls back to PATH lookup" {
    local name="wt-fakepath-test"
    mkdir -p "$BATS_TEST_TMPDIR/pbin"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/pbin/$name"
    chmod +x "$BATS_TEST_TMPDIR/pbin/$name"
    export PATH="$BATS_TEST_TMPDIR/pbin:$PATH"
    unset SCRIPT_DIR BIN_DIR

    run wt_find_bin "$name"
    assert_success
    assert_output "$name"
}

# =============================================================================
# Context helpers live in wt-common (usable without lib/wt-context)
# =============================================================================

@test "context helpers are available from wt-common alone" {
    # This file's setup sources only wt-common, not lib/wt-context
    declare -f wt_list_contexts >/dev/null
    declare -f wt_get_repos_dir >/dev/null
    declare -f wt_get_current_context >/dev/null

    echo 'WT_MAIN_REPO_ROOT="/x"' > "$TEST_HOME/.wt/repos/aaa.conf"
    echo 'WT_MAIN_REPO_ROOT="/y"' > "$TEST_HOME/.wt/repos/bbb.conf"

    run wt_list_contexts
    assert_success
    assert_line --index 0 "aaa"
    assert_line --index 1 "bbb"
}
