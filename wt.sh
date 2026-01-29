#!/usr/bin/env bash
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

# Helper to get the path of the current script (works in both bash and zsh)
_wt_get_script_path() {
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    # Bash: use BASH_SOURCE
    echo "${BASH_SOURCE[0]}"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    # Zsh: use %x prompt expansion to get script path
    echo "${(%):-%x}"
  else
    # Fallback
    echo "$0"
  fi
}

# Ensure this file is sourced, not executed; exit with error if executed directly
_wt_ensure_sourced() {
  local script_path="$(_wt_get_script_path)"
  
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # In zsh, check if we're being sourced by examining ZSH_EVAL_CONTEXT
    # When sourced, it contains "toplevel:file" or similar patterns with "file"
    if [[ "${ZSH_EVAL_CONTEXT:-}" != *:file:* && "${ZSH_EVAL_CONTEXT:-}" != *:file ]]; then
      # Not sourced - but this check can be unreliable, so also check $0
      if [[ "$0" == "$script_path" ]]; then
        echo "Error: This file must be sourced, not executed." >&2
        echo "" >&2
        echo "Add this to your ~/.zshrc:" >&2
        echo "  source $script_path" >&2
        echo "" >&2
        echo "Then use: wt <command> [args]" >&2
        exit 1
      fi
    fi
  elif [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Bash: BASH_SOURCE[0] equals $0 when executed directly
    echo "Error: This file must be sourced, not executed." >&2
    echo "" >&2
    echo "Add this to your ~/.bashrc:" >&2
    echo "  source $script_path" >&2
    echo "" >&2
    echo "Then use: wt <command> [args]" >&2
    exit 1
  fi
}

# Resolve the root directory where wt.sh lives
_wt_resolve_root() {
  local source="$(_wt_get_script_path)"
  # Resolve symlinks to find the real location
  while [[ -L "$source" ]]; do
    local dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    # If source is relative, resolve it relative to the symlink's directory
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

# helper for sourcing a library file from lib/ directory
# Args: $1 = library name, $2 = "optional" to skip error if not found
_wt_source_lib() {
  local lib="$1"
  local required="${2:-required}"
  
  if [[ -f "$_WT_ROOT/lib/$lib" ]]; then
    . "$_WT_ROOT/lib/$lib"
  elif [[ -f "$HOME/.wt/lib/$lib" ]]; then
    . "$HOME/.wt/lib/$lib"
  elif [[ "$required" != "optional" ]]; then
    echo "wt: cannot find required library: $lib" >&2
    return 1
  fi
}

# helper for running a wt-* command from bin/ directory or PATH
_wt_run() {
  local cmd="$1"
  shift
  if [[ -x "$_WT_ROOT/bin/$cmd" ]]; then
    "$_WT_ROOT/bin/$cmd" "$@"
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
  target="$(_wt_run wt-cd "$@")"
  rc=$?
  if [[ $rc -eq 0 && -n "$target" && -d "$target" ]]; then
    cd "$target" || return 1
    echo "Changed directory to: $target"
  else
    return 1
  fi
}

# main wt command
wt() {
  local cmd="$1"
  shift 2>/dev/null || true

  case "$cmd" in
    add)             _wt_run wt-add "$@" ;;
    switch)          _wt_run wt-switch "$@" ;;
    remove)          _wt_run wt-remove "$@" ;;
    list)            _wt_run wt-list "$@" ;;
    context)         _wt_run wt-context "$@" ;;
    metadata-export) _wt_run wt-metadata-export "$@" ;;
    metadata-import) _wt_run wt-metadata-import "$@" ;;
    # Legacy aliases (kept for backward compatibility)
    ijwb-export)     _wt_run wt-metadata-export "$@" ;;
    ijwb-import)     _wt_run wt-metadata-import "$@" ;;
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
_wt_source_shell_completion() {
  local completion_dir="$_WT_ROOT/completion"
  
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ -f "$completion_dir/wt.zsh" ]] && . "$completion_dir/wt.zsh"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    [[ -f "$completion_dir/wt.bash" ]] && . "$completion_dir/wt.bash"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# initialization
# ═══════════════════════════════════════════════════════════════════════════════

_wt_ensure_sourced
_WT_ROOT="$(_wt_resolve_root)"
_wt_source_lib wt-common
_wt_source_lib wt-help
_wt_source_lib wt-completion       # completion for `wt` subcommands
_wt_source_shell_completion        # completion for individual `wt-*` scripts

