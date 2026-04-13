__p_help() {
  echo "Usage: p [subcommand]"
  echo
  echo "  p                cd to \$P (projects directory)"
  echo "                   If \$PSESSION is set, cd to dir matching current tmux session.window (same as re)"
  echo
  echo "Subcommands:"
  echo "  add              Create project worktrees"
  echo "    <name>         Project name (positional)"
  echo "    -r, --repos    Repos to add (space-separated)"
  echo "    -p, --postfix  Optional postfix appended to dir name"
  echo
  echo "  open             Open project in tmux session (sets \$PSESSION=1)"
  echo "    <name>         Project name to open"
  echo "    -p, --postfix  Only open dirs matching postfix; session named name.postfix"
  echo
  echo "  re|restore       cd to dir matching current tmux session.window"
  echo "    -a, --all      Reopen missing windows in existing session"
  echo
  echo "  list             List all projects"
  echo
  echo "  archive          Archive project by name"
  echo "    <name>         Project name to archive"
  echo "    -r, --repos    Archive only specific repos (optional)"
  echo "    -p, --postfix  Archive only dirs matching postfix (optional)"
  echo
  echo "  prune            Remove old archived projects"
  echo "    --all          Remove entire .archive folder"
  echo
  echo "  move             Move project worktrees to a new path"
  echo "    <name>         Project name"
  echo "    <path>         Destination directory"
  echo
  echo "Examples:"
  echo "  p add myproj -r backend frontend"
  echo "  Creates \$P/myproj.backend and \$P/myproj.frontend"
  echo
  echo "  p add myproj -r backend -p stuff"
  echo "  Creates \$P/myproj.backend.stuff"
  echo
  echo "  Worktrees are added from \$PBASE/<repo> in detached HEAD state"
  echo
  echo "  p open myproj"
  echo "  Creates a tmux session 'myproj' with a window per \$P/myproj.* dir"
  echo
  echo "Hooks:"
  echo "  Place executable zsh scripts in \$P/.hooks/"
  echo "  Supported hooks: add, cleanup"
  echo "  Arguments: <repo_path> <worktree_path>"
}

__p_run_hook() {
  local hook="$P/.hooks/$1"
  shift
  if [[ -x "$hook" ]]; then
    "$hook" "$@"
  fi
}

__p_add() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Error: project name is required" >&2
    return 1
  fi
  shift

  local postfix=""
  local -a repos=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--postfix)
        postfix="$2"
        shift 2
        ;;
      -r|--repos)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
          repos+=("$1")
          shift
        done
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ ${#repos[@]} -eq 0 ]]; then
    echo "Error: --repos requires at least one repo" >&2
    return 1
  fi

  for repo in "${repos[@]}"; do
    local dir="$P/${name}.${repo}${postfix:+.${postfix}}"
    mkdir -p "$dir"
    git -C "$PBASE/${repo}" worktree add --detach "$dir" main
    __p_run_hook add "$PBASE/${repo}" "$dir"
  done
}

__p_open() {
  if [[ -z "$TMUX" ]]; then
    echo "Error: not inside a tmux session" >&2
    return 1
  fi

  local name=""
  local postfix=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--postfix)
        postfix="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 1
        ;;
      *)
        name="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$name" ]]; then
    name=$(__p_list | fzf --tmux --prompt='Project: ') || return 0
  fi

  local session_name="$name"
  local -a dirs
  if [[ -n "$postfix" ]]; then
    dirs=("$P"/${name}.*.${postfix}(/N))
    session_name="${name}-${postfix}"
  else
    dirs=("$P"/${name}.*(/N))
  fi

  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "Error: no directories matching ${name}.* in \$P" >&2
    return 1
  fi

  if tmux has-session -t "=$session_name" 2>/dev/null; then
    tmux switch-client -t "=$session_name"
    return
  fi

  tmux new-session -d -s "$session_name" -c "${dirs[1]}" -n "${dirs[1]#*.}" -e PSESSION=1 -e PNAME="$name" -e PPOSTFIX="$postfix"

  for dir in "${dirs[@]:1}"; do
    tmux new-window -t "=$session_name" -c "$dir" -n "${dir#*.}"
  done

  tmux switch-client -t "=$session_name"
}

