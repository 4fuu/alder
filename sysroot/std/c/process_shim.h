/*
 * Toolchain-owned C binding shim for std.process.
 *
 * The Alder side passes NUL-separated argument and environment blobs; this
 * header owns the pointer arrays, PATH resolution, pipe setup, fork/exec,
 * wait status decoding, and signalling. Child descriptors are returned as
 * plain integers so std.io can build HostFile pipe ends inside the module;
 * std.process never forges a handle.
 */
#ifndef PROCESS_SHIM_H
#define PROCESS_SHIM_H

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

typedef struct io_child_start {
    int32_t pid;
    int32_t stdin_fd;
    int32_t stdout_fd;
    int32_t stderr_fd;
} io_child_start;

typedef struct io_child_status {
    int32_t kind;
    int32_t value;
} io_child_status;

typedef struct io_poll_pair {
    int32_t first_ready;
    int32_t second_ready;
} io_poll_pair;

/* One mode per standard stream: 0 inherits the parent descriptor, 1 creates a
 * pipe and returns the parent end. */
static inline int io_pipe_pair(int *read_fd, int *write_fd) {
    int fds[2];
    if (pipe(fds) != 0) { return -1; }
    if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) != 0 || fcntl(fds[1], F_SETFD, FD_CLOEXEC) != 0) {
        (void)close(fds[0]);
        (void)close(fds[1]);
        return -1;
    }
    *read_fd = fds[0];
    *write_fd = fds[1];
    return 0;
}

static inline int io_blob_count(const unsigned char *blob, size_t length) {
    size_t at = 0;
    int count = 0;
    while (at < length) {
        size_t end = at;
        while (end < length && blob[end] != 0) { end = end + 1; }
        if (end >= length) { return -1; }
        count = count + 1;
        at = end + 1;
    }
    return count;
}

static inline char **io_blob_argv(const unsigned char *blob, size_t length) {
    int count = io_blob_count(blob, length);
    char **argv;
    size_t at = 0;
    int index = 0;
    if (count < 0) { return NULL; }
    argv = (char **)malloc(((size_t)count + 1) * sizeof(char *));
    if (argv == NULL) { return NULL; }
    while (at < length) {
        size_t end = at;
        while (end < length && blob[end] != 0) { end = end + 1; }
        argv[index] = (char *)(blob + at);
        index = index + 1;
        at = end + 1;
    }
    argv[index] = NULL;
    return argv;
}

static inline int io_env_name_matches(const char *entry, const char *key, size_t key_length) {
    if (strncmp(entry, key, key_length) != 0) { return 0; }
    return entry[key_length] == '=';
}

static inline int io_env_removed(const char *entry, const unsigned char *remove_blob, size_t remove_length) {
    size_t at = 0;
    while (at < remove_length) {
        size_t end = at;
        while (end < remove_length && remove_blob[end] != 0) { end = end + 1; }
        if (io_env_name_matches(entry, (const char *)(remove_blob + at), end - at)) { return 1; }
        at = end + 1;
    }
    return 0;
}

/* A later set entry with the same key replaces an earlier one. */
static inline int io_env_set_later(const unsigned char *blob, size_t length, size_t at, size_t end) {
    size_t key_length = 0;
    size_t scan = end + 1;
    while (at + key_length < end && blob[at + key_length] != '=') { key_length = key_length + 1; }
    while (scan < length) {
        size_t next = scan;
        while (next < length && blob[next] != 0) { next = next + 1; }
        if (next > scan && io_env_name_matches((const char *)(blob + scan), (const char *)(blob + at), key_length)) { return 1; }
        scan = next + 1;
    }
    return 0;
}

