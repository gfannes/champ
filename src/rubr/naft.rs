// &!:rubr:naft:

pub trait ToNaft {
    fn to_naft(&self, b: &mut Body<'_, '_>) -> std::fmt::Result;
}

pub struct Body<'a, 'b> {
    fmt: &'a mut std::fmt::Formatter<'b>,
    level: usize,
    do_close: bool,
}

// Newtype used to wrap a reference and get into ToNaft.to_naft()
// `println!("{}", AsNaft::<T>::new(&obj))` will call `obj.to_naft(b)`
pub struct AsNaft<'a, T>(&'a T);

impl<'a, 'b> Body<'a, 'b> {
    pub fn new<'c>(fmt: &'c mut std::fmt::Formatter<'b>) -> Body<'c, 'b> {
        Body {
            fmt,
            level: 0,
            do_close: false,
        }
    }

    pub fn node<T>(&mut self, v: &T) -> std::fmt::Result
    where
        T: std::fmt::Display,
    {
        if self.level > 0 {
            if !self.do_close {
                write!(self.fmt, "{{");
                self.do_close = true;
            }
            write!(self.fmt, "\n");
            self.indent()?;
        }
        write!(self.fmt, "[{v}]")
    }

    pub fn attr<T>(&mut self, k: &str, v: &T) -> std::fmt::Result
    where
        T: std::fmt::Display,
    {
        write!(self.fmt, "({k}:{v})")
    }

    pub fn key(&mut self, k: &str) -> std::fmt::Result {
        write!(self.fmt, "({k})")
    }

    pub fn nest<'c>(&'c mut self) -> Body<'c, 'b> {
        Body {
            fmt: self.fmt,
            level: self.level + 1,
            do_close: false,
        }
    }

    fn indent(&mut self) -> std::fmt::Result {
        for i in 0..self.level {
            write!(self.fmt, "  ")?;
        }
        Ok(())
    }
}

impl<'a, 'b> Drop for Body<'a, 'b> {
    fn drop(&mut self) {
        if self.level > 0 {
            if self.do_close {
                write!(self.fmt, "\n");
                self.level -= 1;
                self.indent();
                write!(self.fmt, "}}");
            }
        } else {
            write!(self.fmt, "\n");
        }
    }
}

impl<'a, T> AsNaft<'a, T> {
    pub fn new<'b, TT>(a: &'b TT) -> AsNaft<'b, TT> {
        AsNaft(a)
    }
}

impl<'a, T> std::fmt::Display for AsNaft<'a, T>
where
    T: ToNaft,
{
    fn fmt<'b>(&'b self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut b = Body::new(f);
        self.0.to_naft(&mut b)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct B {}
    impl ToNaft for B {
        fn to_naft(&self, b: &mut Body<'_, '_>) -> std::fmt::Result {
            b.node(&"B")?;
            b.attr("a", &"b")?;
            let b = b.nest();
            Ok(())
        }
    }

    struct A {
        b: B,
    }
    impl ToNaft for A {
        fn to_naft(&self, b: &mut Body<'_, '_>) -> std::fmt::Result {
            b.node(&"A")?;
            b.key("k")?;
            b.attr("k", &"v")?;
            {
                let mut b = b.nest();
                self.b.to_naft(&mut b);
            }
            Ok(())
        }
    }

    #[test]
    fn test_api() {
        let a = A { b: B {} };
        let s = format!("{}", AsNaft::<A>::new(&a));
        println!("{s}rest");
        assert_eq!(&s, "[A](k)(k:v){\n  [B](a:b)\n}\n");
    }
}
