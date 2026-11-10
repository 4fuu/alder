/*
 * Toolchain-owned C binding shims for hosted standard-library wrappers.
 *
 * These helpers exist because the operations they expose cannot be named
 * by a raw fn binding against real headers: errno is a thread-local
 * modifiable lvalue (usually a macro), so no binding block can read it,
 * and strerror belongs to the same hosted-OS surface. The declarations
 * here are the audit trail: the runtime owns these two symbols, binding
 * blocks may bind only them from this header, and the generated
 * _Static_assert probes pin the signatures against this declaration.
 *
 * Portable C11. The names stay outside the alder_ runtime prefix so a
 * binding block can name them under the spelling policy.
 */
#ifndef ALDER_ERRNO_H
#define ALDER_ERRNO_H

#ifdef __cplusplus
extern "C" {
#endif

/* The calling thread's errno value at the moment of the call. */
int c_errno(void);

/* The C locale message for the errno value; the storage is owned by the
 * C library and stays valid until the next call in the same thread. */
const char *c_strerror(int number);

#ifdef __cplusplus
}
#endif

#endif /* ALDER_ERRNO_H */
