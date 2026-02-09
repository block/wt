# completion/wt.bash
# ==================
# Bash completion for wt-* scripts with conditional FZF support.
#
# Behavior:
#   - Always:
#       * Source wt-common (if present) to read WT_MAIN_REPO_ROOT, etc.
#       * Provide completions for wt-* commands.
#
#   - If `fzf` is available:
#       * For `wt-add`:
#           - First argument completion:
#               · Open an fzf menu of git branches from WT_MAIN_REPO_ROOT
#                 (if set and a git repo), else from the current git repo.
#               · Insert the selected branch name as the completion result.
#           - Other arguments: normal file/dir completion.
#
#   - If `fzf` is NOT available:
#       * For `wt-add`:
#           - First argument: branch completion from resolved repo (no fzf),
#             plus normal file/dir completion.
#           - Other arguments: normal file/dir completion.
#
#   - For other wt-* commands:
#       * File/dir completion.
#
# Usage:
#   1. Place this file as: completion/wt.bash
#   2. Have install.sh copy it into ~/.wt/wt.bash
#   3. In ~/.bashrc (or ~/.bash_profile), add:
#        [[ -f "$HOME/.wt/wt.bash" ]] && source "$HOME/.wt/wt.bash"

# --- Load shared config (wt-common) if available ---
if [[ -f "$HOME/.wt/lib/wt-common" ]]; then
  . "$HOME/.wt/lib/wt-common"
fi

# --- Helper: resolve which repo to use for branch completion ---
# Priority:
#   1. WT_MAIN_REPO_ROOT if set and is a git repo.
#   2. Current directory if inside a git repo.
#   3. Empty string otherwise.
_wt_resolve_repo() {
  # Use git -C to correctly handle worktrees (they don't have .git directories)
  if [[ -n "${WT_MAIN_REPO_ROOT:-}" ]] && git -C "$WT_MAIN_REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$WT_MAIN_REPO_ROOT"
    return 0
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rev-parse --show-toplevel 2>/dev/null
    return 0
  fi

  printf '%s\n' ""
  return 0
}

# --- Helper: get branch list from resolved repo ---
_wt_branch_list() {
  local repo
  repo="$(_wt_resolve_repo)"

  [[ -z "$repo" ]] && return 0

  git -C "$repo" branch --format='%(refname:short)' 2>/dev/null
}

# --- Helper: get worktree list from resolved repo (excluding main repo) ---
_wt_worktree_list() {
  local repo main_repo_abs
  repo="$(_wt_resolve_repo)"

  [[ -z "$repo" ]] && return 0

  # Get absolute path of main repo for exclusion
  if [[ -n "${WT_MAIN_REPO_ROOT:-}" ]]; then
    main_repo_abs="$(cd "$WT_MAIN_REPO_ROOT" 2>/dev/null && pwd)"
  else
    main_repo_abs=""
  fi

  git -C "$repo" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        local wt="${line#worktree }"
        local wt_abs
        wt_abs="$(cd "$wt" 2>/dev/null && pwd)"
        # Exclude main repo from list
        if [[ -z "$main_repo_abs" || "$wt_abs" != "$main_repo_abs" ]]; then
          printf '%s\n' "$wt_abs"
        fi
        ;;
    esac
  done
}

# ====================================================================================
#  PATH 1: FZF is available → FZF-powered completion for wt-add first argument
# ====================================================================================
if command -v fzf >/dev/null 2>&1; then

  _wt_add_complete() {
    local cur prev cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD

    # Handle -b/--branch option
    if [[ "$prev" == "-b" || "$prev" == "--branch" ]]; then
      local branches branch
      branches="$(_wt_branch_list)"

      if [[ -z "$branches" ]]; then
        COMPREPLY+=( $(compgen -f -- "$cur") )
        return 0
      fi

      branch=$(printf '%s\n' "$branches" | fzf --height 50% --reverse --prompt='wt-add branch > ' --query="$cur")
      if [[ -n "$branch" ]]; then
        COMPREPLY=( "$branch" )
      fi
      return 0
    fi

    # First argument after `wt-add`
    if [[ $cword -eq 1 ]]; then
      # Check if it's an option
      if [[ "$cur" == -* ]]; then
        COMPREPLY+=( $(compgen -W "-b --branch" -- "$cur") )
        return 0
      fi

      local branches branch
      branches="$(_wt_branch_list)"

      # If no branches found, fall back to normal file completion
      if [[ -z "$branches" ]]; then
        COMPREPLY+=( $(compgen -f -- "$cur") )
        return 0
      fi

      # Run fzf to pick a branch
      branch=$(printf '%s\n' "$branches" | fzf --height 50% --reverse --prompt='wt-add branch > ' --query="$cur")
      if [[ -n "$branch" ]]; then
        # Use the selected branch as the only completion result
        COMPREPLY=( "$branch" )
      else
        # User cancelled -> no completion
        COMPREPLY=()
      fi
      return 0
    fi

    # For all other arguments, just do normal file completion
    COMPREPLY+=( $(compgen -f -- "$cur") )
  }