__p_re() {
  if [[ -z "$TMUX" ]]; then
    echo "Error: not inside a tmux session" >&2
    return 1
  fi

  local all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--all)
        all=1
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  local session=$(tmux display-message -p '#{session_name}')

  if [[ "$all" -eq 1 ]]; then
    local name="${PNAME:-$session}"
    local postfix="$PPOSTFIX"
    local -a dirs
    if [[ -n "$postfix" ]]; then
      dirs=("$P"/${name}.*.${postfix}(/N))
    else
      dirs=("$P"/${name}.*(/N))
    fi
    if [[ ${#dirs[@]} -eq 0 ]]; then
      echo "Error: no directories matching session in \$P" >&2
      return 1
    fi
    local -a existing_windows
    existing_windows=("${(@f)$(tmux list-windows -t "=$session" -F '#{window_name}')}")
    for dir in "${dirs[@]}"; do
      local wname="${dir:t}"
      wname="${wname#*.}"
      if (( ! ${existing_windows[(Ie)$wname]} )); then
        tmux new-window -t "=$session" -c "$dir" -n "$wname"
      fi
    done
    return
  fi

  local name="${PNAME:-$session}"
  local window=$(tmux display-message -p '#{window_name}')
  local target="$P/${name}.${window}"

  if [[ ! -d "$target" ]]; then
    echo "Error: directory $target does not exist" >&2
    return 1
  fi

  cd "$target"
}

__p_archive() {
  local name="$1"
  if [[ -z "$name" ]]; then
    name=$(__p_list | fzf --tmux --prompt='Archive project: ') || return 0
  fi
  shift

  local postfix=""
  local -a repos=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--repos)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
          repos+=("$1")
          shift
        done
        ;;
      -p|--postfix)
        postfix="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  local -a dirs
  if [[ ${#repos[@]} -gt 0 && -n "$postfix" ]]; then
    for repo in "${repos[@]}"; do
      local -a matched=("$P"/${name}.${repo}.${postfix}(/N))
      dirs+=("${matched[@]}")
    done
  elif [[ ${#repos[@]} -gt 0 ]]; then
    for repo in "${repos[@]}"; do
      local -a matched=("$P"/${name}.${repo}*(/N))
      dirs+=("${matched[@]}")
    done
  elif [[ -n "$postfix" ]]; then
    dirs=("$P"/${name}.*.${postfix}(/N))
  else
    dirs=("$P"/${name}.*(/N))
  fi

  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "Error: no directories matching ${name}.* in \$P" >&2
    return 1
  fi

  mkdir -p "$P/.archive"

  for dir in "${dirs[@]}"; do
    local base="${dir:t}"
    local dest="$P/.archive/$base"
    local repo_path
    repo_path=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    repo_path="${repo_path%/.git}"
    __p_run_hook cleanup "$repo_path" "$dir"
    mkdir -p "$dest"
    rsync -a --exclude='.git' "$dir/" "$dest/"
    date -Iseconds > "$dest/.parchived"
    git -C "$dir" worktree remove --force "$dir"
  done

  echo "Archived project '$name' to \$P/.archive"
}

__p_prune() {
  local archive_dir="$P/.archive"

  if [[ ! -d "$archive_dir" ]]; then
    echo "Nothing to prune: $archive_dir does not exist"
    return 0
  fi

  if [[ "$1" == "--all" ]]; then
    rm -rf "$archive_dir"
    echo "Removed $archive_dir"
    return 0
  fi

  local now=$(date +%s)
  local cutoff=$((now - 7 * 86400))
  local count=0

  for dir in "$archive_dir"/*(/:N); do
    local pfile="$dir/.parchived"
    if [[ ! -f "$pfile" ]]; then
      continue
    fi
    local ts=$(date -d "$(cat "$pfile")" +%s 2>/dev/null)
    if [[ -n "$ts" && "$ts" -lt "$cutoff" ]]; then
      rm -rf "$dir"
      ((count++))
    fi
  done

  echo "Pruned $count archived project(s) older than 7 days"
}

__p_move() {
  local name="$1"
  local dest="$2"

  if [[ -z "$name" || -z "$dest" ]]; then
    echo "Usage: p move <name> <path>" >&2
    return 1
  fi

  local -a dirs=("$P"/${name}.*(/N))
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "Error: no directories matching ${name}.* in \$P" >&2
    return 1
  fi

  mkdir -p "$dest"

  for dir in "${dirs[@]}"; do
    local base="${dir:t}"
    git worktree move "$dir" "$dest/$base"
  done

  echo "Moved project '$name' to $dest"
}

__p_list() {
  local -a dirs=("$P"/*.*(/:t))
  local -a names=()
  for d in "${dirs[@]}"; do
    names+=("${d%%.*}")
  done
  print -l "${(@u)names}" | sort
}

p() {
  if [[ $# -eq 0 ]]; then
    if [[ -z "$PSESSION" ]]; then
      cd "$P"
    else
      __p_re
    fi

    return
  fi

  case "$1" in
    p)
      cd "$P"
      return
      ;;
    -h|--help)
      __p_help
      return 0
      ;;
  esac

  local subcmd="$1"
  shift

  case "$subcmd" in
    add)
      __p_add "$@"
      ;;
    open)
      __p_open "$@"
      ;;
    re|restore)
      __p_re "$@"
      ;;
    list)
      __p_list
      ;;
    archive)
      __p_archive "$@"
      ;;
    prune)
      __p_prune "$@"
      ;;
    move)
      __p_move "$@"
      ;;
    *)
      echo "Unknown subcommand: $subcmd" >&2
      return 1
      ;;
  esac
}

_p() {
  local -a subcmds=(
    'add:Create project worktrees'
    'open:Open project in tmux session'
    're:cd to dir matching current tmux session.window'
    'restore:cd to dir matching current tmux session.window'
    'list:List all projects'
    'archive:Archive project by name'
    'prune:Remove old archived projects'
    'move:Move project worktrees to a new path'
  )

  if (( CURRENT == 2 )); then
    _describe 'subcommand' subcmds
    return
  fi

  case "${words[2]}" in
    add)
      if (( CURRENT == 3 )); then
        local -a names=()
        local -a dirs=("$P"/*.*(/:t))
        for d in "${dirs[@]}"; do
          names+=("${d%%.*}")
        done
        local -a unames=(${(@u)names})
        _describe 'project' unames
        return
      fi
      local prev="${words[CURRENT-1]}"
      case "$prev" in
        (-p|--postfix)
          ;;
        (-r|--repos)
          compadd -- "$PBASE"/*(/:t)
          ;;
        (*)
          local j
          for (( j = CURRENT - 1; j >= 3; j-- )); do
            case "${words[j]}" in
              (-p|--postfix) break ;;
              (-r|--repos) compadd -- "$PBASE"/*(/:t); return ;;
            esac
          done
          compadd -- -r --repos -p --postfix
          ;;
      esac
      ;;
    open)
      local name="" has_postfix=0
      local i
      for (( i = 3; i < CURRENT; i++ )); do
        case "${words[i]}" in
          -p|--postfix) has_postfix=1 ;;
          -*) ;;
          *) [[ -z "$name" ]] && name="${words[i]}" ;;
        esac
      done

      local prev="${words[CURRENT-1]}"
      if [[ ( "$prev" = -p || "$prev" = --postfix ) && -n "$name" ]]; then
        local -a postfixes=()
        for d in "$P"/${name}.*(/N:t); do
          local rest="${d#${name}.}"
          [[ "$rest" = *.* ]] && postfixes+=("${rest#*.}")
        done
        compadd -- "${(@u)postfixes}"
        return
      fi

      if [[ -z "$name" ]]; then
        local -a names=()
        local -a dirs=("$P"/*.*(/:t))
        for d in "${dirs[@]}"; do
          names+=("${d%%.*}")
        done
        local -a unames=(${(@u)names})
        _describe 'project' unames
      fi
      (( ! has_postfix )) && compadd -- -p --postfix
      ;;
    re|restore)
      compadd -- -a --all
      ;;
    move)
      if (( CURRENT == 3 )); then
        local -a names=()
        local -a dirs=("$P"/*.*(/:t))
        for d in "${dirs[@]}"; do
          names+=("${d%%.*}")
        done
        local -a unames=(${(@u)names})
        _describe 'project' unames
      elif (( CURRENT == 4 )); then
        _path_files -/
      fi
      ;;
    archive)
      if (( CURRENT == 3 )); then
        local -a names=()
        local -a dirs=("$P"/*.*(/:t))
        for d in "${dirs[@]}"; do
          names+=("${d%%.*}")
        done
        local -a unames=(${(@u)names})
        _describe 'project' unames
      else
        local prev="${words[CURRENT-1]}"
        case "$prev" in
          (-r|--repos)
            compadd -- "$PBASE"/*(/:t)
            ;;
          (-p|--postfix)
            ;;
          (*)
            compadd -- -r --repos -p --postfix
            ;;
        esac
      fi
      ;;
    prune)
      if (( CURRENT == 3 )); then
        compadd -- --all
      fi
      ;;
  esac
}

compdef _p p
