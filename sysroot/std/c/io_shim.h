/*
 * Toolchain-owned C binding shims for the std.io blocking capability.
 *
 * Everything here exists because the operation cannot be named by a raw fn
 * binding against the real headers: open is variadic, struct stat and struct
 * dirent keep platform layout in C, standard C has no portable byte-pointer
 * spelling for read/write, realpath allocates, and the clock/random calls need
 * timespec layout or platform fallbacks. Names stay outside the reserved
 * alder_/Alder_/ALDER_ prefix because the binding spelling policy reserves it.
 *
 * Header-only static inline definitions add no link symbol. Every function
 * either performs the host call directly or marshals verified fixed-width
 * fields; the Alder side never dereferences a host pointer.
 */
#ifndef IO_SHIM_H
#define IO_SHIM_H

#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/random.h>
#elif defined(__APPLE__)
#include <sys/random.h>
#endif

/* The portable subset of file metadata std.io exposes. The kind values match
 * the Alder EntryKind order: 0 unknown, 1 file, 2 directory, 3 symlink,
 * 4 other. */
typedef struct io_file_stat {
    int32_t kind;
    unsigned long long size;
    uint32_t mode;
    long long seconds;
    int32_t nanos;
} io_file_stat;

static inline int io_kind_from_mode(mode_t mode) {
    if (S_ISREG(mode)) { return 1; }
    if (S_ISDIR(mode)) { return 2; }
    if (S_ISLNK(mode)) { return 3; }
    return 0;
}

static inline int io_kind_from_dtype(unsigned char kind) {
#ifdef DT_REG
    if (kind == DT_REG) { return 1; }
    if (kind == DT_DIR) { return 2; }
    if (kind == DT_LNK) { return 3; }
    if (kind != DT_UNKNOWN) { return 4; }
#else
    (void)kind;
#endif
    return 0;
}

static inline void io_fill_stat(const struct stat *st, io_file_stat *out) {
    out->kind = io_kind_from_mode(st->st_mode);
    out->size = (unsigned long long)st->st_size;
    out->mode = (uint32_t)st->st_mode;
    out->seconds = (long long)st->st_mtime;
#if defined(__APPLE__)
    out->nanos = (int32_t)st->st_mtimespec.tv_nsec;
#else
    out->nanos = (int32_t)st->st_mtim.tv_nsec;
#endif
}

static inline int io_open(const char *path, int read, int write, int append,
                          int truncate_file, int create, int create_new) {
    int flags;
    if (read && write) { flags = O_RDWR; }
    else if (write) { flags = O_WRONLY; }
    else { flags = O_RDONLY; }
    if (append) { flags |= O_APPEND; }
    if (truncate_file) { flags |= O_TRUNC; }
    if (create_new) { flags |= O_CREAT | O_EXCL; }
    else if (create) { flags |= O_CREAT; }
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    int fd;
    do {
        fd = open(path, flags, (mode_t)0666);
    } while (fd < 0 && errno == EINTR);
    return fd;
}

static inline long long io_read(int fd, unsigned char *buffer, size_t length) {
    ssize_t got;
    do {
        got = read(fd, buffer, length);
    } while (got < 0 && errno == EINTR);
    return (long long)got;
}

static inline long long io_write(int fd, const unsigned char *buffer, size_t length) {
    ssize_t put;
    do {
        put = write(fd, buffer, length);
    } while (put < 0 && errno == EINTR);
    return (long long)put;
}

static inline int io_seek(int fd, long long offset, int whence, long long *result) {
    off_t moved = lseek(fd, (off_t)offset, whence);
    if (moved < 0) { return -1; }
    *result = (long long)moved;
    return 0;
}

static inline int io_fstat(int fd, io_file_stat *out) {
    struct stat st;
    if (fstat(fd, &st) != 0) { return -1; }
    io_fill_stat(&st, out);
    return 0;
}

static inline int io_stat_path(const char *path, io_file_stat *out) {
    struct stat st;
    if (stat(path, &st) != 0) { return -1; }
    io_fill_stat(&st, out);
    return 0;
}

static inline int io_close(int fd) {
    /* POSIX leaves the descriptor state unspecified after an interrupted
     * close, so a retry could close a descriptor another operation reused. */
    return close(fd);
}

