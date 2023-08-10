mod fs;

use std::ffi;

// A filesystem tree
pub struct Root {
    folders: Vec<Folder>,
    files: Vec<File>,
}

impl Root {
    pub fn new() -> Root {
        Root {
            folders: Vec::new(),
            files: Vec::new(),
        }
    }
}

struct Folder {
    name: ffi::OsString,
    folders: Vec<Folder>,
    files: Vec<File>,
}

struct File {
    name: ffi::OsString,
    content: Option<ffi::OsString>,
    ranges: Vec<Range>,
    checksum: Option<Vec<u8>>,
}

#[derive(Clone)]
struct Range {
    begin: usize,
    size: usize,
}

// Index into a Root
#[derive(Clone)]
struct Path {
    names: Vec<ffi::OsString>,
    range: Option<Range>,
}
