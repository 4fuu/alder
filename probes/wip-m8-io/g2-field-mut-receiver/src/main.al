module hello.main

enum IoError {
    NotFound
}

trait Reader {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError)
}

type Source {
    data: Array(U8, 3)
    at: U64
}

impl Reader for Source {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        if self.at >= self.data.len() { return Ok(0) }
        let rest = self.data.len() - self.at
        let want = buffer.len()
        var n: U64 = want
        if n > rest { n = rest }
        var at: U64 = 0
        while at < n {
            buffer[at] = self.data[self.at + at]
            at = at + 1
        }
        self.at = self.at + n
        return Ok(n)
    }
}

type Wrapper {
    inner: Source
}

impl Reader for Wrapper {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.inner.read(buffer)
    }
}

fn main() -> I32 {
    let w = Wrapper(inner: Source(data: [1, 2, 3], at: 0))
    var data: Array(U8, 4) = [0, 0, 0, 0]
    var view: MutSlice(U8) = data.slice_mut(0, 4)
    let got = match w.read(view) {
        Ok(n) => n
        Err(_) => 99
    }
    if got != 3 { return 1 }
    return 0
}
