use std::collections::HashMap;
use std::path::{Path, PathBuf};

use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::widgets::ListState;

use crate::browse::{list_dir, Entry};
use crate::config;
use crate::favorites::Favorites;
use crate::git::{compute_git, GitInfo};

/// What the app decided to do when it exits. Side effects (cd / run) happen in
/// `main` after the terminal is restored.
pub enum Outcome {
    Cd(PathBuf),
    CdAndRun(PathBuf, String),
}

#[derive(Clone, Copy, PartialEq)]
pub enum Screen {
    Browser,
    Action,
}

#[derive(Clone, Copy, PartialEq)]
pub enum ActionItem {
    Shell,
    Claude,
    Back,
}

pub fn action_label(item: ActionItem) -> &'static str {
    match item {
        ActionItem::Shell => "Open shell here",
        ActionItem::Claude => "Start Claude Code",
        ActionItem::Back => "Back",
    }
}

pub struct App {
    pub root: PathBuf,
    pub cwd: PathBuf,
    pub entries: Vec<Entry>,
    pub list_state: ListState,
    pub favorites: Favorites,
    pub last_target: Option<PathBuf>,
    pub screen: Screen,

    pub action_target: PathBuf,
    pub action_items: Vec<ActionItem>,
    pub action_state: ListState,

    /// git status memoized by path so favorite toggles / re-renders stay instant.
    pub git_cache: HashMap<PathBuf, Option<GitInfo>>,

    pub outcome: Option<Outcome>,
    pub should_quit: bool,
}

/// Move a list selection by `delta`, wrapping at both ends.
fn move_sel(state: &mut ListState, len: usize, delta: i32) {
    if len == 0 {
        return;
    }
    let cur = state.selected().unwrap_or(0) as i32;
    let mut next = cur + delta;
    if next < 0 {
        next = len as i32 - 1;
    }
    if next >= len as i32 {
        next = 0;
    }
    state.select(Some(next as usize));
}

impl App {
    pub fn new() -> Self {
        let root = config::root();
        let favorites = Favorites::load(config::fav_file());
        let last_target = std::fs::read_to_string(config::last_file())
            .ok()
            .map(|s| PathBuf::from(s.trim()))
            .filter(|p| p.is_dir());
        let cwd = if root.is_dir() { root.clone() } else { config::home() };

        let entries = list_dir(&cwd, &root, &favorites);
        let mut list_state = ListState::default();
        if !entries.is_empty() {
            list_state.select(Some(0));
        }

        let mut app = App {
            root,
            cwd,
            entries,
            list_state,
            favorites,
            last_target,
            screen: Screen::Browser,
            action_target: PathBuf::new(),
            action_items: Vec::new(),
            action_state: ListState::default(),
            git_cache: HashMap::new(),
            outcome: None,
            should_quit: false,
        };
        app.fill_git();
        app
    }

    fn refresh(&mut self) {
        self.entries = list_dir(&self.cwd, &self.root, &self.favorites);
        if self.entries.is_empty() {
            self.list_state.select(None);
        } else {
            let sel = self
                .list_state
                .selected()
                .unwrap_or(0)
                .min(self.entries.len() - 1);
            self.list_state.select(Some(sel));
        }
        self.fill_git();
    }

    /// Populate each entry's git info, computing uncached paths in parallel.
    fn fill_git(&mut self) {
        let missing: Vec<PathBuf> = self
            .entries
            .iter()
            .filter_map(|e| e.path.clone())
            .filter(|p| !self.git_cache.contains_key(p))
            .collect();

        if !missing.is_empty() {
            let computed = compute_git(&missing);
            for (p, info) in missing.into_iter().zip(computed) {
                self.git_cache.insert(p, info);
            }
        }

        for e in &mut self.entries {
            if let Some(p) = &e.path {
                e.git = self.git_cache.get(p).cloned().flatten();
            }
        }
    }

    fn go_up(&mut self) {
        if self.cwd != Path::new("/") {
            if let Some(parent) = self.cwd.parent() {
                self.cwd = parent.to_path_buf();
                self.list_state.select(Some(0));
                self.refresh();
            }
        }
    }

