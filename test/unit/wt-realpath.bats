#!/usr/bin/env bats

# Unit tests for _wt_realpath in lib/wt-common

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the library under test
    source "$TEST_HOME/.wt/lib/wt-common"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for _wt_realpath()
# =============================================================================

@test "_wt_realpath resolves single-level symlink" {
    local real_dir="$BATS_TEST_TMPDIR/real-dir"
    mkdir -p "$real_dir"
    echo "content" > "$real_dir/file.txt"

    local link="$BATS_TEST_TMPDIR/link-to-dir"
    ln -s "$real_dir" "$link"

    run _wt_realpath "$link"
    assert_success

    local expected
    expected="$(cd -P "$real_dir" && pwd -P)"
    assert_output "$expected"
}

@test "_wt_realpath resolves multi-hop symlink chain" {
    local real_dir="$BATS_TEST_TMPDIR/real-target"
    mkdir -p "$real_dir"

    local link1="$BATS_TEST_TMPDIR/link1"
    local link2="$BATS_TEST_TMPDIR/link2"
    local link3="$BATS_TEST_TMPDIR/link3"

    ln -s "$real_dir" "$link1"
    ln -s "$link1" "$link2"
    ln -s "$link2" "$link3"

    run _wt_realpath "$link3"
    assert_success

    local expected
    expected="$(cd -P "$real_dir" && pwd -P)"
    assert_output "$expected"
}

@test "_wt_realpath handles regular directory (no symlink)" {
    local real_dir="$BATS_TEST_TMPDIR/plain-dir"
    mkdir -p "$real_dir"

    run _wt_realpath "$real_dir"
    assert_success

    local expected
    expected="$(cd -P "$real_dir" && pwd -P)"
    assert_output "$expected"
}

@test "_wt_realpath returns failure for nonexistent path" {
    run _wt_realpath "$BATS_TEST_TMPDIR/does-not-exist"
    assert_failure
}

@test "_wt_realpath resolves symlink to a file" {
    local real_file="$BATS_TEST_TMPDIR/real-file.txt"
    echo "content" > "$real_file"

    local link="$BATS_TEST_TMPDIR/link-to-file"
    ln -s "$real_file" "$link"

    run _wt_realpath "$link"
    assert_success

    local expected_dir
    expected_dir="$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)"
    assert_output "$expected_dir/real-file.txt"
}

@test "_wt_realpath resolves relative symlink target" {
    local subdir="$BATS_TEST_TMPDIR/sub"
    mkdir -p "$subdir"
    local real_dir="$BATS_TEST_TMPDIR/real-target"
    mkdir -p "$real_dir"

    # Create a relative symlink: sub/link -> ../real-target
    ln -s "../real-target" "$subdir/link"

    run _wt_realpath "$subdir/link"
    assert_success

    local expected
    expected="$(cd -P "$real_dir" && pwd -P)"
    assert_output "$expected"
}
