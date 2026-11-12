/*
 * Toolchain-owned C binding shim for std.env.
 *
 * getenv returns a pointer into the C library's environment storage, which no
 * binding block can name as an owned value. The helper copies the value into
 * a caller-owned buffer and reports the length, -1 when the name is unset,
 * and -2 when the buffer is too small. The Alder side retries with a larger
 * buffer and never retains the host pointer.
 */
#ifndef ENV_SHIM_H
#define ENV_SHIM_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

static inline int env_get(const char *name, unsigned char *out, size_t capacity) {
    const char *value = getenv(name);
    size_t length;
    if (value == NULL) { return -1; }
    length = strlen(value);
    if (length > capacity) { return -2; }
    if (length != 0) { memcpy(out, value, length); }
    return (int)length;
}

#endif /* ENV_SHIM_H */
