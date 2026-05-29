use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Compact git state for a project, shown next to its name in the browser.
#[derive(Clone)]
pub struct GitInfo {
    pub branch: String,
    pub dirty: bool,
    pub ahead: u32,
    pub behind: u32,
}

/// Branch + dirty + ahead/behind from a single `git status` call.
/// Returns `None` when `dir` is not (inside) a git work tree.
pub fn git_info(dir: &Path) -> Option<GitInfo> {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["status", "--porcelain", "--branch"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&out.stdout);
    let mut lines = text.lines();
    let header = lines.next().unwrap_or("");
    let (branch, ahead, behind) = parse_branch_line(header);
    // Any line after the `## ...` header is a change → working tree is dirty.
    let dirty = lines.next().is_some();

    Some(GitInfo {
        branch,
        dirty,
        ahead,
        behind,
    })
}

fn parse_branch_line(line: &str) -> (String, u32, u32) {
    let s = line.trim_start_matches("## ").trim();

    if s.starts_with("HEAD (no branch)") {
        return ("HEAD".into(), 0, 0);
    }
    if let Some(rest) = s.strip_prefix("No commits yet on ") {
        return (rest.trim().to_string(), 0, 0);
    }

    let branch = match s.split_once("...") {
        Some((b, _)) => b.to_string(),
        None => s.split_whitespace().next().unwrap_or("").to_string(),
    };

    let (mut ahead, mut behind) = (0u32, 0u32);
    if let Some(start) = s.find('[') {
        if let Some(end_rel) = s[start..].find(']') {
            let inside = &s[start + 1..start + end_rel];
            for part in inside.split(',') {
                let part = part.trim();
                if let Some(n) = part.strip_prefix("ahead ") {
                    ahead = n.trim().parse().unwrap_or(0);
                } else if let Some(n) = part.strip_prefix("behind ") {
                    behind = n.trim().parse().unwrap_or(0);
                }
            }
        }
    }

    (branch, ahead, behind)
}

/// Resolve git info for many directories with bounded parallelism, so entering
/// a folder full of repos stays fast (≈ the slowest single `git` call).
pub fn compute_git(paths: &[PathBuf]) -> Vec<Option<GitInfo>> {
    let mut out = Vec::with_capacity(paths.len());
    for chunk in paths.chunks(16) {
        let results = std::thread::scope(|s| {
            let handles: Vec<_> = chunk.iter().map(|p| s.spawn(|| git_info(p))).collect();
            handles
                .into_iter()
                .map(|h| h.join().unwrap_or(None))
                .collect::<Vec<Option<GitInfo>>>()
        });
        out.extend(results);
    }
    out
}
