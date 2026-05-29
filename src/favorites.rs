use std::fs;
use std::path::{Path, PathBuf};

/// Favorites are absolute project paths, one per line, newest first.
/// Persisted to `~/.project-nav-favorites` so they survive across sessions.
pub struct Favorites {
    pub list: Vec<PathBuf>,
    file: PathBuf,
}

impl Favorites {
    pub fn load(file: PathBuf) -> Self {
        let mut list = Vec::new();
        if let Ok(content) = fs::read_to_string(&file) {
            for line in content.lines() {
                let line = line.trim();
                if !line.is_empty() {
                    list.push(PathBuf::from(line));
                }
            }
        }
        Favorites { list, file }
    }

    pub fn contains(&self, p: &Path) -> bool {
        self.list.iter().any(|f| f == p)
    }

    /// Toggle membership. New favorites go to the top of the list.
    pub fn toggle(&mut self, p: &Path) {
        if let Some(pos) = self.list.iter().position(|f| f == p) {
            self.list.remove(pos);
        } else {
            self.list.insert(0, p.to_path_buf());
        }
        self.save();
    }

    fn save(&self) {
        let mut out = String::new();
        for f in &self.list {
            out.push_str(&f.to_string_lossy());
            out.push('\n');
        }
        let _ = fs::write(&self.file, out);
    }
}
