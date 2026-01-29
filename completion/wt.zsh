# completion/wt.zsh
# ==================
# Zsh integration for wt-* scripts with conditional FZF support.
#
# Behavior:
#   - Always:
#       * Source wt-common (if present) to get WT_MAIN_REPO_ROOT, etc.
#       * Provide some form of completion for wt-* commands.
#
#   - If `fzf` is available:
#       * TAB is wrapped:
#            - If the command is `wt-add`, invoke an FZF branch picker.
#            - Otherwise, delegate to the original TAB binding.
#       * Ctrl+X Ctrl+A always invokes the FZF branch picker.
#
#   - If `fzf` is NOT available:
#       * Use normal zsh completion:
#            - wt-add: first arg completes from git branches (WT_MAIN_REPO_ROOT
#              or current repo), plus files.
#            - Other wt-* commands: file completion.
#
# This file is designed for personal use.

# --- Load shared config (wt-common) if available ---
if [[ -r "$HOME/.wt/lib/wt-common" ]]; then
  source "$HOME/.wt/lib/wt-common"
fi

# --- Helper: resolve which repo to use for branch completion ---
# Priority:
#   1. WT_MAIN_REPO_ROOT if set and a git repo.
#   2. Current directory if inside a git repo.
#   3. Non-zero status (no output) otherwise.
_wt_resolve_repo() {
  # Use git -C to correctly handle worktrees and non-standard .git layouts.
  if [[ -n ${WT_MAIN_REPO_ROOT:-} ]] && git -C "$WT_MAIN_REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    print -r -- "$WT_MAIN_REPO_ROOT"
    return 0
  fi

  if git rev-parse --is-inside-work-tree &>/dev/null; then
    # Show the repository root; callers should treat this as the repo path.
    git rev-parse --show-toplevel 2>/dev/null
    return 0
  fi

  return 1
}

# --- Helper: get branch names from resolved repo ---
_wt_branch_list() {
  local repo
  repo=$(_wt_resolve_repo) || return

  git -C "$repo" branch --format='%(refname:short)' 2>/dev/null
}

# --- Helper: get worktree paths from resolved repo (excluding main repo) ---
_wt_worktree_list() {
  local repo main_repo_abs
  repo=$(_wt_resolve_repo) || return

  # Get absolute path of main repo for exclusion
  if [[ -n ${WT_MAIN_REPO_ROOT:-} ]]; then
    main_repo_abs="$(cd "$WT_MAIN_REPO_ROOT" 2>/dev/null && pwd)"
  else
    main_repo_abs=""
  fi

  git -C "$repo" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        local wt="${line#worktree }"
        local wt_abs="$(cd "$wt" 2>/dev/null && pwd)"
        # Exclude main repo from list
        if [[ -z "$main_repo_abs" || "$wt_abs" != "$main_repo_abs" ]]; then
          print -r -- "$wt_abs"
        fi
        ;;
    esac
  done
}

