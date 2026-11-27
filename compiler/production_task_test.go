package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M9 gate 9.4 slice B: the `await` and `Pending(T)` frontend surface and the
// std.task type skeleton.
//
// The accepted program exercises await typing through a generic
// `I: type(Io, AsyncIo)` context, `try await` composition, both direct-call
// shapes (`await binding` and `await spawn(...)`), and the five standard task
// operations. Gate 9.4c has not installed the group record or the executor
// handoff, so every task operation is a fixed-panic placeholder: the typing
// evidence is compile-only (`check` plus `build`, which generate, compile, and
// link the program without running it) and makes no runtime claim. The test
// capability implements the full Io surface with panic bodies and the AsyncIo
// marker so the generic instance can be checked in one compilation unit
// without the hosted Evented capability, which arrives with gate 9.6.
//
// `Cancellation` is real: new/token-free cancel/is_cancelled behavior runs end
// to end under the capability-free path. `CancellationToken` shared state
// needs the source-scoped capability category and the group-owned storage that
// gate 9.4c installs, so the token operations are fixed-panic placeholders.

const taskManifest = "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

func taskProject(body string) map[string]string {
	return map[string]string{
		"alder.toml":  taskManifest,
		"src/main.al": "module hello.main\n\nimport core.panic { panic }\nimport std.io { AsyncIo, ChildStatus, DirEntry, FileMode, FileStat, HostChild, HostDirectory, HostFile, Io, IoError, PollPair, SeekFrom, Timestamp }\nimport std.path { OsString, Path }\nimport std.task { Cancellation, CancellationError, Pending, Task, TaskGroup, blocking, race, timeout }\nimport std.time { Duration }\n\n" + body,
	}
}

// taskTestCapability is a complete Io implementation with panic bodies plus
// the AsyncIo marker. It is the compile-only stand-in for the hosted executor
// capability: every method keeps the trait's exact receiver mode and
// signature, so the trait implementation is validated like any user type.
const taskTestCapability = `type TestCapability {
}

impl Io for TestCapability {
    fn open(self, path: Path, mode: FileMode) -> Result(HostFile, IoError) {
        panic("test capability")
    }
    fn read(self, mut file: HostFile, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        panic("test capability")
    }
    fn write(self, mut file: HostFile, data: [U8]) -> Result(U64, IoError) {
        panic("test capability")
    }
    fn seek(self, mut file: HostFile, from: SeekFrom) -> Result(U64, IoError) {
        panic("test capability")
    }
    fn close(self, take file: HostFile) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn sync(self, mut file: HostFile) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn stat(self, mut file: HostFile) -> Result(FileStat, IoError) {
        panic("test capability")
    }
    fn stat_path(self, path: Path) -> Result(FileStat, IoError) {
        panic("test capability")
    }
    fn lstat(self, path: Path) -> Result(FileStat, IoError) {
        panic("test capability")
    }
    fn set_permissions(self, mut file: HostFile, mode: U32) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn rename(self, from: Path, to: Path) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn remove(self, path: Path) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn remove_directory(self, path: Path) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn make_directory(self, path: Path) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn canonicalize(self, path: Path) -> Result(Path, IoError) {
        panic("test capability")
    }
    fn open_directory(self, path: Path) -> Result(HostDirectory, IoError) {
        panic("test capability")
    }
    fn read_directory(self, mut directory: HostDirectory) -> Result(Option(DirEntry), IoError) {
        panic("test capability")
    }
    fn close_directory(self, take directory: HostDirectory) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn read_stdin(self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        panic("test capability")
    }
    fn write_stdout(self, data: [U8]) -> Result(U64, IoError) {
        panic("test capability")
    }
    fn write_stderr(self, data: [U8]) -> Result(U64, IoError) {
        panic("test capability")
    }
    fn spawn(self, program: OsString, arguments: Vec(OsString), set_environment: Vec(OsString), remove_environment: Vec(OsString), clear_environment: Bool, working_directory: Option(Path), stdin_mode: U8, stdout_mode: U8, stderr_mode: U8) -> Result(HostChild, IoError) {
        panic("test capability")
    }
    fn wait(self, pid: I32) -> Result(ChildStatus, IoError) {
        panic("test capability")
    }
    fn kill(self, pid: I32) -> Result(Unit, IoError) {
        panic("test capability")
    }
    fn poll(self, mut first: HostFile, mut second: HostFile, timeout_ms: I32) -> Result(PollPair, IoError) {
        panic("test capability")
    }
    fn wait_signal(self, signal: I32, timeout_ms: I32) -> Result(Bool, IoError) {
        panic("test capability")
    }
    fn sleep(self, seconds: U64, nanos: U32) -> Unit {
        panic("test capability")
    }
    fn monotonic(self) -> Timestamp {
        panic("test capability")
    }
    fn wallclock(self) -> Timestamp {
        panic("test capability")
    }
    fn random_bytes(self, buffer: MutSlice(U8)) -> Unit {
        panic("test capability")
    }
    fn check_cancel(self) -> Unit {
        panic("test capability")
    }
}

impl AsyncIo for TestCapability {
}

`

