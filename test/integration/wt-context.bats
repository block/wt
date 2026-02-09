#!/usr/bin/env bats

# Integration tests for bin/wt-context

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repos
    REPO1=$(create_mock_repo "$BATS_TEST_TMPDIR/repo1")
    REPO2=$(create_mock_repo "$BATS_TEST_TMPDIR/repo2")
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Context listing tests (--list)
# =============================================================================

@test "wt-context --list shows no contexts when none exist" {
    run "$TEST_HOME/.wt/bin/wt-context" --list
    assert_success
    # Should indicate no contexts are configured
    assert_output --partial "No contexts"
}

@test "wt-context --list shows single context with repo path" {
    create_test_context "ctx1" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" --list
    assert_success
    assert_output --partial "ctx1"
    assert_output --partial "$REPO1"
}

@test "wt-context --list shows multiple contexts" {
    create_test_context "alpha" "$REPO1"
    create_test_context "beta" "$REPO2"

    run "$TEST_HOME/.wt/bin/wt-context" --list
    assert_success
    assert_output --partial "alpha"
    assert_output --partial "beta"
}

@test "wt-context --list shows current context indicator" {
    create_test_context "current-ctx" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" --list
    assert_success

    # Should show context name
    assert_output --partial "current-ctx"

    # Should show indicator for current context (* prefix or (current) suffix)
    [[ "$output" == *"(current)"* ]] || [[ "$output" == *"*"* ]] || \
        fail "Expected current context indicator (* or (current)) in output: $output"
}

# =============================================================================
# Context switching tests
# =============================================================================

@test "wt-context switches to named context" {
    create_test_context "switch-target" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" "switch-target"
    assert_success

    # Verify current context changed
    local current
    current=$(cat "$TEST_HOME/.wt/current")
    assert_equal "$current" "switch-target"
}

@test "wt-context sets WT variables after switch" {
    create_test_context "vars-test" "$REPO1"

    # Switch and verify
    run "$TEST_HOME/.wt/bin/wt-context" "vars-test"
    assert_success

    # Load and check via wt_get_context_repo_root
    run bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        source "'"$TEST_HOME/.wt/lib/wt-context"'"
        wt_get_context_repo_root "vars-test"
    '
    assert_success
    assert_output "$REPO1"
}

@test "wt-context fails for non-existent context" {
    run "$TEST_HOME/.wt/bin/wt-context" "nonexistent-context"
    assert_failure
    assert_output --partial "nonexistent-context"
    assert_output --partial "not found"
}

@test "wt-context switching between contexts works" {
    create_test_context "ctx-a" "$REPO1"
    create_test_context "ctx-b" "$REPO2"

    # Switch to ctx-a
    run "$TEST_HOME/.wt/bin/wt-context" "ctx-a"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "ctx-a"

    # Switch to ctx-b
    run "$TEST_HOME/.wt/bin/wt-context" "ctx-b"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "ctx-b"

    # Switch back to ctx-a
    run "$TEST_HOME/.wt/bin/wt-context" "ctx-a"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "ctx-a"
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-context -h/--help shows help" {
    run "$TEST_HOME/.wt/bin/wt-context" -h
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-context" --help
    assert_output --partial "Usage:"
}

# =============================================================================
# Context add subcommand tests
# =============================================================================

@test "wt-context add shows repo info and respects decline" {
    # Provide "n" input to decline at the first confirmation prompt
    run bash -c 'echo "n" | "'"$TEST_HOME/.wt/bin/wt-context"'" add "test-add" "'"$REPO1"'"'

    assert_output --partial "Detected repository"
    assert_output --partial "$REPO1"
    assert_output --partial "main"
    assert_output --partial "Branch:"

    # Verify context was NOT created when user declined
    assert [ ! -f "$TEST_HOME/.wt/repos/test-add.conf" ]
    run ls "$TEST_HOME/.wt/repos/"
    refute_output --partial "test-add"
}

# =============================================================================
# Edge cases
# =============================================================================

@test "wt-context handles context names with special characters" {
    create_test_context "my-dashed-context" "$REPO1"
    create_test_context "my_under_context" "$REPO1"
    create_test_context "context123" "$REPO1"

    run "$TEST_HOME/.wt/bin/wt-context" "my-dashed-context"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "my-dashed-context"

    run "$TEST_HOME/.wt/bin/wt-context" "my_under_context"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "my_under_context"

    run "$TEST_HOME/.wt/bin/wt-context" "context123"
    assert_success
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "context123"
}

# =============================================================================
# Config file integrity tests
# =============================================================================

@test "wt-context switch preserves config file" {
    create_test_context "preserve-test" "$REPO1"
    local config_path="$TEST_HOME/.wt/repos/preserve-test.conf"
    local original_content
    original_content=$(cat "$config_path")

    run "$TEST_HOME/.wt/bin/wt-context" "preserve-test"
    assert_success

    # Config should be unchanged
    local new_content
    new_content=$(cat "$config_path")
    assert_equal "$new_content" "$original_content"
}

@test "wt-context switch updates only current file" {
    create_test_context "update-test" "$REPO1"

    # Record all config file mtimes
    local config_mtime
    config_mtime=$(stat -f %m "$TEST_HOME/.wt/repos/update-test.conf" 2>/dev/null || stat -c %Y "$TEST_HOME/.wt/repos/update-test.conf")

    sleep 1  # Ensure time passes

    run "$TEST_HOME/.wt/bin/wt-context" "update-test"
    assert_success

    # Config file should have same mtime
    local new_mtime
    new_mtime=$(stat -f %m "$TEST_HOME/.wt/repos/update-test.conf" 2>/dev/null || stat -c %Y "$TEST_HOME/.wt/repos/update-test.conf")
    assert_equal "$new_mtime" "$config_mtime"
}
