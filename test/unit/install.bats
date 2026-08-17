#!/usr/bin/env bats

# Unit tests for install.sh upgrade behavior

setup() {
    load '../test_helper/common'
    setup_test_env

    # Fake crontab so tests never touch the real user crontab
    CRON_STATE="$BATS_TEST_TMPDIR/cron-state"
    FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/crontab" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  -l) [[ -f "$CRON_STATE" ]] || exit 1; cat "$CRON_STATE" ;;
  # Buffer all of stdin before truncating: crontab -l reads the same file
  # concurrently in the migration pipeline
  -)  content="\$(cat)"; printf '%s\n' "\$content" > "$CRON_STATE" ;;
esac
EOF
    chmod +x "$FAKE_BIN/crontab"
    export PATH="$FAKE_BIN:$PATH"

    source "$PROJECT_ROOT/install.sh"
    # install.sh sets -euo pipefail for its own execution; restore bats defaults
    set +u
    set +o pipefail
}

teardown() {
    teardown_test_env
}

# =============================================================================
# install_toolkit — installer-owned paths are replaced wholesale
# =============================================================================

@test "install_toolkit removes stale files that no longer exist in the source" {
    touch "$TEST_HOME/.wt/bin/wt-bazel-symlinks"
    touch "$TEST_HOME/.wt/lib/wt-addons"
    touch "$TEST_HOME/.wt/lib/wt-metadata-refresh"

    run install_toolkit
    assert_success

    assert [ ! -e "$TEST_HOME/.wt/bin/wt-bazel-symlinks" ]
    assert [ ! -e "$TEST_HOME/.wt/lib/wt-addons" ]
    assert [ ! -e "$TEST_HOME/.wt/lib/wt-metadata-refresh" ]
}

@test "install_toolkit installs a complete fresh copy" {
    run install_toolkit
    assert_success

    assert [ -f "$TEST_HOME/.wt/wt.sh" ]
    assert [ -f "$TEST_HOME/.wt/bin/wt-add" ]
    assert [ -f "$TEST_HOME/.wt/bin/wt-metadata-refresh" ]
    assert [ -f "$TEST_HOME/.wt/lib/wt-common" ]
    assert [ -x "$TEST_HOME/.wt/bin/wt-add" ]
}

@test "install_toolkit never touches user data (repos/, logs/, current)" {
    echo 'WT_BASE_BRANCH="main"' > "$TEST_HOME/.wt/repos/myrepo.conf"
    mkdir -p "$TEST_HOME/.wt/logs"
    echo "old log" > "$TEST_HOME/.wt/logs/metadata-refresh.log"
    echo "myrepo" > "$TEST_HOME/.wt/current"

    run install_toolkit
    assert_success

    assert_equal "$(cat "$TEST_HOME/.wt/repos/myrepo.conf")" 'WT_BASE_BRANCH="main"'
    assert_equal "$(cat "$TEST_HOME/.wt/logs/metadata-refresh.log")" "old log"
    assert_equal "$(cat "$TEST_HOME/.wt/current")" "myrepo"
}

@test "install_toolkit never deletes the source when it is the install dir" {
    INSTALL_DIR="$SOURCE_DIR"

    run install_toolkit

    assert [ -f "$SOURCE_DIR/wt.sh" ]
    assert [ -f "$SOURCE_DIR/bin/wt-add" ]
    assert [ -f "$SOURCE_DIR/lib/wt-common" ]
}

# =============================================================================
# refresh_cron_job — existing wt entries are replaced with the canonical one
# =============================================================================

@test "refresh_cron_job replaces old lib/ cron entry with the canonical bin/ entry" {
    echo "0 2 * * * /bin/zsh -lc '$TEST_HOME/.wt/lib/wt-metadata-refresh' >> $TEST_HOME/.wt/logs/metadata-refresh.log 2>&1" > "$CRON_STATE"

    run refresh_cron_job
    assert_success

    assert_equal "$(cat "$CRON_STATE")" "$(cron_entry_line)"
}

@test "refresh_cron_job replaces a customized wt entry with the canonical one" {
    echo "30 6 * * * /bin/bash -c '$TEST_HOME/.wt/lib/wt-metadata-refresh --extra'" > "$CRON_STATE"

    run refresh_cron_job
    assert_success

    assert_equal "$(cat "$CRON_STATE")" "$(cron_entry_line)"
}

@test "refresh_cron_job collapses duplicate wt entries into one canonical entry" {
    printf '%s\n' \
      "0 2 * * * /bin/zsh -lc '$TEST_HOME/.wt/lib/wt-metadata-refresh'" \
      "0 4 * * * /bin/zsh -lc '$TEST_HOME/.wt/bin/wt-metadata-refresh'" > "$CRON_STATE"

    run refresh_cron_job
    assert_success

    assert_equal "$(cat "$CRON_STATE")" "$(cron_entry_line)"
}

@test "refresh_cron_job leaves unrelated crontab lines alone" {
    printf '%s\n' "0 3 * * * /usr/bin/true" "0 2 * * * /bin/zsh -lc '$TEST_HOME/.wt/lib/wt-metadata-refresh'" > "$CRON_STATE"

    run refresh_cron_job
    assert_success

    run cat "$CRON_STATE"
    assert_output --partial "0 3 * * * /usr/bin/true"
    assert_output --partial "$(cron_entry_line)"
    refute_output --partial "lib/wt-metadata-refresh"
}

@test "refresh_cron_job is idempotent on an already-canonical entry" {
    cron_entry_line > "$CRON_STATE"

    run refresh_cron_job
    assert_success

    assert_equal "$(cat "$CRON_STATE")" "$(cron_entry_line)"
}

@test "refresh_cron_job adds nothing when no wt entry exists" {
    echo "0 3 * * * /usr/bin/true" > "$CRON_STATE"

    run refresh_cron_job
    assert_success

    assert_equal "$(cat "$CRON_STATE")" "0 3 * * * /usr/bin/true"
}

@test "refresh_cron_job succeeds when the user has no crontab" {
    rm -f "$CRON_STATE"

    run refresh_cron_job
    assert_success

    assert [ ! -e "$CRON_STATE" ]
}
