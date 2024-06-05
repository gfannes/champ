pub type ErrorType = Box<dyn std::error::Error + 'static>;
pub type Result<T> = std::result::Result<T, ErrorType>;

#[derive(Debug)]
pub struct Error {
    descr: String,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[Error](descr:{})", &self.descr)?;
        Ok(())
    }
}
impl std::error::Error for Error {}

impl Error {
    pub fn create(descr: impl Into<String>) -> ErrorType {
        Box::new(Error {
            descr: descr.into(),
        })
    }
}

macro_rules! fail {
    ($fmt:expr) => {
        return Err(util::Error::create(&format!($fmt)))
    };
    ($fmt:expr, $($arg:expr),*) => {
        return Err(my::Error::create(&format!($fmt, $($arg),*)))
    };
    ($fmt:expr, $($arg:expr),+ ,) => {
        fail!($fmt, $($arg),*)
    };
}
