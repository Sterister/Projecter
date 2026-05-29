# Projecter

A terminal-based project navigator with arrow key navigation, favorites, and per-project git status. The navigator (`p`) is a fast Rust TUI built on [ratatui](https://ratatui.rs); the SSH helpers are bash.

![Rust](https://img.shields.io/badge/rust-1.70%2B-orange) ![License](https://img.shields.io/badge/license-MIT-blue)

## What it does

Projecter gives you four tools:

- **`p`** — A quick-launch command that opens an interactive directory browser starting from your projects folder. Navigate with arrow keys, select a folder, and either open a shell or start [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in it. Each project shows its git branch and dirty/ahead/behind state. Star projects with `space` to pin them to the top, and press `↑` at the top to jump back to your last project.

- **`s`** — SSH quick-connect menu. Type `s` in any terminal to get an interactive list of your machines (Tailscale, LAN, DNS). Uses `fzf` if installed, falls back to a numbered list. Hosts are configured in `~/.config/ssh-menu/hosts`.

- **`c`** — Launch [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with `--dangerously-skip-permissions` in one keystroke. Passes through any extra arguments.

- **SSH greeting menu** — Automatically shows the same navigator when you SSH into your machine. Greets you by name.

### Features

- Arrow key navigation (up/down/left/right), with `j`/`k`/`h`/`l` aliases
- **Favorites** — press `space` to pin a project to the top; pins are stored in `~/.project-nav-favorites` and survive restarts. Even deeply nested projects show up at the root.
- **Git status** — each project shows its branch, a `●` when the working tree is dirty, and `↑`/`↓` ahead/behind counts. Computed in parallel so large project folders stay snappy.
- Browse into subdirectories freely — navigate anywhere on the filesystem
- "Repeat last" — press `↑` at the top of the list to jump back to your last project
- Diffed rendering with a real event loop — no input lag, correct scrolling
- Adapts to terminal resize automatically

## Install

```bash
git clone https://github.com/Sterister/Projecter.git
cd Projecter
bash install.sh
```

Requires a Rust toolchain ([rustup.rs](https://rustup.rs)). The installer builds the `projecter` binary, installs it to `~/.local/bin`, and adds the necessary hooks to your `.bashrc` or `.zshrc`.

## Configuration

Add these to your shell config (`.bashrc` / `.zshrc`) **before** the Projecter hooks:

```bash
# Set your projects directory (default: ~/Projects)
export PROJECTER_ROOT="$HOME/Documents/Projects"

# Set your name for the SSH greeting (default: your username)
export PROJECTER_USER="Stian"
```

## Usage

### Local terminal

```
$ p
```

Opens the project navigator. Use arrow keys to browse, Enter to select.

### SSH quick-connect

```
$ s
```

Opens an interactive SSH menu. Add your machines to `~/.config/ssh-menu/hosts`:

```
# Name | User | Address (IP or DNS)
Desktop | stian | 100.x.x.x
Server  | root  | myserver.example.com
```

Uses `fzf` for interactive filtering if installed (`sudo apt install fzf`), otherwise shows a numbered list.

### Claude Code quick-launch

```
$ c
```

Starts Claude Code with `--dangerously-skip-permissions`. Supports extra args, e.g. `c --model sonnet`.

### SSH greeting

The menu appears automatically on first SSH login. No action needed.

### Controls

| Key | Action |
|-----|--------|
| `↑` / `↓` (or `k` / `j`) | Navigate list |
| `→` / `Enter` (or `l`) | Open directory / select |
| `←` (or `h`) | Go back to parent |
| `space` | Toggle favorite (pins to top) |
| `↑` (at top) | Jump to last used project |
| `q` / `Esc` | Quit |

### Action menu

After selecting a directory, you get:

- **Open shell here** — `cd` into the directory
- **Start Claude Code** — `cd` and launch `claude --dangerously-skip-permissions`
- **Back** — return to the browser

## How it works

The navigator is a Rust TUI that renders to **stderr** and prints a single shell command (`cd '…'`, optionally `&& claude …`) to **stdout** on exit. The `p` shell function is `eval "$(~/.local/bin/projecter)"`, so the emitted `cd` runs in your current shell — the same trick `fzf` and `zoxide` use. Rendering is diffed by ratatui, and key events come from a blocking event loop, so there is no polling and no per-keystroke process spawn.

## License

MIT