static inline char **io_build_env(const unsigned char *set_blob, size_t set_length,
                                  const unsigned char *remove_blob, size_t remove_length,
                                  int clear_environment) {
    int inherited = 0;
    int set_count = io_blob_count(set_blob, set_length);
    int index = 0;
    int capacity;
    int out = 0;
    char **envp;
    size_t at;
    if (set_count < 0) { return NULL; }
    while (environ != NULL && environ[inherited] != NULL) { inherited = inherited + 1; }
    capacity = (clear_environment ? 0 : inherited) + set_count + 1;
    envp = (char **)malloc((size_t)capacity * sizeof(char *));
    if (envp == NULL) { return NULL; }
    if (!clear_environment) {
        while (index < inherited) {
            char *entry = environ[index];
            int overridden = 0;
            size_t set_at = 0;
            while (set_at < set_length) {
                size_t end = set_at;
                while (end < set_length && set_blob[end] != 0) { end = end + 1; }
                if (io_env_name_matches(entry, (const char *)(set_blob + set_at), end - set_at)) { overridden = 1; }
                set_at = end + 1;
            }
            if (!overridden && !io_env_removed(entry, remove_blob, remove_length)) { envp[out] = entry; out = out + 1; }
            index = index + 1;
        }
    }
    at = 0;
    while (at < set_length) {
        size_t end = at;
        while (end < set_length && set_blob[end] != 0) { end = end + 1; }
        if (!io_env_set_later(set_blob, set_length, at, end)) {
            envp[out] = (char *)(set_blob + at);
            out = out + 1;
        }
        at = end + 1;
    }
    envp[out] = NULL;
    return envp;
}

static inline char *io_resolve_program(const char *program, char *const envp[]) {
    const char *path = NULL;
    size_t length;
    char *candidate;
    int index = 0;
    if (strchr(program, '/') != NULL) {
        length = strlen(program) + 1;
        candidate = (char *)malloc(length);
        if (candidate == NULL) { return NULL; }
        memcpy(candidate, program, length);
        return candidate;
    }
    while (envp[index] != NULL) {
        if (strncmp(envp[index], "PATH=", 5) == 0) { path = envp[index] + 5; break; }
        index = index + 1;
    }
    if (path == NULL) { path = "/usr/local/bin:/usr/bin:/bin"; }
    while (*path != 0) {
        const char *end = strchr(path, ':');
        size_t dir_length = end == NULL ? strlen(path) : (size_t)(end - path);
        size_t need = dir_length + 1 + strlen(program) + 1;
        candidate = (char *)malloc(need);
        if (candidate == NULL) { return NULL; }
        memcpy(candidate, path, dir_length);
        candidate[dir_length] = '/';
        memcpy(candidate + dir_length + 1, program, strlen(program) + 1);
        if (access(candidate, X_OK) == 0) { return candidate; }
        free(candidate);
        if (end == NULL) { break; }
        path = end + 1;
    }
    return NULL;
}

