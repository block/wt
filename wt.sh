# shellcheck shell=bash  # wt.sh is sourced (not executed), it runs in the user's shell (bash or zsh)
#
# wt.sh — Unified Worktree Command
# ================================
#
# Provides a single `wt` command with subcommands (add, switch, remove, list, cd, etc.)
# that wrap the individual wt-* scripts.
#
# This file MUST be sourced (not executed) to enable `wt cd` to change directories.
#
# Usage: source this file, then run `wt help` for details.
#

# Installation root — all wt files live under this directory.
# Override by setting __WT_ROOT before sourcing (e.g., for development).
__WT_ROOT="${__WT_ROOT:-$HOME/.wt}"

# Ensure this file is sourced, not executed; exit with error if executed directly
__wt_ensure_sourced() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # In zsh, check if we're being sourced by examining ZSH_EVAL_CONTEXT
    # When sourced, it contains "toplevel:file" or similar patterns with "file"
    if [[ "${ZSH_EVAL_CONTEXT:-}" != *:file:* && "${ZSH_EVAL_CONTEXT:-}" != *:file ]]; then
      echo "Error: This file must be sourced, not executed." >&2
      echo "" >&2
      echo "Add this to your ${ZDOTDIR:-~}/.zshrc:" >&2
      echo "  source $__WT_ROOT/wt.sh" >&2
      echo "" >&2
      echo "Then use: wt <command> [args]" >&2
      exit 1
    fi
  elif [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Bash: BASH_SOURCE[0] equals $0 when executed directly
    echo "Error: This file must be sourced, not executed." >&2
    echo "" >&2
    echo "Add this to your ~/.bashrc (or ~/.bash_profile):" >&2
    echo "  source $__WT_ROOT/wt.sh" >&2
    echo "" >&2
    echo "Then use: wt <command> [args]" >&2
    exit 1
  fi
}

# helper for sourcing a library file from lib/ directory
# Args: $1 = library name, $2 = "optional" to skip error if not found
__wt_source_lib() {
  local lib="$1"
  local required="${2:-required}"
  
  if [[ -f "$__WT_ROOT/lib/$lib" ]]; then
    . "$__WT_ROOT/lib/$lib"
  elif [[ "$required" != "optional" ]]; then
    echo "wt: cannot find required library: $lib" >&2
    return 1
  fi
}

# helper for running a wt-* command from bin/ directory or PATH
__wt_run() {
  local cmd="$1"
  shift
  local root="${__WT_ROOT:-$HOME/.wt}"
  if [[ -x "$root/bin/$cmd" ]]; then
    "$root/bin/$cmd" "$@"
  elif command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@"
  else
    echo "wt: command not found: $cmd" >&2
    echo "Make sure wt.sh is sourced from the correct location." >&2
    return 127
  fi
}

# helper for changing directory to a worktree (runs in current shell)
# Note: Named __wt_do_cd to avoid conflict with _wt_cd completion function in completion/wt.zsh
__wt_do_cd() {
  local target rc
  target="$(__wt_run wt-cd "$@")"
  rc=$?
  if [[ $rc -eq 0 && -n "$target" && -d "$target" ]]; then
    cd "$target" || return 1
    echo "Changed directory to: $target"
  else
    return 1
  fi
}

# helper for removing worktrees with auto-cd if cwd was removed
__wt_do_remove() {
  local old_pwd="$PWD"
  __wt_run wt-remove "$@"
  local rc=$?
  # If the removal succeeded and our cwd no longer exists, cd to main repo
  if [[ $rc -eq 0 && ! -d "$old_pwd" ]]; then
    cd "$WT_MAIN_REPO_ROOT" || return 1
    info "Working directory was removed; changed to $WT_MAIN_REPO_ROOT"
  fi
  return $rc
}

# main wt command
wt() {
  local cmd="$1"
  shift 2>/dev/null || true

  case "$cmd" in
    add)             __wt_run wt-add "$@" ;;
    adopt)           __wt_run wt-adopt "$@" ;;
    switch)          __wt_run wt-switch "$@" ;;
    remove)          __wt_do_remove "$@" ;;
    list)            __wt_run wt-list "$@" ;;
    context) __wt_run wt-context "$@" && wt_read_config --force ;;
    metadata-export) __wt_run wt-metadata-export "$@" ;;
    metadata-import) __wt_run wt-metadata-import "$@" ;;
    # Legacy aliases (kept for backward compatibility)
    ijwb-export)     __wt_run wt-metadata-export "$@" ;;
    ijwb-import)     __wt_run wt-metadata-import "$@" ;;
    cd)              __wt_do_cd "$@" ;;
    help|--help|-h|"")
      wt_show_help          # helper for showing help, defined in wt-help library
      ;;
    *)
      echo "wt: unknown command '$cmd'" >&2
      echo "Run 'wt help' for usage information." >&2
      return 1
      ;;
  esac
}

# helper for sourcing shell-specific completion (wt-* scripts completion)
__wt_source_shell_completion() {
  local completion_dir="$__WT_ROOT/completion"
  
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ -f "$completion_dir/wt.zsh" ]] && . "$completion_dir/wt.zsh"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    [[ -f "$completion_dir/wt.bash" ]] && . "$completion_dir/wt.bash"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# initialization
# ═══════════════════════════════════════════════════════════════════════════════

__wt_ensure_sourced
__wt_source_lib wt-common
__wt_source_lib wt-help
__wt_source_shell_completion        # completion for `wt` and `wt-*` commands