const taskTypingBody = `fn count(I: type(Io), io: I, text: String, needle: U8) -> U64 {
    let data = text.to_bytes()
    var hits: U64 = 0
    var at: U64 = 0
    while at < data.len() {
        if data.byte(at) == needle { hits = hits + 1 }
        at = at + 1
    }
    return hits
}

fn note(I: type(Io), io: I) -> Unit {
    return
}

fn counted(I: type(Io), io: I) -> Result(U64, CancellationError) {
    return Ok(11)
}

fn count_pair(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(count(io, "abracadabra", 97))
    let right = tasks.spawn(count(io, "banana", 110))
    tasks.start(note(io))
    let a = await left
    let b = await right
    return a * 100 + b
}

fn composed(I: type(Io, AsyncIo), io: I) -> Result(U64, CancellationError) {
    using tasks = TaskGroup.new(io)
    let handle = tasks.spawn(counted(io))
    let value = try await handle
    return Ok(value)
}

fn timed(I: type(Io, AsyncIo), io: I) -> U64 {
    let outcome = match timeout(io, Duration.seconds(5), count(io, "aaaa", 97)) {
        Ok(value) => value
        Err(_) => 0
    }
    return outcome
}

fn raced(I: type(Io, AsyncIo), io: I) -> U64 {
    return race(io, count(io, "aa", 97), count(io, "bbb", 98))
}

fn inline_await(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    return await tasks.spawn(count(io, "zz", 122))
}

fn blocked(io: TestCapability) -> U64 {
    return blocking(io, count(io, "zz", 122))
}

fn mint_token(io: TestCapability) -> Unit {
    using cancel = Cancellation.new()
    let token = cancel.token()
    return
}

fn market() -> I32 {
    using first = Cancellation.new()
    using second = Cancellation.new()
    if first.is_cancelled() { return 1 }
    if second.is_cancelled() { return 2 }
    first.cancel()
    if !first.is_cancelled() { return 3 }
    if second.is_cancelled() { return 4 }
    return 0
}

fn typed(io: TestCapability) -> U64 {
    let a = count_pair(io)
    let b = timed(io)
    let c = raced(io)
    let d = inline_await(io)
    let e = blocked(io)
    mint_token(io)
    return a + b + c + d + e
}

pub fn main() -> I32 {
    let cap = TestCapability()
    let checked = typed(cap)
    return market()
}
`

// TestTaskAwaitPendingTypingProduction checks the accepted frontend surface
// without running a task: `check` covers typing, lowering, and the complete
// MIR verifier, and `build` generates C11 for the same program, compiles it
// under the production flag set, and links it. Running would reach the fixed
// panic that stands in for the gate 9.4c task runtime.
func TestTaskAwaitPendingTypingProduction(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	files := taskProject(taskTestCapability + taskTypingBody)
	check := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "check")
	if check.status != 0 || check.stdout != "" || check.stderr != "" {
		t.Fatalf("await/Pending typing: %+v", check)
	}
	build := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "build")
	if build.status != 0 || build.stderr != "" {
		t.Fatalf("await/Pending build: %+v", build)
	}
}

