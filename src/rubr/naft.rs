use crate::util;
use std::{cell, io::Write, rc};

pub struct Node {
    // &todo Support String iso Stdout, maybe anything that can std::io::Write
    pub out: rc::Rc<cell::RefCell<std::io::Stdout>>,
    pub level: usize,
    pub name: Option<String>,
}
impl Node {
    pub fn new(out: std::io::Stdout) -> Node {
        Node {
            out: cell::RefCell::new(out).into(),
            level: 0,
            name: None,
        }
    }

    pub fn name(&self, name: &str) -> Node {
        Node {
            out: self.out.clone(),
            level: self.level,
            name: Some(name.into()),
        }
    }

    pub fn node(&self, tag: &str) -> util::Result<Node> {
        {
            let mut cout = self.out.as_ref().borrow_mut();
            write!(cout, "\n{}", "  ".repeat(self.level))?;
            if let Some(name) = &self.name {
                write!(cout, "[{}:{}]", name, tag)?;
            } else {
                write!(cout, "[{}]", tag)?;
            }
        }

        Ok(Node {
            out: self.out.clone(),
            level: self.level + 1,
            name: None,
        })
    }

    pub fn attr(&self, name: &str, value: &impl std::fmt::Display) -> util::Result<()> {
        let mut cout = self.out.as_ref().borrow_mut();
        write!(cout, "({}:{})", name, value)?;
        Ok(())
    }
}
impl std::io::Write for Node {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let mut cout = self.out.as_ref().borrow_mut();
        cout.write(buf)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        let mut cout = self.out.as_ref().borrow_mut();
        cout.flush()
    }
}

pub trait ToNaft {
    fn to_naft(&self, p: &Node) -> util::Result<()>;
}
