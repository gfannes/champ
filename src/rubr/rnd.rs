use std::fmt;

struct Body<'a, 'b> {
    fmt: &'a mut fmt::Formatter<'b>,
    level: usize,
    do_close: bool,
}

impl<'a, 'b> Body<'a, 'b> {
    fn new<'c>(fmt: &'c mut fmt::Formatter<'b>) -> Body<'c, 'b> {
        Body {
            fmt,
            level: 0,
            do_close: false,
        }
    }

    fn node<T>(&mut self, v: &T) -> fmt::Result
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

    fn attr<T>(&mut self, k: &str, v: &T) -> fmt::Result
    where
        T: std::fmt::Display,
    {
        write!(self.fmt, "({k}:{v})")
    }

    fn key(&mut self, k: &str) -> fmt::Result {
        write!(self.fmt, "({k})")
    }

    fn nest<'c>(&'c mut self) -> Body<'c, 'b> {
        Body {
            fmt: self.fmt,
            level: self.level + 1,
            do_close: false,
        }
    }

    fn indent(&mut self) -> fmt::Result {
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

trait ToNaft {
    fn to_naft(&self, w: &mut Body<'_, '_>) -> fmt::Result;
}

struct AsNaft<'a, T>(&'a T);

impl<'a, T> AsNaft<'a, T> {
    fn new<'b, TT>(a: &'b TT) -> AsNaft<'b, TT> {
        AsNaft(a)
    }
}

impl<'a, T> std::fmt::Display for AsNaft<'a, T>
where
    T: ToNaft,
{
    fn fmt<'b>(&'b self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut w = Body::new(f);
        self.0.to_naft(&mut w)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct B {}
    impl ToNaft for B {
        fn to_naft(&self, w: &mut Body<'_, '_>) -> fmt::Result {
            w.node(&"B")?;
            w.attr("a", &"b")?;
            let b = w.nest();
            Ok(())
        }
    }

    struct A {
        b: B,
    }
    impl ToNaft for A {
        fn to_naft(&self, w: &mut Body<'_, '_>) -> fmt::Result {
            w.node(&"A")?;
            w.key("k")?;
            w.attr("k", &"v")?;
            {
                let mut b = w.nest();
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
