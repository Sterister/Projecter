use crate::favorites::Favorites;
use crate::git::GitInfo;
use std::path::{Path, PathBuf};

/// One row in the browser list.
pub struct Entry {
    pub label: String,
    pub path: Option<PathBuf>,
    pub is_fav: bool,
    pub is_parent: bool,
    pub git: Option<GitInfo>,
}

/// Build the directory listing for `cwd`. At the projects root, favorites are
/// pinned to the top (with their path relative to root) and de-duplicated from
/// the normal alphabetical listing so they never appear twice.
pub fn list_dir(cwd: &Path, root: &Path, favs: &Favorites) -> Vec<Entry> {
    let mut entries = Vec::new();

    if cwd != Path::new("/") {
        entries.push(Entry {
            label: "..".into(),
            path: None,
            is_fav: false,
            is_parent: true,
            git: None,
        });
    }

    let at_root = cwd == root;

    if at_root {
        for fav in &favs.list {
            if fav.is_dir() {
                entries.push(Entry {
                    label: rel_label(fav, root),
                    path: Some(fav.clone()),
                    is_fav: true,
                    is_parent: false,
                    git: None,
                });
            }
        }
    }

    let mut dirs: Vec<PathBuf> = Vec::new();
    if let Ok(rd) = std::fs::read_dir(cwd) {
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                dirs.push(p);
            }
        }
    }
    dirs.sort_by_key(|p| {
        p.file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_lowercase()
    });

    for d in dirs {
        if at_root && favs.contains(&d) {
            continue; // already pinned above
        }
        let is_fav = favs.contains(&d);
        let label = d
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        entries.push(Entry {
            label,
            path: Some(d),
            is_fav,
            is_parent: false,
            git: None,
        });
    }

    entries
}

/// Path relative to the projects root, or the full path if outside it.
pub fn rel_label(p: &Path, root: &Path) -> String {
    match p.strip_prefix(root) {
        Ok(stripped) => stripped.to_string_lossy().to_string(),
        Err(_) => p.to_string_lossy().to_string(),
    }
}
