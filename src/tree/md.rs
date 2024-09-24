use crate::strange;

type Range = std::ops::Range<usize>;

#[derive(Default, PartialEq, Eq, Debug)]
struct Line {
    all: Range,
    main: Range,
}
type Lines = Vec<Line>;
impl Line {
    pub fn new(all: Range, main: Range) -> Line {
        Line { all, main }
    }
}

fn split_lines(str: &str) -> Lines {
    let mut lines = Vec::new();

    let mut strange = strange::Strange::new(str);

    while !strange.is_empty() {
        strange.save();
        strange.read(|r| r.exclude().to_end().until('\n'));
        let mut main = strange.pop_range();
        let all = main.start..main.end + strange.read_char_if('\n') as usize;

        let mut strange = strange::Strange::new(str.get(main.clone()).unwrap());
        while strange.read_char_when(|ch| " \t#-*$`".contains(ch)) {
            main.start += 1;
        }
        lines.push(Line { all, main });
    }

    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_lines() {
        let scns = [
            ("\n", vec![Line::new(0..1, 0..0)]),
            ("\n\n", vec![Line::new(0..1, 0..0), Line::new(1..2, 1..1)]),
            ("Line", vec![Line::new(0..4, 0..4)]),
            (" Space", vec![Line::new(0..6, 1..6)]),
            ("# Title", vec![Line::new(0..7, 2..7)]),
            (
                "# Title\nLine",
                vec![Line::new(0..8, 2..7), Line::new(8..12, 8..12)],
            ),
        ];

        for (scn, exp) in scns {
            let lines = split_lines(scn);
            assert_eq!(lines, exp);
        }
    }
}