    fn open_action(&mut self, target: PathBuf, preselect: usize) {
        self.action_target = target;
        let items = vec![ActionItem::Shell, ActionItem::Claude, ActionItem::Back];
        let sel = preselect.min(items.len() - 1);
        self.action_items = items;
        let mut st = ListState::default();
        st.select(Some(sel));
        self.action_state = st;
        self.screen = Screen::Action;
    }

    pub fn on_key(&mut self, key: KeyEvent) {
        match self.screen {
            Screen::Browser => self.browser_key(key),
            Screen::Action => self.action_key(key),
        }
    }

    fn browser_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                // At the very top, ↑ jumps straight to the last-used project.
                if self.list_state.selected() == Some(0) {
                    if let Some(last) = self.last_target.clone() {
                        if last.is_dir() {
                            self.open_action(last, 1); // pre-select "Start Claude Code"
                            return;
                        }
                    }
                }
                move_sel(&mut self.list_state, self.entries.len(), -1);
            }
            KeyCode::Down | KeyCode::Char('j') => {
                move_sel(&mut self.list_state, self.entries.len(), 1);
            }
            KeyCode::Right | KeyCode::Char('l') => self.enter_selected_dir(),
            KeyCode::Left | KeyCode::Char('h') => self.go_up(),
            KeyCode::Enter => {
                if let Some(entry) = self.selected_entry() {
                    if entry.is_parent {
                        self.go_up();
                    } else if let Some(path) = entry.path {
                        self.open_action(path, 0);
                    }
                }
            }
            KeyCode::Char(' ') => self.toggle_favorite(),
            KeyCode::Char('q') | KeyCode::Esc => self.should_quit = true,
            _ => {}
        }
    }

    /// A cheap snapshot of the selected entry's key fields.
    fn selected_entry(&self) -> Option<SelEntry> {
        let sel = self.list_state.selected()?;
        let e = self.entries.get(sel)?;
        Some(SelEntry {
            is_parent: e.is_parent,
            path: e.path.clone(),
        })
    }

    fn enter_selected_dir(&mut self) {
        if let Some(entry) = self.selected_entry() {
            if entry.is_parent {
                self.go_up();
            } else if let Some(path) = entry.path {
                if path.is_dir() {
                    self.cwd = path;
                    self.list_state.select(Some(0));
                    self.refresh();
                }
            }
        }
    }

    fn toggle_favorite(&mut self) {
        let Some(entry) = self.selected_entry() else {
            return;
        };
        if entry.is_parent {
            return;
        }
        let Some(path) = entry.path else {
            return;
        };
        self.favorites.toggle(&path);
        self.refresh();
        // Keep the cursor on the project we just toggled.
        if let Some(pos) = self
            .entries
            .iter()
            .position(|e| e.path.as_deref() == Some(path.as_path()))
        {
            self.list_state.select(Some(pos));
        }
    }

    fn action_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                move_sel(&mut self.action_state, self.action_items.len(), -1)
            }
            KeyCode::Down | KeyCode::Char('j') => {
                move_sel(&mut self.action_state, self.action_items.len(), 1)
            }
            KeyCode::Left | KeyCode::Char('h') | KeyCode::Char('q') | KeyCode::Esc => {
                self.screen = Screen::Browser;
            }
            KeyCode::Enter => {
                let sel = self.action_state.selected().unwrap_or(0);
                let item = self
                    .action_items
                    .get(sel)
                    .copied()
                    .unwrap_or(ActionItem::Back);
                let target = self.action_target.clone();
                match item {
                    ActionItem::Shell => self.outcome = Some(Outcome::Cd(target)),
                    ActionItem::Claude => {
                        self.outcome = Some(Outcome::CdAndRun(
                            target,
                            "claude --dangerously-skip-permissions".into(),
                        ))
                    }
                    ActionItem::Back => self.screen = Screen::Browser,
                }
            }
            _ => {}
        }
    }
}

/// Lightweight snapshot to avoid borrowing `self.entries` across mutations.
struct SelEntry {
    is_parent: bool,
    path: Option<PathBuf>,
}
