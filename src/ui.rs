use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::{action_label, App, Screen};
use crate::browse::rel_label;
use crate::config;
use crate::git::GitInfo;

fn dim() -> Style {
    Style::default().add_modifier(Modifier::DIM)
}
fn yellow() -> Style {
    Style::default().fg(Color::Yellow)
}
fn highlight() -> Style {
    Style::default()
        .bg(Color::Indexed(236))
        .fg(Color::Green)
        .add_modifier(Modifier::BOLD)
}

/// Styled spans for a project's git state: ` branch ● ↑n ↓n`.
fn git_spans(g: &GitInfo) -> Vec<Span<'static>> {
    let mut spans = vec![Span::styled(
        format!("  {}", g.branch),
        Style::default().fg(Color::Cyan).add_modifier(Modifier::DIM),
    )];
    if g.dirty {
        spans.push(Span::styled(" ●", yellow()));
    }
    if g.ahead > 0 {
        spans.push(Span::styled(format!(" ↑{}", g.ahead), Style::default().fg(Color::Green)));
    }
    if g.behind > 0 {
        spans.push(Span::styled(format!(" ↓{}", g.behind), Style::default().fg(Color::Red)));
    }
    spans
}

pub fn draw(f: &mut Frame, app: &App) {
    match app.screen {
        Screen::Browser => browser(f, app),
        Screen::Action => action(f, app),
    }
}

fn browser(f: &mut Frame, app: &App) {
    let chunks = Layout::vertical([
        Constraint::Length(3),
        Constraint::Min(1),
        Constraint::Length(1),
    ])
    .split(f.area());

    let mut head: Vec<Line> = vec![
        Line::from(Span::styled(
            " Project Navigator",
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(format!(" {}", breadcrumb(app)), yellow())),
    ];
    match &app.last_target {
        Some(last) => head.push(Line::from(Span::styled(
            format!(" ↑ Last: {}", rel_label(last, &app.root)),
            dim(),
        ))),
        None => head.push(Line::from("")),
    }
    f.render_widget(Paragraph::new(head), chunks[0]);

    let items: Vec<ListItem> = app
        .entries
        .iter()
        .map(|e| {
            let mut spans = if e.is_parent {
                vec![Span::styled("..", dim())]
            } else if e.is_fav {
                vec![Span::styled(format!("★ {}", e.label), yellow())]
            } else {
                vec![Span::raw(e.label.clone())]
            };
            if let Some(g) = &e.git {
                spans.extend(git_spans(g));
            }
            ListItem::new(Line::from(spans))
        })
        .collect();

    let list = List::new(items)
        .highlight_style(highlight())
        .highlight_symbol(" > ");
    let mut state = app.list_state.clone();
    f.render_stateful_widget(list, chunks[1], &mut state);

    f.render_widget(
        Paragraph::new(Span::styled(
            " ↑↓ navigate   → open   ← back   space ★ fav   enter select   q quit",
            dim(),
        )),
        chunks[2],
    );
}

fn action(f: &mut Frame, app: &App) {
    let chunks = Layout::vertical([
        Constraint::Length(3),
        Constraint::Min(1),
        Constraint::Length(1),
    ])
    .split(f.area());

    let mut head: Vec<Line> = vec![
        Line::from(Span::styled(
            " Project Navigator",
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        )),
        Line::from(vec![
            Span::styled(" Open: ", yellow()),
            Span::styled(
                rel_label(&app.action_target, &app.root),
                yellow().add_modifier(Modifier::BOLD),
            ),
        ]),
    ];
    // Show git state of the selected project, if any.
    match app.git_cache.get(&app.action_target).and_then(|o| o.as_ref()) {
        Some(g) => {
            let mut spans = vec![Span::styled(" git:", dim())];
            spans.extend(git_spans(g));
            head.push(Line::from(spans));
        }
        None => head.push(Line::from("")),
    }
    f.render_widget(Paragraph::new(head), chunks[0]);

    let items: Vec<ListItem> = app
        .action_items
        .iter()
        .map(|it| ListItem::new(Line::from(action_label(*it))))
        .collect();
    let list = List::new(items)
        .highlight_style(highlight())
        .highlight_symbol(" > ");
    let mut state = app.action_state.clone();
    f.render_stateful_widget(list, chunks[1], &mut state);

    f.render_widget(
        Paragraph::new(Span::styled(
            " ↑↓ navigate   enter select   ← back   q quit",
            dim(),
        )),
        chunks[2],
    );
}

fn breadcrumb(app: &App) -> String {
    if app.cwd == app.root {
        return "Projects".into();
    }
    if let Ok(rel) = app.cwd.strip_prefix(&app.root) {
        return format!("Projects / {}", rel.to_string_lossy().replace('/', " / "));
    }
    if let Ok(rel) = app.cwd.strip_prefix(config::home()) {
        return format!("~ / {}", rel.to_string_lossy().replace('/', " / "));
    }
    app.cwd.to_string_lossy().to_string()
}
