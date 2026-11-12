module hello.std_env_example

import std.env
import std.path

// The executable std.env v1 snapshot example. Its key is set before it is
// read and removed before the absence check, so ambient environment values
// never affect the checksum. Contributions: arguments 1, set 1, get 10,
// remove 100, absence 1, rejected name 1, working directory 1, executable 1,
// and target architecture 1.

fn set_ready(key: String) -> U64 {
    match path.OsString.parse(key) {
        Ok(name) => {
            match path.OsString.parse("ready") {
                Ok(value) => {
                    match env.set_var(name, value) {
                        Ok(_) => { return 1 }
                        Err(_) => { return 0 }
                    }
                }
                Err(_) => { return 0 }
            }
        }
        Err(_) => { return 0 }
    }
    return 0
}

fn get_ready(key: String) -> U64 {
    match path.OsString.parse(key) {
        Ok(name) => {
            match env.get(name) {
                Some(value) => {
                    match value.to_string() {
                        Some(text) => {
                            if text == "ready" { return 10 }
                            return 0
                        }
                        None => { return 0 }
                    }
                }
                None => { return 0 }
            }
        }
        Err(_) => { return 0 }
    }
    return 0
}

fn remove_ready(key: String) -> U64 {
    match path.OsString.parse(key) {
        Ok(name) => {
            match env.remove_var(name) {
                Ok(_) => { return 100 }
                Err(_) => { return 0 }
            }
        }
        Err(_) => { return 0 }
    }
    return 0
}

fn absent_ready(key: String) -> U64 {
    match path.OsString.parse(key) {
        Ok(name) => {
            match env.get(name) {
                Some(_) => { return 0 }
                None => { return 1 }
            }
        }
        Err(_) => { return 0 }
    }
    return 0
}

fn invalid_name() -> U64 {
    match path.OsString.parse("A=B") {
        Ok(name) => {
            match path.OsString.parse("value") {
                Ok(value) => {
                    match env.set_var(name, value) {
                        Ok(_) => { return 0 }
                        Err(_) => { return 1 }
                    }
                }
                Err(_) => { return 0 }
            }
        }
        Err(_) => { return 0 }
    }
    return 0
}

pub fn std_env_example() -> U64 {
    var total: U64 = 0

    // Arguments: entry contract shape, program name present.
    let args = env.arguments()
    if args.len() >= 1 { total = total + 1 }

    total = total + set_ready("ALDER_STD_ENV_EXAMPLE")
    total = total + get_ready("ALDER_STD_ENV_EXAMPLE")
    total = total + remove_ready("ALDER_STD_ENV_EXAMPLE")
    total = total + absent_ready("ALDER_STD_ENV_EXAMPLE")
    total = total + invalid_name()

    // Working directory and executable resolve on every supported target.
    match env.current_dir() {
        Ok(dir) => { if dir.to_os().len() > 0 { total = total + 1 } }
        Err(_) => {}
    }
    match env.current_exe() {
        Ok(exe) => { if exe.to_os().len() > 0 { total = total + 1 } }
        Err(_) => {}
    }

    // Target information is fixed for the build; both arch values contribute
    // the same deterministic unit.
    let target = env.target()
    match target.os {
        Linux => {}
        MacOS => {}
        Windows => {}
    }
    match target.arch {
        X64 => { total = total + 1 }
        AArch64 => { total = total + 1 }
    }

    return total
}
