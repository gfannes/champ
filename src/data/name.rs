use std::rc::Rc;

pub type Name = Rc<Data>;

#[derive(Default)]
pub struct Data {
    pub name: String,
    pub parent: Option<Name>,
}

impl std::fmt::Display for Data {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if let Some(parent) = &self.parent {
            parent.fmt(f)?;
        }
        write!(f, "/{}", &self.name)?;
        Ok(())
    }
}

pub trait Build {
    fn root(name: impl Into<String>) -> Name;
    fn add(&self, name: impl Into<String>) -> Name;
}

impl Build for Name {
    fn root(name: impl Into<String>) -> Name {
        Rc::new(Data {
            name: name.into(),
            parent: None,
        })
    }
    fn add(&self, name: impl Into<String>) -> Name {
        Rc::new(Data {
            name: name.into(),
            parent: Some(self.clone()),
        })
    }
}

#[test]
fn test_name() {
    let root = Name::root("ROOT");
    assert_eq!(format!("{}", root), "/ROOT");
    let a = root.add("a");
    let b = root.add("b");
    let c = a.add("c");
    assert_eq!(format!("{}", c), "/ROOT/a/c");
}
