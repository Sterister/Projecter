mod app;
mod browse;
mod config;
mod favorites;
mod git;
mod ui;

use std::io;

use ratatui::backend::{Backend, CrosstermBackend};
use ratatui::crossterm::{
    cursor::{Hide, Show},
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::Terminal;

use app::{App, Outcome};

fn main() -> io::Result<()> {
    let mut app = App::new();

    // The TUI is drawn to stderr so that stdout stays clean for the single
    // shell command we emit on exit (the `p` wrapper does `eval "$(projecter)"`).
    enable_raw_mode()?;
    execute!(io::stderr(), EnterAlternateScreen, Hide)?;
    let backend = CrosstermBackend::new(io::stderr());
    let mut terminal = Terminal::new(backend)?;

    let res = run(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(io::stderr(), LeaveAlternateScreen, Show)?;

    res?;

    // Side effects run after the terminal is restored.
    match app.outcome.take() {
        Some(Outcome::Cd(p)) => {
            config::write_last(&p);
            println!("cd {}", config::sh_quote(&p.to_string_lossy()));
        }
        Some(Outcome::CdAndRun(p, cmd)) => {
            config::write_last(&p);
            println!("cd {} && {}", config::sh_quote(&p.to_string_lossy()), cmd);
        }
        None => {}
    }

    Ok(())
}

fn run<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui::draw(f, app))?;
        if app.should_quit || app.outcome.is_some() {
            break;
        }
        // Blocking read — instant response, no polling, no per-key process spawn.
        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Release {
                app.on_key(key);
            }
        }
    }
    Ok(())
}