// TestTaskCancellationProductionBehavior runs the completed half of the
// cancellation pair. The token half is a fixed panic until gate 9.4c, so only
// the source-side state machine is a runtime claim.
func TestTaskCancellationProductionBehavior(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	files := taskProject(`fn probe() -> I32 {
    using first = Cancellation.new()
    using second = Cancellation.new()
    if first.is_cancelled() { return 1 }
    if second.is_cancelled() { return 2 }
    first.cancel()
    if !first.is_cancelled() { return 3 }
    if second.is_cancelled() { return 4 }
    second.cancel()
    if !second.is_cancelled() { return 5 }
    if !first.is_cancelled() { return 6 }
    return 0
}

pub fn main() -> I32 {
    return probe()
}
`)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stdout != "" || result.stderr != "" {
		t.Fatalf("cancellation behavior: %+v", result)
	}
}

type taskRejectionCase struct {
	name    string
	body    string
	code    string
	message string
}

func taskRejectionCases() []taskRejectionCase {
	return []taskRejectionCase{
		{
			name: "await-non-task",
			body: `fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let n = 5
    return await n
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "await requires a std.task Task(T) handle, not I64",
		},
		{
			name: "await-user-nominal",
			body: `type FakeTask(T: type) {
    value: T
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let fake = FakeTask(value: 5)
    return await fake
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "await requires a std.task Task(T) handle, not FakeTask",
		},
		{
			name: "await-outside-group",
			body: `fn rejected(task: Task(U64)) -> U64 {
    return await task
}

pub fn main() -> I32 {
    return 0
}
`,
			code:    "SEM0001",
			message: "await is only allowed inside the using scope of a std.task TaskGroup",
		},
		{
			name: "await-stored-handle",
			body: `type Holder {
    task: Task(U64)
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let holder = Holder(task: tasks.spawn(count(io, "a", 97)))
    return await holder.task
}

fn count(I: type(Io), io: I, text: String, needle: U8) -> U64 {
    return 1
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "await requires a direct Task binding or a fresh std.task operation result",
		},
		{
			name: "await-consumed-handle",
			body: `fn count(I: type(Io), io: I) -> U64 {
    return 1
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(count(io))
    let a = await left
    let b = await left
    return a + b
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "owner was already transferred",
		},
		{
			name: "dropped-handle",
			body: `fn count(I: type(Io), io: I) -> U64 {
    return 1
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(count(io))
    return 5
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "affine owner reaches function exit without an ownership transfer",
		},
		{
			name: "try-non-result-await",
			body: `fn count(I: type(Io), io: I) -> U64 {
    return 1
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(count(io))
    return try await left
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "try requires a function returning Result",
		},
		{
			name: "await-in-function-value",
			body: `fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    let later = fn(task: Task(U64)) -> U64 { return await task }
    return 0
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "await is only allowed inside the using scope of a std.task TaskGroup",
		},
		{
			name: "await-method-form",
			body: `fn count(I: type(Io), io: I) -> U64 {
    return 1
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(count(io))
    return left.await()
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SYN0001",
			message: "expected identifier",
		},
		{
			name: "pending-field",
			body: `type Holder {
    pending: Pending(U64)
}

pub fn main() -> I32 {
    return 0
}
`,
			code:    "SEM0001",
			message: "Pending(T) is only a parameter type of the std.task spawn, start, timeout, race, and blocking operations",
		},
		{
			name: "pending-function-parameter",
			body: `fn rejected(pending: Pending(U64)) -> Unit {
    return
}

pub fn main() -> I32 {
    return 0
}
`,
			code:    "SEM0001",
			message: "Pending(T) is only a parameter type of the std.task spawn, start, timeout, race, and blocking operations",
		},
		{
			name: "pending-function-result",
			body: `fn rejected() -> Pending(U64) {
    panic("no value")
}

pub fn main() -> I32 {
    return 0
}
`,
			code:    "SEM0001",
			message: "Pending(T) is only a parameter type of the std.task spawn, start, timeout, race, and blocking operations",
		},
		{
			name:    "pending-deep-declaration",
			body:    "fn rejected(deep: " + nestedOptionType(33, "Pending(U64)") + ") -> Unit {\n    return\n}\n\npub fn main() -> I32 {\n    return 0\n}\n",
			code:    "SEM0001",
			message: "Pending(T) is only a parameter type of the std.task spawn, start, timeout, race, and blocking operations",
		},
		{
			name: "pending-not-a-call",
			body: `fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let handle = tasks.spawn(5)
    return await handle
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "a Pending(T) argument must be a direct call to a named function or method",
		},
		{
			name: "pending-call-not-named",
			body: `type Holder {
    value: U64
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let handle = tasks.spawn(Holder(value: 1))
    return await handle
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "a Pending(T) argument must call a named function or method, not a constructor, variant, closure, function value, or C import",
		},
		{
			name: "race-result-mismatch",
			body: `fn count(I: type(Io), io: I) -> U64 {
    return 1
}

fn note(I: type(Io), io: I) -> Unit {
    return
}

fn rejected(I: type(Io, AsyncIo), io: I) -> U64 {
    return race(io, count(io), note(io))
}

pub fn main() -> I32 {
    let cap = TestCapability()
    return rejected(cap).to_i32_wrapping()
}
`,
			code:    "SEM0001",
			message: "the Pending(T) arguments do not share one result type",
		},
	}
}

func TestTaskAwaitPendingRejections(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	cases := taskRejectionCases()
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			files := taskProject(taskTestCapability + tc.body)
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "check")
			if result.status != 1 || result.stdout != "" {
				t.Fatalf("%s: expected one diagnostic, got %+v", tc.name, result)
			}
			if !strings.Contains(result.stderr, tc.code) || !strings.Contains(result.stderr, tc.message) {
				t.Fatalf("%s: stderr %q does not carry %s %q", tc.name, result.stderr, tc.code, tc.message)
			}
		})
	}
}

// TestTaskSysrootSurface keeps the installed module's public shape pinned:
// the v1 snapshot's types and signatures are present with their spellings,
// and no implementation detail leaks a C ABI type onto the public surface.
func TestTaskSysrootSurface(t *testing.T) {
	t.Parallel()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	text, err := os.ReadFile(filepath.Join(root, "sysroot", "std", "task.al"))
	if err != nil {
		t.Fatal(err)
	}
	source := string(text)
	required := []string{
		"pub type TaskGroup(I: type(Io, AsyncIo))",
		"pub type Task(T: type)",
		"pub type Pending(T: type)",
		"pub enum Timeout {",
		"pub enum CancellationError {",
		"pub type Cancellation {",
		"pub type CancellationToken {",
		"fn new(io: I) -> TaskGroup(I)",
		"fn spawn(T: type, mut self, pending: Pending(T)) -> Task(T)",
		"fn start(mut self, pending: Pending(Unit)) -> Unit",
		"fn new() -> Cancellation",
		"fn token(self) -> CancellationToken",
		"fn cancel(mut self) -> Unit",
		"fn is_cancelled(self) -> Bool",
		"fn check(self) -> Result(Unit, CancellationError)",
		"pub fn timeout(T: type, I: type(Io, AsyncIo), io: I, duration: Duration, pending: Pending(T)) -> Result(T, Timeout)",
		"pub fn race(T: type, I: type(Io, AsyncIo), io: I, first: Pending(T), second: Pending(T)) -> T",
		"pub fn blocking(T: type, I: type(Io), io: I, pending: Pending(T)) -> T",
		"pub fn yield(I: type(Io, AsyncIo), io: I) -> Unit",
	}
	for _, want := range required {
		if !strings.Contains(source, want) {
			t.Errorf("std/task.al is missing %q", want)
		}
	}
}

// TestTaskDeepUnderCapTypeProduction pins the other side of the depth cap: a
// deeply nested type that stays under the limit and mentions no Pending is an
// ordinary accepted type, so the conservative cap does not reject deep
// declarations wholesale.
func TestTaskDeepUnderCapTypeProduction(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	deep := nestedOptionType(16, "U64")
	body := "fn accepts(deep: " + deep + ") -> U64 {\n    return 0\n}\n\npub fn main() -> I32 {\n    return 0\n}\n"
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, taskProject(body), "check")
	if result.status != 0 || result.stdout != "" || result.stderr != "" {
		t.Fatalf("deep under-cap type: %+v", result)
	}
}