static inline int io_spawn(const char *program,
                           const unsigned char *argv_blob, size_t argv_length,
                           const unsigned char *set_blob, size_t set_length,
                           const unsigned char *remove_blob, size_t remove_length,
                           int clear_environment,
                           int has_working_directory,
                           const char *working_directory,
                           int stdin_mode, int stdout_mode, int stderr_mode,
                           io_child_start *out) {
    char **argv = io_blob_argv(argv_blob, argv_length);
    char **envp = io_build_env(set_blob, set_length, remove_blob, remove_length, clear_environment);
    char *resolved = NULL;
    int child_stdin = -1;
    int child_stdout = -1;
    int child_stderr = -1;
    int parent_stdin = -1;
    int parent_stdout = -1;
    int parent_stderr = -1;
    int error_pipe[2] = { -1, -1 };
    int child_error = 0;
    pid_t child;
    if (argv == NULL || envp == NULL) { free(argv); free(envp); return -1; }
    resolved = io_resolve_program(program, envp);
    if (resolved == NULL) { free(argv); free(envp); return -1; }
    if (stdin_mode == 1) {
        if (io_pipe_pair(&child_stdin, &parent_stdin) != 0) { free(resolved); free(argv); free(envp); return -1; }
    }
    if (stdout_mode == 1) {
        if (io_pipe_pair(&parent_stdout, &child_stdout) != 0) { goto failed; }
    }
    if (stderr_mode == 1) {
        if (io_pipe_pair(&parent_stderr, &child_stderr) != 0) { goto failed; }
    }
    if (pipe(error_pipe) != 0) { goto failed; }
    if (fcntl(error_pipe[1], F_SETFD, FD_CLOEXEC) != 0) { goto failed; }
    child = fork();
    if (child < 0) { goto failed; }
    if (child == 0) {
        (void)close(error_pipe[0]);
        if (child_stdin >= 0) { if (dup2(child_stdin, STDIN_FILENO) < 0) { child_error = errno; goto child_failed; } }
        if (child_stdout >= 0) { if (dup2(child_stdout, STDOUT_FILENO) < 0) { child_error = errno; goto child_failed; } }
        if (child_stderr >= 0) { if (dup2(child_stderr, STDERR_FILENO) < 0) { child_error = errno; goto child_failed; } }
        if (child_stdin > STDERR_FILENO) { (void)close(child_stdin); }
        if (child_stdout > STDERR_FILENO) { (void)close(child_stdout); }
        if (child_stderr > STDERR_FILENO) { (void)close(child_stderr); }
        if (has_working_directory != 0 && chdir(working_directory) != 0) { child_error = errno; goto child_failed; }
        execve(resolved, argv, envp);
        child_error = errno;
child_failed:
        (void)write(error_pipe[1], &child_error, sizeof(child_error));
        _exit(126);
    }
    (void)close(error_pipe[1]);
    if (read(error_pipe[0], &child_error, sizeof(child_error)) > 0) {
        (void)close(error_pipe[0]);
        (void)waitpid(child, NULL, 0);
        errno = child_error;
        if (child_stdin >= 0) { (void)close(child_stdin); }
        if (child_stdout >= 0) { (void)close(child_stdout); }
        if (child_stderr >= 0) { (void)close(child_stderr); }
        free(resolved); free(argv); free(envp);
        return -1;
    }
    (void)close(error_pipe[0]);
    if (child_stdin >= 0) { (void)close(child_stdin); }
    if (child_stdout >= 0) { (void)close(child_stdout); }
    if (child_stderr >= 0) { (void)close(child_stderr); }
    out->pid = (int32_t)child;
    out->stdin_fd = parent_stdin;
    out->stdout_fd = parent_stdout;
    out->stderr_fd = parent_stderr;
    free(resolved);
    free(argv);
    free(envp);
    return 0;
failed:
    if (error_pipe[0] >= 0) { (void)close(error_pipe[0]); }
    if (error_pipe[1] >= 0) { (void)close(error_pipe[1]); }
    if (child_stdin >= 0) { (void)close(child_stdin); }
    if (child_stdout >= 0) { (void)close(child_stdout); }
    if (child_stderr >= 0) { (void)close(child_stderr); }
    if (parent_stdin >= 0) { (void)close(parent_stdin); }
    if (parent_stdout >= 0) { (void)close(parent_stdout); }
    if (parent_stderr >= 0) { (void)close(parent_stderr); }
    free(resolved);
    free(argv);
    free(envp);
    return -1;
}

static inline int io_wait_child(int32_t pid, io_child_status *out) {
    int status = 0;
    pid_t result;
    do {
        result = waitpid((pid_t)pid, &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result < 0) { return -1; }
    if (WIFEXITED(status)) {
        out->kind = 0;
        out->value = WEXITSTATUS(status);
        return 0;
    }
    if (WIFSIGNALED(status)) {
        out->kind = 1;
        out->value = WTERMSIG(status);
        return 0;
    }
    out->kind = 2;
    out->value = status;
    return 0;
}

static inline int io_kill_child(int32_t pid) {
    if (kill((pid_t)pid, SIGKILL) != 0) { return -1; }
    return 0;
}

/* Waits until either descriptor has input, hangup, or an error. A negative
 * timeout waits forever. Readable descriptions include POLLHUP and POLLERR so
 * the caller always reaches a read that observes end of stream. */
static inline int io_poll_pair_wait(int32_t first_fd, int32_t second_fd, int32_t timeout_ms, io_poll_pair *out) {
    struct pollfd fds[2];
    int ready;
    fds[0].fd = (int)first_fd;
    fds[0].events = POLLIN;
    fds[0].revents = 0;
    fds[1].fd = (int)second_fd;
    fds[1].events = POLLIN;
    fds[1].revents = 0;
    do {
        ready = poll(fds, 2, (int)timeout_ms);
    } while (ready < 0 && errno == EINTR);
    if (ready < 0) { return -1; }
    out->first_ready = (fds[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) != 0;
    out->second_ready = (fds[1].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) != 0;
    return 0;
}

#endif /* PROCESS_SHIM_H */
