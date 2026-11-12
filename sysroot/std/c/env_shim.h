/*
 * Toolchain-owned C binding shim for std.env.
 *
 * getenv returns a pointer into the C library's environment storage, which no
 * binding block can name as an owned value. The helper copies the value into
 * a caller-owned buffer and reports the length, -1 when the name is unset,
 * and -2 when the buffer is too small. The Alder side retries with a larger
 * buffer and never retains the host pointer.
 *
 * The remaining helpers observe or update process-global state. Arguments
 * come from the hosted-entry setter in alder.c: the driver installs argv once
 * before Alder code runs, and every accessor copies bytes out. The host
 * environment is single-threaded by contract; set_var/remove_var and
 * set_current_dir are process-global operations whose callers must not race
 * with other observers.
 */
#ifndef ENV_SHIM_H
#define ENV_SHIM_H

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#include <process.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

extern int alder_host_arg_count(void);
extern const char *alder_host_arg(int index);

static inline int env_get(const char *name, unsigned char *out, size_t capacity) {
    const char *value = getenv(name);
    size_t length;
    if (value == NULL) { return -1; }
    length = strlen(value);
    if (length > capacity) { return -2; }
    if (length != 0) { memcpy(out, value, length); }
    return (int)length;
}

static inline int env_arg_count(void) {
    return alder_host_arg_count();
}

static inline long long env_arg_length(int index) {
    const char *value = alder_host_arg(index);
    size_t length;
    if (value == NULL) { return -1; }
    length = strlen(value);
    if (length > (size_t)INT64_MAX) { return -1; }
    return (long long)length;
}

static inline int env_arg_byte(int index, unsigned long long offset) {
    const char *value = alder_host_arg(index);
    size_t length;
    if (value == NULL) { return -1; }
    length = strlen(value);
    if (offset >= (unsigned long long)length) { return -1; }
    return (int)(unsigned char)value[(size_t)offset];
}

static inline long long env_current_exe(unsigned char *out, size_t capacity) {
    if (out == NULL || capacity == 0) {
        errno = EINVAL;
        return -1;
    }
#if defined(_WIN32)
    {
        DWORD length;
        if (capacity > (size_t)UINT32_MAX) {
            errno = ERANGE;
            return -1;
        }
        length = GetModuleFileNameA(NULL, (char *)out, (DWORD)capacity);
        if (length == 0 || (size_t)length >= capacity) {
            errno = ERANGE;
            return -1;
        }
        return (long long)length;
    }
#elif defined(__APPLE__)
    {
        char buffer[4096];
        uint32_t size = (uint32_t)sizeof(buffer);
        char *resolved;
        size_t length;
        if (_NSGetExecutablePath(buffer, &size) != 0) {
            errno = ERANGE;
            return -1;
        }
        resolved = realpath(buffer, NULL);
        if (resolved == NULL) { return -1; }
        length = strlen(resolved);
        if (length >= capacity) {
            free(resolved);
            errno = ERANGE;
            return -1;
        }
        memcpy(out, resolved, length);
        free(resolved);
        return (long long)length;
    }
#else
    {
        ssize_t length = readlink("/proc/self/exe", (char *)out, capacity);
        if (length < 0) { return -1; }
        if ((size_t)length >= capacity) {
            errno = ERANGE;
            return -1;
        }
        return (long long)length;
    }
#endif
}

static inline long long env_current_dir(unsigned char *out, size_t capacity) {
    if (out == NULL || capacity == 0) {
        errno = EINVAL;
        return -1;
    }
#if defined(_WIN32)
    if (capacity > (size_t)INT_MAX) {
        errno = ERANGE;
        return -1;
    }
    if (_getcwd((char *)out, (int)capacity) == NULL) { return -1; }
#else
    if (getcwd((char *)out, capacity) == NULL) { return -1; }
#endif
    return (long long)strlen((char *)out);
}

static inline int env_set_var(const char *name, const char *value) {
#if defined(_WIN32)
    {
        errno_t result = _putenv_s(name, value);
        if (result != 0) {
            errno = (int)result;
            return -1;
        }
        return 0;
    }
#else
    if (setenv(name, value, 1) != 0) { return -1; }
    return 0;
#endif
}

static inline int env_remove_var(const char *name) {
#if defined(_WIN32)
    {
        errno_t result = _putenv_s(name, "");
        if (result != 0) {
            errno = (int)result;
            return -1;
        }
        return 0;
    }
#else
    if (unsetenv(name) != 0) { return -1; }
    return 0;
#endif
}

static inline int env_set_current_dir(const char *path) {
#if defined(_WIN32)
    if (_chdir(path) != 0) { return -1; }
    return 0;
#else
    if (chdir(path) != 0) { return -1; }
    return 0;
#endif
}

static inline int env_last_errno(void) {
    return errno;
}

static inline int env_target_os(void) {
#if defined(_WIN32)
    return 2;
#elif defined(__APPLE__)
    return 1;
#else
    return 0;
#endif
}

static inline int env_target_arch(void) {
#if defined(_M_ARM64) || defined(__aarch64__)
    return 1;
#else
    return 0;
#endif
}

#endif /* ENV_SHIM_H */
