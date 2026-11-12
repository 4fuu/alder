package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Foreign-thread entry: each export call creates an independent root domain,
// so concurrent calls exercise the runtime's atomic domain/segment serial and
// allocation counters without entering the hosted program entry.
const cExportThreadProgram = `export c fn storage_len() -> c.ULongLong {
    let text = "ab".concat("cd")
    return text.len().to_c_ulonglong()
}
`

const cExportThreadDriver = `#include "exports.h"
#include <pthread.h>
#include <stdint.h>

#define THREADS 8
#define CALLS 500

static void *worker(void *arg) {
    (void)arg;
    int i;
    for (i = 0; i < CALLS; i++) {
        if (storage_len() != 4) { return (void *)(uintptr_t)1; }
    }
    return NULL;
}

int main(void) {
    pthread_t threads[THREADS];
    int i;
    for (i = 0; i < THREADS; i++) {
        if (pthread_create(&threads[i], NULL, worker, NULL) != 0) { return 1; }
    }
    for (i = 0; i < THREADS; i++) {
        void *result = NULL;
        if (pthread_join(threads[i], &result) != 0 || result != NULL) { return 2; }
    }
    return 0;
}
`

func TestM8CExportForeignThreads(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)

	dir := t.TempDir()
	files := map[string]string{"thread.al": cExportThreadProgram}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "thread.al")
	if emitted.status != 0 || emitted.stderr != "" {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	header := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=header", "thread.al")
	if header.status != 0 || header.stderr != "" {
		t.Fatalf("emit=header result: %+v stderr=%s", header, header.stderr)
	}
	if err := os.WriteFile(filepath.Join(dir, "exports.h"), []byte(header.stdout), 0o644); err != nil {
		t.Fatal(err)
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cExportThreadDriver, 0,
		"-I", dir, "-pthread")
}

// Retained callbacks from a foreign thread are supported when the bound C
// wait function is a real barrier. The worker calls the trampoline until
// clear stops it; wait joins before the owner frees the copied context.
const cCallbackOwnerThreadProgram = `import c "ownerthread.h" as ev {
    callback type Handler = "ownerthread_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int

    raw fn set = "ownerthread_set"(handler: Handler, context: c.Ptr(c.UChar)) -> c.Int
    raw fn clear = "ownerthread_clear"(context: c.Ptr(c.UChar)) -> c.Int
    raw fn wait = "ownerthread_wait"(context: c.Ptr(c.UChar)) -> Unit
    raw fn fire = "ownerthread_fire"() -> c.Int
}

fn handle_event(event: c.ConstPtr(c.UChar), length: c.Size, context: c.Ptr(c.UChar)) -> c.Int {
    unsafe c { c.store(context, c.Zero(c.UChar)) }
    return c.Zero(c.Int)
}

fn consume(T: type, take owner: T) -> Unit {
    using held = owner
    let status = unsafe c { ev.fire() }
    return
}

fn main() -> I32 {
    var state: c.UChar = c.Zero(c.UChar)
    let registered = unsafe c { c.CallbackOwner.register(ev.set, ev.clear, ev.wait, handle_event, state) }
    using owner = match registered {
        Some(value) => value
        None => return 1
    }
    consume(owner)
    return 0
}
`

const cCallbackOwnerThreadHeader = `#ifndef OWNERTHREAD_H
#define OWNERTHREAD_H
#include <stddef.h>
typedef int (*ownerthread_handler)(const unsigned char *event, size_t length, unsigned char *context);
int ownerthread_set(ownerthread_handler handler, unsigned char *context);
int ownerthread_clear(unsigned char *context);
void ownerthread_wait(unsigned char *context);
int ownerthread_fire(void);
#endif
`

const cCallbackOwnerThreadDriver = `#include "alder_host.h"
#include "ownerthread.h"
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>

static ownerthread_handler saved_handler;
static unsigned char *saved_context;
static pthread_t worker;
static atomic_int stop_flag;
static atomic_int failed;
static atomic_int callback_count;
static int clear_count;
static int wait_count;
static int started;

static void *worker_main(void *arg) {
    (void)arg;
    while (!atomic_load_explicit(&stop_flag, memory_order_acquire)) {
        unsigned char event = 'A';
        if (saved_handler == NULL || saved_context == NULL ||
            saved_handler(&event, 1, saved_context) != 0) {
            atomic_store_explicit(&failed, 1, memory_order_relaxed);
            break;
        }
        (void)atomic_fetch_add_explicit(&callback_count, 1, memory_order_relaxed);
        sched_yield();
    }
    return NULL;
}

int ownerthread_set(ownerthread_handler handler, unsigned char *context) {
    saved_handler = handler;
    saved_context = context;
    atomic_store_explicit(&stop_flag, 0, memory_order_relaxed);
    if (pthread_create(&worker, NULL, worker_main, NULL) != 0) { return 1; }
    started = 1;
    return 0;
}

int ownerthread_clear(unsigned char *context) {
    (void)context;
    atomic_store_explicit(&stop_flag, 1, memory_order_release);
    clear_count += 1;
    return 0;
}

void ownerthread_wait(unsigned char *context) {
    (void)context;
    if (started) {
        (void)pthread_join(worker, NULL);
        started = 0;
    }
    wait_count += 1;
}

int ownerthread_fire(void) {
    int i;
    for (i = 0; i < 100000 && atomic_load_explicit(&callback_count, memory_order_relaxed) == 0; i++) {
        sched_yield();
    }
    return atomic_load_explicit(&failed, memory_order_relaxed) != 0 ? 2 : 0;
}

int main(void) {
    int context = 0;
    if (alder_program_entry(&context) != 0) { return 10; }
    if (clear_count != 1 || wait_count != 1) { return 11; }
    if (atomic_load_explicit(&callback_count, memory_order_relaxed) == 0) { return 12; }
    if (atomic_load_explicit(&failed, memory_order_relaxed) != 0) { return 13; }
    return 0;
}
`

func TestM8CCallbackOwnerForeignThread(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)

	dir := t.TempDir()
	files := map[string]string{
		"ownerthread.al": cCallbackOwnerThreadProgram,
		"ownerthread.h":  cCallbackOwnerThreadHeader,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "ownerthread.al")
	if emitted.status != 0 || emitted.stderr != "" {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	for _, want := range []string{"alder_callback_owner_new", "ownerthread_clear(context) != 0", "ownerthread_wait(context)"} {
		if !strings.Contains(emitted.stdout, want) {
			t.Fatalf("generated owner C misses %q", want)
		}
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cCallbackOwnerThreadDriver, 0,
		"-I", dir, "-pthread")
}