# -------------------------------------------------------------------
#  PATH 1: FZF is available → use FZF-powered completion for wt-add
# -------------------------------------------------------------------
if (( $+commands[fzf] )); then
  # FZF-based branch picker widget
  wt_fzf_branch_complete() {
    emulate -L zsh -o extended_glob

    local branches branch
    branches="$(_wt_branch_list)"

    if [[ -z "$branches" ]]; then
      # No repo or no branches -> fall back to normal completion
      zle complete-word
      return
    fi

    branch=$(print -r -- "$branches" | fzf --height 50% --reverse --prompt='wt-add branch > ')
    [[ -z "$branch" ]] && return  # user cancelled

    # Insert the branch at the cursor position, preserving existing arguments
    if [[ -n "$LBUFFER" && "$LBUFFER" != *[[:space:]] ]]; then
      LBUFFER+=" "
    fi
    LBUFFER+="$branch "
    BUFFER="$LBUFFER$RBUFFER"
    CURSOR=${#LBUFFER}
  }

  zle -N wt_fzf_branch_complete

  # Capture original TAB widget so we can delegate for non-wt-add commands.
  typeset -g WT_ORIG_TAB_WIDGET=""
  {
    local binding
    binding=($(bindkey '^I' 2>/dev/null))
    WT_ORIG_TAB_WIDGET="${binding[2]:-}"
  } 2>/dev/null

  # Dispatcher: if command starts with wt-add, use FZF; otherwise call original TAB binding.
  wt_tab_dispatch() {
    emulate -L zsh -o extended_glob

    local -a words
    words=(${(z)BUFFER})
    local first="${words[1]:-}"

    if [[ "$first" == "wt-add" ]]; then
      wt_fzf_branch_complete
      return
    fi

    if [[ -n "$WT_ORIG_TAB_WIDGET" && "$WT_ORIG_TAB_WIDGET" != "wt_tab_dispatch" ]]; then
      zle "$WT_ORIG_TAB_WIDGET"
    else
      zle complete-word
    fi
  }

  zle -N wt_tab_dispatch

  # Bind TAB to our dispatcher
  bindkey '^I' wt_tab_dispatch

  # Bind Ctrl+X Ctrl+A to always trigger FZF-based branch picker
  bindkey '^X^A' wt_fzf_branch_complete

  # Completion for wt-switch: worktree paths only
  _wt_switch() {
    local context state
    typeset -A opt_args

    _arguments -C \
      '1:worktree:->worktree' && return 0

    case "$state" in
      worktree)
        local -a worktrees
        worktrees=(${(f)$(_wt_worktree_list)})

        if (( ${#worktrees[@]} > 0 )); then
          _describe 'worktrees' worktrees || _files -/
        else
          _files -/
        fi
        ;;
    esac
  }

  # Completion for wt-remove: worktree paths only (main repo excluded)
  _wt_remove() {
    local context state
    typeset -A opt_args

    _arguments -C \
      '1:worktree:->worktree' && return 0

    case "$state" in
      worktree)
        local -a worktrees
        worktrees=(${(f)$(_wt_worktree_list)})

        if (( ${#worktrees[@]} > 0 )); then
          _describe 'worktrees' worktrees || _files -/
        else
          _files -/
        fi
        ;;
    esac
  }

  # Completion for wt-cd: worktree paths only
  _wt_cd() {
    local context state
    typeset -A opt_args

    _arguments -C \
      '1:worktree:->worktree' && return 0

    case "$state" in
      worktree)
        local -a worktrees
        worktrees=(${(f)$(_wt_worktree_list)})

        if (( ${#worktrees[@]} > 0 )); then
          _describe 'worktrees' worktrees || _files -/
        else
          _files -/
        fi
        ;;
    esac
  }

  compdef _wt_switch wt-switch
  compdef _wt_remove wt-remove
  compdef _wt_cd wt-cd

# -------------------------------------------------------------------
#  PATH 2: FZF not available → pure zsh completion
# -------------------------------------------------------------------
else
  # Pure zsh completion for wt-add:
  # - Supports -b/--branch flag
  # - First arg: branch name from resolved repo OR path
  # - Others: file completion
  _wt_add() {
    emulate -L zsh -o extended_glob

    local context state
    typeset -A opt_args

    _arguments -C \
      '(-b --branch)'{-b,--branch}'[Create new branch]:branch name:->branch' \
      '1:branch or path:->first' \
      '*:files:_files' && return 0

    case "$state" in
      branch|first)
        local -a branches
        branches=(${(f)$(_wt_branch_list)})

        if (( ${#branches[@]} > 0 )); then
          _describe 'branches' branches || _files
        else
          _files
        fi
        ;;
    esac
  }

  # Completion for wt-switch: worktree paths only
  _wt_switch() {
    local context state
    typeset -A opt_args

    _arguments -C \
      '1:worktree:->worktree' && return 0

    case "$state" in
      worktree)
        local -a worktrees
        worktrees=(${(f)$(_wt_worktree_list)})

        if (( ${#worktrees[@]} > 0 )); then
          _describe 'worktrees' worktrees || _files -/
        else
          _files -/
        fi
        ;;
    esac
  }

  # Completion for wt-remove: worktree paths only (main repo excluded)
  _wt_remove() {
    local context state
    typeset -A opt_args

    _arguments -C \
      '1:worktree:->worktree' && return 0

    case "$state" in
      worktree)
        local -a worktrees
        worktrees=(${(f)$(_wt_worktree_list)})

        if (( ${#worktrees[@]} > 0 )); then
          _describe 'worktrees' worktrees || _files -/
        else
          _files -/
        fi
        ;;
    esac
  }

  # Completion for wt-cd: worktree paths only
  _wt_cd() {
    local context state
    typeset -A opt_args

    _arguments -C \
      '1:worktree:->worktree' && return 0

    case "$state" in
      worktree)
        local -a worktrees
        worktrees=(${(f)$(_wt_worktree_list)})

        if (( ${#worktrees[@]} > 0 )); then
          _describe 'worktrees' worktrees || _files -/
        else
          _files -/
        fi
        ;;
    esac
  }

  compdef _wt_add   wt-add
  compdef _wt_switch wt-switch
  compdef _wt_remove wt-remove
  compdef _wt_cd wt-cd
fi
