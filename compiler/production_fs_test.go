package compiler

import "testing"

// std.fs value layer: open options and portable permissions are pure records,
// so the whole snapshot subset can be checked without host handles.
func sysrootFsValueMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.fs

fn main() -> I32 {
    let read = fs.Options.read()
    if !read.read || read.write || read.append || read.truncate || read.create || read.create_new { return 1 }
    let write = fs.Options.write()
    if write.read || !write.write || write.append || !write.truncate || !write.create || write.create_new { return 2 }

    var adjusted = read
    adjusted.append = true
    adjusted.create_new = true
    if !adjusted.append || !adjusted.create_new { return 3 }
    if read.append || read.create_new { return 4 }

    let permissions = fs.Permissions(readable: true, writable: false, executable: true)
    if !permissions.readable || permissions.writable || !permissions.executable { return 5 }
    var changed = permissions
    changed.writable = true
    if !changed.writable { return 6 }
    if permissions.writable { return 7 }
    return 0
}
`,
	}
}

func TestSysrootFsValueLayer(t *testing.T) {
	testSysrootValueModule(t, sysrootFsValueMain())
}