# ====================================================================================
#  PATH 2: FZF not available → pure bash completion
# ====================================================================================
else
  _wt_add_complete() {
    local cur prev cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD

    # Handle -b/--branch option
    if [[ "$prev" == "-b" || "$prev" == "--branch" ]]; then
      local branches
      branches="$(_wt_branch_list)"

      if [[ -n "$branches" ]]; then
        COMPREPLY+=( $(compgen -W "$branches" -- "$cur") )
      fi
      return 0
    fi

    # First argument after `wt-add`
    if [[ $cword -eq 1 ]]; then
      # Check if it's an option
      if [[ "$cur" == -* ]]; then
        COMPREPLY+=( $(compgen -W "-b --branch" -- "$cur") )
        return 0
      fi

      local branches
      branches="$(_wt_branch_list)"

      # Offer branch completions if present
      if [[ -n "$branches" ]]; then
        COMPREPLY+=( $(compgen -W "$branches" -- "$cur") )
      fi

      # Also offer normal file completion
      COMPREPLY+=( $(compgen -f -- "$cur") )
      return 0
    fi

    # For all other arguments, just do normal file completion
    COMPREPLY+=( $(compgen -f -- "$cur") )
  }

fi

# --- Completion for wt-switch: worktree paths only ---
_wt_switch_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  local worktrees
  worktrees="$(_wt_worktree_list)"

  # Handle paths with spaces correctly
  if [[ -n "$worktrees" ]]; then
    local IFS=$'\n'
    compopt -o filenames 2>/dev/null
    COMPREPLY+=( $(compgen -W "$worktrees" -- "$cur") )
  fi
  COMPREPLY+=( $(compgen -d -- "$cur") )
}

# --- Completion for wt-remove: worktree paths only (main repo excluded) ---
_wt_remove_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  local worktrees
  worktrees="$(_wt_worktree_list)"

  # Handle paths with spaces correctly
  if [[ -n "$worktrees" ]]; then
    local IFS=$'\n'
    compopt -o filenames 2>/dev/null
    COMPREPLY+=( $(compgen -W "$worktrees" -- "$cur") )
  fi
  COMPREPLY+=( $(compgen -d -- "$cur") )
}

# --- Completion for wt-cd: worktree paths only ---
_wt_cd_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  local worktrees
  worktrees="$(_wt_worktree_list)"

  # Handle paths with spaces correctly
  if [[ -n "$worktrees" ]]; then
    local IFS=$'\n'
    compopt -o filenames 2>/dev/null
    COMPREPLY+=( $(compgen -W "$worktrees" -- "$cur") )
  fi
  COMPREPLY+=( $(compgen -d -- "$cur") )
}

# --- Completion for wt-metadata-export: directories ---
_wt_metadata_export_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Complete directories
  COMPREPLY=($(compgen -d -- "$cur"))
}

# --- Completion for wt-metadata-import: worktrees and directories ---
_wt_metadata_import_complete() {
  local cur cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  cword=$COMP_CWORD

  # First arg: source directory or target worktree
  # Second arg: target worktree
  if [[ $cword -eq 1 ]]; then
    # Offer both worktrees and directories
    local worktrees
    worktrees="$(_wt_worktree_list)"
    if [[ -n "$worktrees" ]]; then
      local IFS=$'\n'
      compopt -o filenames 2>/dev/null
      COMPREPLY+=( $(compgen -W "$worktrees" -- "$cur") )
    fi
    COMPREPLY+=($(compgen -d -- "$cur"))
  elif [[ $cword -eq 2 ]]; then
    # Second argument - target worktree
    local worktrees
    worktrees="$(_wt_worktree_list)"
    if [[ -n "$worktrees" ]]; then
      local IFS=$'\n'
      compopt -o filenames 2>/dev/null
      COMPREPLY+=( $(compgen -W "$worktrees" -- "$cur") )
    fi
  fi
}

# --- Wire up completion functions (only if commands exist on PATH) ---
type wt-add >/dev/null 2>&1 && complete -F _wt_add_complete wt-add
type wt-switch >/dev/null 2>&1 && complete -F _wt_switch_complete wt-switch
type wt-remove >/dev/null 2>&1 && complete -F _wt_remove_complete wt-remove
type wt-cd >/dev/null 2>&1 && complete -F _wt_cd_complete wt-cd
type wt-metadata-export >/dev/null 2>&1 && complete -F _wt_metadata_export_complete wt-metadata-export
type wt-metadata-import >/dev/null 2>&1 && complete -F _wt_metadata_import_complete wt-metadata-import
