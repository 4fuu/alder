/*
 * Toolchain-owned C binding shims for hosted standard-library wrappers.
 *
 * These helpers exist because the operations they expose cannot be named
 * by a raw fn binding against real headers: errno is a thread-local
 * modifiable lvalue (usually a macro), so no binding block can read it,
 * and strerror belongs to the same hosted-OS surface. The definitions
 * here are the audit trail: the runtime owns this surface, binding blocks
 * may bind only these two functions from this header, and the generated
 * _Static_assert probes pin the signatures against these definitions.
 *
 * Both functions are static inline, so including this header never adds
 * an exported symbol to a program and a user C library cannot collide
 * with them at link time. Every translation unit gets its own copy.
 *
 * Portable C11. The names stay outside the alder_ runtime prefix so a
 * binding block can name them under the spelling policy.
 */
#ifndef ALDER_ERRNO_H
#define ALDER_ERRNO_H

#include <errno.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The calling thread's errno value at the moment of the call. */
static inline int c_errno(void) {
    return errno;
}

/* The C locale message for the errno value; the storage is owned by the
 * C library and stays valid until the next call in the same thread. */
static inline const char *c_strerror(int number) {
    return strerror(number);
}

#ifdef __cplusplus
}
#endif

#endif /* ALDER_ERRNO_H */
