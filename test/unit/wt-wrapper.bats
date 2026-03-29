#!/usr/bin/env bats

# Unit tests for bin/wt (standalone wrapper)

setup() {
    load '../test_helper/common'
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "bin/wt exists and is executable" {
    [[ -x "$PROJECT_ROOT/bin/wt" ]]
}

@test "bin/wt with no args shows help (exit 0)" {
    run "$PROJECT_ROOT/bin/wt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wt — Unified Worktree Toolkit"* ]]
}

@test "bin/wt help shows help text" {
    run "$PROJECT_ROOT/bin/wt" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree Commands"* ]]
}

@test "bin/wt --help shows help text" {
    run "$PROJECT_ROOT/bin/wt" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree Commands"* ]]
}

@test "bin/wt -h shows help text" {
    run "$PROJECT_ROOT/bin/wt" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree Commands"* ]]
}

@test "bin/wt cd prints error and exits 1" {
    run "$PROJECT_ROOT/bin/wt" cd
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an interactive shell"* ]]
}

@test "bin/wt cd provides workaround hint" {
    run "$PROJECT_ROOT/bin/wt" cd
    [[ "$output" == *"wt-cd"* ]]
}

@test "bin/wt unknown-command prints error and exits 1" {
    run "$PROJECT_ROOT/bin/wt" nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown command"* ]]
}

@test "bin/wt dispatches list to wt-list" {
    # Verify wt-list exists as sibling
    [[ -x "$PROJECT_ROOT/bin/wt-list" ]]
    # Run it (will exercise the dispatch path; actual output depends on config)
    run "$PROJECT_ROOT/bin/wt" list
    # Should not get "command not found" error
    [[ "$output" != *"command script not found"* ]]
}

@test "bin/wt dispatches ijwb-export to wt-metadata-export" {
    # Verify the legacy alias maps to the correct script
    # We can check by looking at the script content
    grep -q 'ijwb-export.*metadata-export' "$PROJECT_ROOT/bin/wt"
}

@test "bin/wt dispatches ijwb-import to wt-metadata-import" {
    grep -q 'ijwb-import.*metadata-import' "$PROJECT_ROOT/bin/wt"
}

@test "bin/wt case statement matches wt.sh subcommands" {
    # Every dispatch subcommand in wt.sh should have a corresponding case in bin/wt
    # Commands that have their own case branch (help is combined with --help|-h)
    local wt_sh_cmds=(add adopt switch remove list context metadata-export metadata-import cd)
    for cmd in "${wt_sh_cmds[@]}"; do
        grep -q "$cmd)" "$PROJECT_ROOT/bin/wt" || {
            echo "Missing case for: $cmd"
            return 1
        }
    done
    # help is combined with --help|-h in a single case branch
    grep -q 'help|--help|-h)' "$PROJECT_ROOT/bin/wt" || {
        echo "Missing case for: help"
        return 1
    }
}
