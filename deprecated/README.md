# Deprecated

These are the original **bash** implementations of the project navigator,
kept here for reference only. They are no longer installed or wired up.

- `project-nav.sh` — the original `p` navigator (arrow-key browser, action menu).
- `workspace-builder.sh` — the visual multi-pane tilix workspace builder.

They have been replaced by the Rust TUI (`src/`, the `projecter` binary), which
is faster (diffed rendering, real event loop, no per-keystroke process spawn) and
adds favorites and per-project git status. The workspace builder was dropped and
is not reimplemented.
