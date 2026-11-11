/*
 * Toolchain-owned C shim for the program-entry error diagnostic.
 *
 * `core.error` uses this audited boundary to write the already formatted
 * `program error:` text to standard error. It is a best-effort write followed
 * by a flush; the caller returns status 1 normally, so no process-termination
 * path or cleanup suppression is involved.
 */
#ifndef ALDER_ENTRY_H
#define ALDER_ENTRY_H

#include <stdio.h>

#if defined(__GNUC__) || defined(__clang__)
#define ALDER_ENTRY_UNUSED __attribute__((unused))
#else
#define ALDER_ENTRY_UNUSED
#endif

#ifdef __cplusplus
extern "C" {
#endif

static inline ALDER_ENTRY_UNUSED void c_program_error(const char *text) {
    if (text == NULL) {
        text = "(null)";
    }
    (void)fputs(text, stderr);
    (void)fputc('\n', stderr);
    (void)fflush(stderr);
}

#ifdef __cplusplus
}
#endif

#endif /* ALDER_ENTRY_H */
