use crate::my;
use crate::tui::term;

#[derive(Debug, Copy, Clone, Default)]
pub struct Region {
    pub row: usize,
    pub col: usize,
    pub width: usize,
    pub height: usize,
}

impl Region {
    pub fn pop(&mut self, count: usize, side: Side) -> Option<Region> {
        let mut res = None;

        match side {
            Side::Top => {
                if self.height >= count {
                    res = Some(Region {
                        row: self.row,
                        col: self.col,
                        width: self.width,
                        height: count,
                    });

                    self.row += count;
                    self.height -= count;
                }
            }
            Side::Bottom => {
                if self.height >= count {
                    self.height -= count;

                    res = Some(Region {
                        row: self.row + self.height,
                        col: self.col,
                        width: self.width,
                        height: count,
                    });
                }
            }
            Side::Left => {
                if self.width >= count {
                    res = Some(Region {
                        row: self.row,
                        col: self.col,
                        width: count,
                        height: self.height,
                    });

                    self.col += count;
                    self.width -= count;
                }
            }
            Side::Right => {
                if self.width >= count {
                    self.width -= count;

                    res = Some(Region {
                        row: self.row,
                        col: self.col + self.width,
                        width: count,
                        height: self.height,
                    });
                }
            }
        }

        res
    }
}

pub enum Side {
    Top,
    Left,
    Right,
    Bottom,
}

#[derive(Default)]
pub struct Layout {
    pub path: Region,
    pub parent: Region,
    pub location: Region,
    pub preview: Region,
    pub status: Region,
}

impl Layout {
    pub fn new() -> Layout {
        Default::default()
    }

    pub fn create(term: &term::Term) -> my::Result<Layout> {
        let mut region = term.region()?;
        let mut res = Layout::new();
        res.path = region
            .pop(1, Side::Top)
            .ok_or(my::Error::create("Could not pop region for path"))?;
        res.status = region
            .pop(1, Side::Bottom)
            .ok_or(my::Error::create("Could not pop region for status"))?;

        let w = region.width / 4;
        res.parent = region
            .pop(w, Side::Left)
            .ok_or(my::Error::create("Could not pop region for parent"))?;
        res.location = region
            .pop(w, Side::Left)
            .ok_or(my::Error::create("Could not pop region for location"))?;
        res.preview = region;

        Ok(res)
    }
}
