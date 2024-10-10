pub struct Counter {
    n: Option<u64>,
}

impl Counter {
    pub fn new(n: Option<u64>) -> Counter {
        Counter { n }
    }

    pub fn call(&mut self) -> bool {
        if let Some(n) = &mut self.n {
            if *n > 0 {
                *n -= 1;
                true
            } else {
                false
            }
        } else {
            true
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_counter_without_end() {
        let mut counter = Counter::new(None);
        assert!(counter.call());
        assert!(counter.call());
        assert!(counter.call());
        assert!(counter.call());
    }

    #[test]
    fn test_counter_with_end() {
        let scns = [0, 1, 100];
        for n in scns {
            let mut counter = Counter::new(Some(n));
            for _ in 0..n {
                assert!(counter.call());
            }
            assert!(!counter.call());
            assert!(!counter.call());
        }
    }
}
