#ifndef ALDER_SIGNAL_SHIM_H
#define ALDER_SIGNAL_SHIM_H

/*
 * Toolchain-owned C binding shim for std.signal.
 *
 * One call installs a handler for one signal, waits for that signal or a
 * timeout, restores the previous disposition, and returns. Standard signals
 * coalesce: the handler writes one byte to a nonblocking self-pipe on POSIX,
 * so one call observes at most one delivery. The header is static inline and
 * adds no link symbol.
 */

#if defined(_WIN32)

#include <errno.h>
#include <stdint.h>
#include <windows.h>

static HANDLE io_signal_event = NULL;
static DWORD io_signal_event_type = 0;

static BOOL WINAPI io_signal_console_handler(DWORD event_type) {
    if (io_signal_event != NULL && event_type == io_signal_event_type) {
        (void)SetEvent(io_signal_event);
        return TRUE;
    }
    return FALSE;
}

static inline int io_signal_wait(int32_t signal_number, int32_t timeout_ms, int32_t *delivered) {
    HANDLE event;
    DWORD waited;
    DWORD wait_ms;
    int result = 0;
    int saved = 0;
    if (delivered == NULL) {
        errno = EINVAL;
        return -1;
    }
    *delivered = 0;
    if (signal_number != (int32_t)CTRL_C_EVENT && signal_number != (int32_t)CTRL_BREAK_EVENT) {
        errno = EINVAL;
        return -1;
    }
    event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (event == NULL) {
        errno = EINVAL;
        return -1;
    }
    io_signal_event = event;
    io_signal_event_type = (DWORD)signal_number;
    if (!SetConsoleCtrlHandler(io_signal_console_handler, TRUE)) {
        (void)CloseHandle(event);
        io_signal_event = NULL;
        errno = EINVAL;
        return -1;
    }
    wait_ms = timeout_ms < 0 ? INFINITE : (DWORD)timeout_ms;
    waited = WaitForSingleObject(event, wait_ms);
    if (waited == WAIT_OBJECT_0) {
        *delivered = 1;
    } else if (waited != WAIT_TIMEOUT) {
        result = -1;
        saved = EINVAL;
    }
    if (!SetConsoleCtrlHandler(io_signal_console_handler, FALSE)) {
        if (result == 0) {
            result = -1;
            saved = EINVAL;
        }
    }
    (void)CloseHandle(event);
    io_signal_event = NULL;
    if (result != 0) {
        errno = saved;
    }
    return result;
}

#else

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static int io_signal_write_fd = -1;

static void io_signal_handler(int signal_number) {
    unsigned char byte = 1;
    ssize_t ignored;
    (void)signal_number;
    if (io_signal_write_fd >= 0) {
        ignored = write(io_signal_write_fd, &byte, (size_t)1);
        (void)ignored;
    }
}

static inline int io_signal_set_flags(int fd) {
    int status_flags = fcntl(fd, F_GETFL, 0);
    int descriptor_flags = fcntl(fd, F_GETFD, 0);
    if (status_flags < 0 || descriptor_flags < 0) {
        return -1;
    }
    if (fcntl(fd, F_SETFL, status_flags | O_NONBLOCK) != 0) {
        return -1;
    }
    if (fcntl(fd, F_SETFD, descriptor_flags | FD_CLOEXEC) != 0) {
        return -1;
    }
    return 0;
}

static inline int io_signal_wait(int32_t signal_number, int32_t timeout_ms, int32_t *delivered) {
    int fds[2];
    struct sigaction action;
    struct sigaction previous;
    struct pollfd descriptor;
    int installed = 0;
    int result = 0;
    int saved = 0;
    if (delivered == NULL) {
        errno = EINVAL;
        return -1;
    }
    *delivered = 0;
    if (pipe(fds) != 0) {
        return -1;
    }
    if (io_signal_set_flags(fds[0]) != 0 || io_signal_set_flags(fds[1]) != 0) {
        saved = errno;
        (void)close(fds[0]);
        (void)close(fds[1]);
        errno = saved;
        return -1;
    }
    (void)memset(&action, 0, sizeof(action));
    (void)memset(&previous, 0, sizeof(previous));
    action.sa_handler = io_signal_handler;
    (void)sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    io_signal_write_fd = fds[1];
    if (sigaction((int)signal_number, &action, &previous) != 0) {
        saved = errno;
        io_signal_write_fd = -1;
        (void)close(fds[0]);
        (void)close(fds[1]);
        errno = saved;
        return -1;
    }
    installed = 1;
    descriptor.fd = fds[0];
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    for (;;) {
        int ready = poll(&descriptor, 1, (int)timeout_ms);
        if (ready < 0) {
            if (errno == EINTR) {
                descriptor.revents = 0;
                continue;
            }
            saved = errno;
            result = -1;
            break;
        }
        if (ready == 0) {
            result = 0;
            break;
        }
        if ((descriptor.revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) != 0) {
            unsigned char bytes[16];
            while (read(fds[0], bytes, sizeof(bytes)) > 0) {
            }
            *delivered = 1;
            result = 0;
            break;
        }
    }
    if (installed != 0 && sigaction((int)signal_number, &previous, NULL) != 0) {
        if (result == 0) {
            saved = errno;
            result = -1;
        }
    }
    io_signal_write_fd = -1;
    (void)close(fds[0]);
    (void)close(fds[1]);
    if (result != 0) {
        errno = saved;
    }
    return result;
}

#endif

#endif
