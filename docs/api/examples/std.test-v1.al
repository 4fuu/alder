module hello.std_test_example

import std.io { Blocking }
import std.test

// The executable std.test v1 snapshot example. Every check is total; the
// failure paths are covered by subprocess tests because they terminate the
// process. Temporary owners are left to their cleanup at the end of the
// function and contribute only presence checks, never host-dependent paths.

pub fn std_test_example() -> U64 {
    var total: U64 = 0

    // Assertions return normally when they pass.
    test.assert(true, "never printed")
    test.assert_eq(U64, 7, 7)
    test.assert_ne(String, "alder", "aster")
    total = total + 1

    // Expected-result helpers return the payload they name.
    let good: Result(U64, String) = Ok(41)
    total = total + test.expect_ok(U64, String, good)
    let bad: Result(U64, String) = Err("boom")
    let why = test.expect_err(U64, String, bad)
    if why == "boom" { total = total + 1 }

    // Seeded cases are deterministic and carry their position.
    let case_list = test.cases(4, 7)
    if case_list.len() == 4 { total = total + 1 }
    var at: U64 = 0
    while at < 4 {
        match case_list.get(at) {
            Some(item) => {
                if item.index == at { total = total + 1 }
            }
            None => {}
        }
        at = at + 1
    }

    // Temporary owners exist and clean up at scope end.
    let cap = Blocking()
    using temporary_file = test.temp_file(cap, "alder-std-test")
    if temporary_file.path().to_os().to_bytes().len() > 0 { total = total + 1 }
    using temporary_dir = test.temp_dir(cap, "alder-std-test")
    if temporary_dir.path().to_os().to_bytes().len() > 0 { total = total + 1 }

    return total
}
