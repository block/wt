#!/usr/bin/env bats

# Integration tests for bin/wt-metadata-refresh

setup() {
    load '../test_helper/common'
    setup_test_env

    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    create_test_context "test" "$REPO"
    load_test_context "test"

    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".ijwb"/' "$TEST_HOME/.wt/repos/test.conf"
    export WT_METADATA_PATTERNS=".ijwb"

    mkdir -p "$REPO/.ijwb"

    # Mock bazel that records its arguments and emits configurable output
    export MOCK_BAZEL_ARGS="$BATS_TEST_TMPDIR/bazel.args"
    mkdir -p "$BATS_TEST_TMPDIR/mockbin"
    cat > "$BATS_TEST_TMPDIR/mockbin/bazel" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_BAZEL_ARGS"
if [[ -n "${MOCK_BAZEL_STDERR:-}" ]]; then
    echo "$MOCK_BAZEL_STDERR" >&2
fi
if [[ -n "${MOCK_BAZEL_STDOUT:-}" ]]; then
    echo "$MOCK_BAZEL_STDOUT"
fi
exit "${MOCK_BAZEL_EXIT:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/mockbin/bazel"
    export PATH="$BATS_TEST_TMPDIR/mockbin:$PATH"
}

teardown() {
    teardown_test_env
}

@test "wt-metadata-refresh skips exclusion entries in .bazelproject directories" {
    cat > "$REPO/.ijwb/.bazelproject" <<EOF
directories:
  src/main
  -src/main/excluded
EOF
    export MOCK_BAZEL_STDOUT="//src/main:lib"

    run "$TEST_HOME/.wt/bin/wt-metadata-refresh" --no-export
    assert_success

    run cat "$MOCK_BAZEL_ARGS"
    assert_output --partial "//src/main/..."
    refute_output --partial "excluded"
}

@test "wt-metadata-refresh maps root directory entry to //..." {
    cat > "$REPO/.ijwb/.bazelproject" <<EOF
directories:
  .
EOF
    export MOCK_BAZEL_STDOUT="//pkg:target"

    run "$TEST_HOME/.wt/bin/wt-metadata-refresh" --no-export
    assert_success

    run cat "$MOCK_BAZEL_ARGS"
    assert_line "kind('.*', //...)"
    refute_output --partial "//./"
}

@test "wt-metadata-refresh logs bazel stderr to log file on empty results" {
    export MOCK_BAZEL_STDERR="ERROR: Skipping '//bad/...': no such package"
    export MOCK_BAZEL_EXIT=3

    run "$TEST_HOME/.wt/bin/wt-metadata-refresh" --no-export
    assert_failure

    assert_output --partial "Bazel query returned empty results"
    assert [ -f "$TEST_HOME/.wt/logs/bazel-query-stderr.log" ]
    run cat "$TEST_HOME/.wt/logs/bazel-query-stderr.log"
    assert_output --partial "ERROR: Skipping"
}