static inline int io_fsync(int fd) {
    int rc;
    do { rc = fsync(fd); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline int io_fchmod(int fd, unsigned int mode) {
    int rc;
    do { rc = fchmod(fd, (mode_t)mode); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline int io_chmod(const char *path, unsigned int mode) {
    int rc;
    do { rc = chmod(path, (mode_t)mode); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline int io_rename(const char *from, const char *to) {
    int rc;
    do { rc = rename(from, to); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline int io_remove(const char *path) {
    int rc;
    do { rc = unlink(path); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline int io_rmdir(const char *path) {
    int rc;
    do { rc = rmdir(path); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline int io_mkdir(const char *path, unsigned int mode) {
    int rc;
    do { rc = mkdir(path, (mode_t)mode); } while (rc != 0 && errno == EINTR);
    return rc;
}

static inline long long io_realpath(const char *path, unsigned char *out, size_t capacity) {
    char *resolved = realpath(path, NULL);
    if (resolved == NULL) { return -1; }
    size_t length = strlen(resolved);
    if (length >= capacity) {
        free(resolved);
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(out, resolved, length);
    free(resolved);
    return (long long)length;
}

/* A directory token is an opaque round trip: the Alder side never dereferences
 * it, only passes it back to io_read_dir/io_close_dir. */
static inline unsigned long long io_open_dir(const char *path) {
    DIR *dir = opendir(path);
    return (unsigned long long)(uintptr_t)dir;
}

static inline int io_read_dir(unsigned long long token, unsigned char *name,
                              size_t capacity, size_t *length, int *kind) {
    DIR *dir = (DIR *)(uintptr_t)token;
    errno = 0;
    struct dirent *entry = readdir(dir);
    if (entry == NULL) {
        if (errno != 0) { return -1; }
        return 0;
    }
    size_t name_length = strlen(entry->d_name);
    if (name_length >= capacity) {
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(name, entry->d_name, name_length);
    *length = name_length;
#if defined(_DIRENT_HAVE_D_TYPE) || defined(__APPLE__)
    *kind = io_kind_from_dtype((unsigned char)entry->d_type);
#else
    *kind = 0;
#endif
    return 1;
}

static inline int io_close_dir(unsigned long long token) {
    return closedir((DIR *)(uintptr_t)token);
}

static inline int io_clock_gettime(int which, long long *seconds, int32_t *nanos) {
    struct timespec now;
    clockid_t id = which == 1 ? CLOCK_MONOTONIC : CLOCK_REALTIME;
    int rc;
    do { rc = clock_gettime(id, &now); } while (rc != 0 && errno == EINTR);
    if (rc != 0) { return -1; }
    *seconds = (long long)now.tv_sec;
    *nanos = (int32_t)now.tv_nsec;
    return 0;
}

static inline int io_sleep(unsigned long long seconds, unsigned int nanos) {
    struct timespec request;
    request.tv_sec = (time_t)seconds;
    request.tv_nsec = (long)nanos;
    while (nanosleep(&request, &request) != 0) {
        if (errno != EINTR) { return -1; }
    }
    return 0;
}

static inline int io_random(unsigned char *buffer, size_t length) {
#if defined(__linux__)
    size_t done = 0;
    while (done < length) {
        ssize_t got = getrandom(buffer + done, length - done, 0);
        if (got < 0) {
            if (errno == EINTR) { continue; }
            return -1;
        }
        done += (size_t)got;
    }
    return 0;
#elif defined(__APPLE__)
    size_t done = 0;
    while (done < length) {
        size_t chunk = length - done;
        if (chunk > 256) { chunk = 256; }
        if (getentropy(buffer + done, chunk) != 0) {
            if (errno == EINTR) { continue; }
            return -1;
        }
        done += chunk;
    }
    return 0;
#else
    (void)buffer;
    (void)length;
    errno = ENOSYS;
    return -1;
#endif
}

static inline size_t io_errno_message(int code, unsigned char *out, size_t capacity) {
    const char *text = strerror(code);
    if (text == NULL) { return 0; }
    size_t length = strlen(text);
    if (length > capacity) { length = capacity; }
    memcpy(out, text, length);
    return length;
}

#endif
