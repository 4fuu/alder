module hello.main

import hello.io1 { Greeter, Token, hello }

fn main() -> I32 {
    let t = Token(id: 7)
    if hello(Token, t) != 7 { return 1 }
    if t.greet() != 7 { return 2 }
    return 0
}
