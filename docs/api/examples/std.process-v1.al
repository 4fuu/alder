module hello.std_process_example

import std.io { Blocking }
import std.path { OsString }
import std.process { Command, Output, ProcessError }

// The executable std.process v1 snapshot example. One fixed program with
// fixed arguments and piped capture; the checksum is deterministic.

fn os_value(value: String) -> Option(OsString) {
    match OsString.parse(value) {
        Ok(text) => { return Some(text) }
        Err(_) => { return None }
    }
    return None
}

fn bytes_are(left: Bytes, right: String) -> Bool {
    return left == right.to_bytes()
}

// The example inputs are fixed, so any early failure produces a
// distinctive negative checksum.
pub fn std_process_example(io: Blocking) -> I64 {
    var total: I64 = 0

    let program = match os_value("/bin/echo") {
        Some(value) => value
        None => return -1000000
    }
    let message = match os_value("alder") {
        Some(value) => value
        None => return -1000000
    }
    var command = Command.new(program)
    command.argument(message)
    command.stdout(Piped)
    command.stderr(Piped)
    let result = match command.output(io) {
        Ok(value) => value
        Err(_) => return -1000000
    }
    if result.status.success() { total = total + 1 }
    if bytes_are(result.stdout, "alder\n") { total = total + 10 }

    let scripted = match os_value("/bin/echo") {
        Some(value) => value
        None => return -1000000
    }
    let key = match os_value("ALDER_STD_PROCESS_EXAMPLE") {
        Some(value) => value
        None => return -1000000
    }
    let flag = match os_value("1") {
        Some(value) => value
        None => return -1000000
    }
    var second_command = Command.new(scripted)
    second_command.argument(message)
    second_command.env(key, flag)
    second_command.stdout(Piped)
    second_command.stderr(Piped)
    let second = match second_command.output(io) {
        Ok(value) => value
        Err(_) => return -1000000
    }
    if second.status.success() { total = total + 100 }
    if second.stderr.len() == 0 { total = total + 1 }

    let missing = match os_value("/alder/does/not/exist") {
        Some(value) => value
        None => return -1000000
    }
    let gone = Command.new(missing)
    match gone.status(io) {
        Ok(_) => { total = total - 100000 }
        Err(_) => { total = total + 1000 }
    }

    return total
}
