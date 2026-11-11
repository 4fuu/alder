/*
 * Toolchain-owned C binding shim for the core panic surface.
 *
 * `core.panic` cannot bind the runtime's `alder_runtime_panic` directly:
 * binding names beginning with `alder_` are reserved for generated code and
 * the runtime, and the invariant runtime path prints a backtrace rather than
 * a user panic message. This shim is the audited boundary for user panics.
 * It flushes every C output stream, writes the message to stderr, and aborts;
 * Alder cleanup scopes do not run.
 *
 * The message must be a valid NUL-terminated C string. It is deliberately
 * passed as a plain pointer because the current binding surface has no
 * pointer-plus-length argument. Once that surface lands, this shim can use a
 * byte pointer and length without changing the Alder API.
 */
#ifndef ALDER_PANIC_H
#define ALDER_PANIC_H

#include <stdio.h>
#include <stdlib.h>

#if defined(__GNUC__) || defined(__clang__)
#define ALDER_PANIC_UNUSED __attribute__((unused))
#else
#define ALDER_PANIC_UNUSED
#endif

#ifdef __cplusplus
extern "C" {
#endif

static inline _Noreturn ALDER_PANIC_UNUSED void c_panic(const char *message) {
    if (message == NULL) {
        message = "(null)";
    }
    (void)fflush(NULL);
    fputs("panic: ", stderr);
    fputs(message, stderr);
    fputc('\n', stderr);
    (void)fflush(stderr);
    abort();
}

#ifdef __cplusplus
}
#endif

#endif /* ALDER_PANIC_H */
