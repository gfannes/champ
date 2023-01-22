use crate::data;

#[derive(Default)]
pub struct List {
    pub items: Vec<String>,
    pub focus: Option<usize>,
}

impl List {
    pub fn new() -> List {
        Default::default()
    }

    pub fn set_items(&mut self, nodes: &Vec<String>, filter: &data::Filter) {
        let focus_str = self.focus.map(|ix| self.items[ix].clone());
        self.focus = None;

        self.items.clear();
        for (ix, s) in nodes.iter().enumerate() {
            let mut include = true;

            let is_hidden = s.starts_with(".");
            if is_hidden && !filter.hidden {
                include = false;
            }

            if include {
                let s = s.to_string();
                if let Some(focus_str) = &focus_str {
                    if self.focus.is_none() && s == *focus_str {
                        self.focus = Some(ix);
                    }
                }

                self.items.push(s);
            }
        }
    }

    pub fn update_focus(&mut self, index: &mut data::Index) {
        index.update(&self.items);
        if index.ix < 0 {
            self.focus = None;
        } else {
            self.focus = Some(index.ix as usize);
        }
    }
}
