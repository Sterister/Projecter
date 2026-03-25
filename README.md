# Projecter

A terminal-based project navigator with arrow key navigation, scrolling, and directory browsing. Built in pure bash with no dependencies.

![Bash](https://img.shields.io/badge/bash-4.0%2B-green) ![License](https://img.shields.io/badge/license-MIT-blue)

## What it does

Projecter gives you three tools:

- **`p`** — A quick-launch command that opens an interactive directory browser starting from your projects folder. Navigate with arrow keys, select a folder, and either open a shell or start [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in it. Includes a "repeat last" shortcut for opening multiple terminals in the same project.

- **`s`** — SSH quick-connect menu. Type `s` in any terminal to get an interactive list of your machines (Tailscale, LAN, DNS). Uses `fzf` if installed, falls back to a numbered list. Hosts are configured in `~/.config/ssh-menu/hosts`.

- **SSH greeting menu** — Automatically shows the same navigator when you SSH into your machine. Greets you by name.

### Features

- Arrow key navigation (up/down/left/right)
- Browse into subdirectories freely — not locked to one level
- Navigate anywhere on the filesystem (not just projects)
- Scrolling with indicators when the list exceeds terminal height
- Adapts to terminal resize (handles `SIGWINCH`)
- Flicker-free rendering (buffered output, no `clear` during navigation)
- "Repeat last" — press `↑` at the top of the list to jump back to your last project
- Action menu: open shell, start Claude Code, or go back
- Pure bash, no dependencies beyond `tput` and `find`

## Install

```bash
git clone https://github.com/Sterister/Projecter.git
cd Projecter
bash install.sh
```

The installer copies the scripts to your home directory and adds the necessary hooks to your `.bashrc` or `.zshrc`.

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

### SSH greeting

The menu appears automatically on first SSH login. No action needed.

### Controls

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate list |
| `→` / `Enter` | Open directory / select |
| `←` | Go back to parent |
| `↑` (at top) | Jump to last used project (in `p` mode) |
| `q` / `Esc` | Quit |

### Action menu

After selecting a directory, you get:

- **Open shell here** — `cd` into the directory
- **Start Claude Code** — `cd` and launch `claude --dangerously-skip-permissions`
- **Back** — return to the browser

## How it works

Both scripts are sourced (not executed) so that `cd` affects your current shell. Rendering uses ANSI escape codes with buffered output for flicker-free updates. Terminal size is checked on every redraw and on `SIGWINCH`.

## License

MIT
