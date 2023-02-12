pub use crate::my::Result;
pub use crate::tui::layout::{Layout, Region, Side};
pub use crate::tui::list::List;
pub use crate::tui::term::Term;
pub use crate::tui::text::Text;
pub use crossterm::event::{Event, KeyCode};

mod layout;
mod list;
pub mod status;
mod term;
mod text;
