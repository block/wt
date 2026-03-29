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

@test "wt_read_config --force clears existing variables" {
    export WT_BASE_BRANCH="stale-value"
    export WT_WORKTREES_BASE="stale-wt"

    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"

    # No context configured, no git config — force should clear vars
    # (returns non-zero since both sources fail, but vars are still cleared)
    rm -f "$HOME/.wt/current"
    wt_read_config --force || true

    # Variables should be cleared (not "stale-value")
    assert_equal "${WT_BASE_BRANCH:-}" ""
    assert_equal "${WT_WORKTREES_BASE:-}" ""
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

@test "wt_require_valid_config passes when all paths are absolute" {
    export WT_MAIN_REPO_ROOT="/home/user/repo"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_success
    assert_equal "$stderr" ""
}

@test "wt_require_valid_config fails for relative WT_MAIN_REPO_ROOT" {
    export WT_MAIN_REPO_ROOT="relative/repo"
    export WT_WORKTREES_BASE="/home/user/worktrees"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"WT_MAIN_REPO_ROOT"* ]]
    [[ "$stderr" == *"relative/repo"* ]]
}

@test "wt_require_valid_config fails for glob in WT_WORKTREES_BASE" {
    export WT_MAIN_REPO_ROOT="/home/user/repo"
    export WT_WORKTREES_BASE="/home/user/wt-*"
    export WT_IDEA_FILES_BASE="/home/user/idea-files"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"WT_WORKTREES_BASE"* ]]
}

@test "wt_require_valid_config reports all invalid vars" {
    export WT_MAIN_REPO_ROOT="relative/repo"
    export WT_WORKTREES_BASE="../worktrees"
    export WT_IDEA_FILES_BASE="/valid/path"

    run --separate-stderr wt_require_valid_config
    assert_failure
    [[ "$stderr" == *"WT_MAIN_REPO_ROOT"* ]]
    [[ "$stderr" == *"WT_WORKTREES_BASE"* ]]
}

@test "wt_require_valid_config shows config file path when context is set" {
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

@test "wt_require_valid_config skips empty variables" {
    unset WT_MAIN_REPO_ROOT
    unset WT_WORKTREES_BASE
    unset WT_IDEA_FILES_BASE

    run --separate-stderr wt_require_valid_config
    assert_success
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

