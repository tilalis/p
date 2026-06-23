# p

A zsh plugin for project-based git worktree and tmux session management.

`p` lets you spin up a "project" as a set of git worktrees (one per repo), open it as a tmux session with one window per worktree, and archive or move it when you're done. Each project is a flat collection of directories under `$P` named `<project>.<repo>[.<postfix>]`.

## Concept

A **project** groups one or more git worktrees that you work on together. For a project named `myproj` using repos `backend` and `frontend`, `p` creates:

```
$P/myproj.backend
$P/myproj.frontend
```

Worktrees are checked out from `$PBASE/<repo>` in detached HEAD state (off `main`). Opening the project creates a tmux session `myproj` with a window per directory.

## Requirements

- `zsh`
- `git` (with worktree support)
- `tmux` (for `open` / `re`)
- `fzf` (for interactive project selection)
- `rsync` (for `archive`)

## Installation

### Manual

Source the plugin from your `.zshrc`:

```zsh
source /path/to/p.plugin.zsh
```

Or with a plugin manager, point it at this directory.

### Oh My Zsh

Clone (or symlink) this directory into your Oh My Zsh custom plugins folder, naming it `p`:

```zsh
git clone <repo-url> ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/p
```

Then add `p` to the plugins list in your `.zshrc` and restart your shell:

```zsh
plugins=(... p)
```

Oh My Zsh automatically sources `p.plugin.zsh` and registers the completions.

## Configuration

Set these environment variables before using `p`:

| Variable | Description |
| --- | --- |
| `P` | Projects directory — where worktrees and tmux sessions live. |
| `PBASE` | Base directory containing the source repos to create worktrees from. |
| `PSESSION` | Set automatically (to `1`) inside a `p open` tmux session. Controls bare `p` behavior. |

```zsh
export P="$HOME/projects"
export PBASE="$HOME/repos"
```

## Usage

```
p [subcommand] [args]
```

Run `p -h` (or `p --help`) for full inline help.

### `p` (no arguments)

- If `$PSESSION` is **not** set: `cd` to `$P`.
- If `$PSESSION` **is** set (you're in a project session): `cd` to the directory matching the current tmux `session.window` (same as `p re`).

### `p add <name> -r <repos...> [-p <postfix>]`

Create project worktrees.

- `<name>` — project name (positional).
- `-r`, `--repos` — one or more repos to add (space-separated).
- `-p`, `--postfix` — optional postfix appended to the directory name.

```zsh
p add myproj -r backend frontend
# Creates $P/myproj.backend and $P/myproj.frontend

p add myproj -r backend -p stuff
# Creates $P/myproj.backend.stuff
```

Worktrees are added from `$PBASE/<repo>` in detached HEAD state off `main`.

### `p open [<name>] [-r]`

Open a project in a tmux session (must be run from inside tmux). Creates a session named `<name>` with one window per `$P/<name>.*` directory, and sets `$PSESSION=1` in the session.

- `<name>` — project to open. If omitted, pick one interactively with `fzf`.
- `-r`, `--re`, `--restore` — if the session already exists, create any missing windows for directories that don't yet have one.

If the session already exists, `p open` switches to it.

### `p re` / `p restore`

`cd` to the directory matching the current tmux `session.window` (i.e. `$P/<session>.<window>`). Useful for jumping back to a worktree's directory after navigating away.

### `p list`

List all project names (unique prefixes of `$P/*.*` directories).

### `p archive <name> [-r <repos...>] [-p <postfix>]`

Archive a project. Copies each matching worktree (excluding `.git`) into `$P/.archive/`, stamps it with an archive timestamp, runs the `cleanup` hook, then removes the worktree with `git worktree remove --force`.

- `<name>` — project to archive. If omitted, pick interactively with `fzf`.
- `-r`, `--repos` — archive only specific repos (optional).
- `-p`, `--postfix` — archive only directories matching the postfix (optional).

### `p prune [--all]`

Remove old archived projects from `$P/.archive`.

- No args — remove archived projects older than 7 days.
- `--all` — remove the entire `.archive` folder.

### `p move <name> <path>`

Move all of a project's worktrees to a new destination directory using `git worktree move`.

```zsh
p move myproj /new/location
```

## Hooks

Place executable zsh scripts in `$P/.hooks/`. Each hook is called with `<repo_path> <worktree_path>`.

| Hook | Runs when |
| --- | --- |
| `add` | After a worktree is created by `p add`. |
| `cleanup` | Before a worktree is removed by `p archive`. |

## Completions

The plugin registers zsh completion (`compdef _p p`) for subcommands, project names, repo names (from `$PBASE`), and options.
