use std::path::{Path, PathBuf};

/// User's home directory.
pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/".into()))
}

/// Projects root — `$PROJECTER_ROOT` or `~/Projects`.
pub fn root() -> PathBuf {
    match std::env::var("PROJECTER_ROOT") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => home().join("Projects"),
    }
}

pub fn fav_file() -> PathBuf {
    home().join(".project-nav-favorites")
}

pub fn last_file() -> PathBuf {
    home().join(".project-nav-last")
}

/// Remember the last-used project so the navigator can offer a quick jump.
pub fn write_last(p: &Path) {
    let _ = std::fs::write(last_file(), p.to_string_lossy().as_bytes());
}

/// Single-quote a string for safe interpolation into the shell command we emit.
pub fn sh_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
