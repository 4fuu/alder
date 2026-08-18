#include "alder_host.h"

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <direct.h>
#include <windows.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#ifndef ALDER_HOST_CC
#define ALDER_HOST_CC "cc"
#endif
#ifndef ALDER_HOST_RUNTIME_C
#define ALDER_HOST_RUNTIME_C "runtime/c/alder.c"
#endif
#ifndef ALDER_HOST_RUNTIME_INCLUDE_DIR
#define ALDER_HOST_RUNTIME_INCLUDE_DIR "runtime/c"
#endif
#ifndef ALDER_HOST_INCLUDE_DIR
#define ALDER_HOST_INCLUDE_DIR "bootstrap"
#endif
#ifndef ALDER_HOST_TRIPLE
#if defined(_WIN32) && defined(_M_X64)
#define ALDER_HOST_TRIPLE "x86_64-pc-windows-msvc"
#elif defined(_WIN32) && defined(_M_ARM64)
#define ALDER_HOST_TRIPLE "aarch64-pc-windows-msvc"
#elif defined(__APPLE__) && defined(__aarch64__)
#define ALDER_HOST_TRIPLE "aarch64-apple-darwin"
#elif defined(__APPLE__) && defined(__x86_64__)
#define ALDER_HOST_TRIPLE "x86_64-apple-darwin"
#elif defined(__linux__) && defined(__aarch64__)
#define ALDER_HOST_TRIPLE "aarch64-unknown-linux-gnu"
#elif defined(__linux__) && defined(__x86_64__)
#define ALDER_HOST_TRIPLE "x86_64-unknown-linux-gnu"
#else
#define ALDER_HOST_TRIPLE "unknown-host"
#endif
#endif

#if defined(ALDER_HOST_LARGE_STACK) && defined(__linux__)
#include <sys/resource.h>
#endif

struct AlderHostSource {
    const char *path;
    uint64_t path_len;
    uint8_t *text;
    uint64_t text_len;
    bool owned_path;
};

struct AlderHostContext {
    struct AlderHostSource *sources;
    uint64_t source_count;
    size_t source_capacity;
    uint64_t command;
    bool project_mode;
    uint64_t project_action;
    uint8_t *manifest;
    uint64_t manifest_len;
    const char *target;
    const char *profile;
    const char *triple;
    char *source_request;
    size_t source_request_len;
    size_t source_request_capacity;
    char *project_paths[2];
    char *project_path_request;
    size_t project_path_request_len;
    size_t project_path_request_capacity;
    uint64_t project_path_kind;
    uint64_t project_target_kind;
    uint64_t project_entry_source;
    char **run_args;
    size_t run_arg_count;
    bool json;
    const char *output_path;
    uint64_t output_path_len;
    uint64_t output_mode;
    bool output_failed;
    bool response_started;
    uint8_t *response;
    size_t response_len;
    size_t response_capacity;
    FILE *artifact;
    char *artifact_temp;
};

static struct AlderHostContext *alderhost_active_context;

static bool alderhost_configure_stack(void) {
#if defined(ALDER_HOST_LARGE_STACK) && defined(__linux__)
    const rlim_t wanted = (rlim_t)UINT64_C(67108864);
    struct rlimit limit;
    if (getrlimit(RLIMIT_STACK, &limit) != 0) {
        return false;
    }
    if (limit.rlim_cur >= wanted) {
        return true;
    }
    if (limit.rlim_max != RLIM_INFINITY && limit.rlim_max < wanted) {
        return false;
    }
    limit.rlim_cur = wanted;
    return setrlimit(RLIMIT_STACK, &limit) == 0;
#else
    return true;
#endif
}

static bool alderhost_size_to_u64(size_t value, uint64_t *out) {
#if SIZE_MAX > UINT64_MAX
    if (value > (size_t)UINT64_MAX) {
        return false;
    }
#endif
    *out = (uint64_t)value;
    return true;
}

static void alderhost_contract_failure(void) {
    (void)fputs("alder host: source accessor contract violation\n", stderr);
    (void)fflush(stderr);
    abort();
}

static struct AlderHostSource *alderhost_source(uint64_t source) {
    if (alderhost_active_context == NULL ||
        source >= alderhost_active_context->source_count) {
        alderhost_contract_failure();
    }
    return &alderhost_active_context->sources[(size_t)source];
}

uint64_t alderhost_source_count(void) {
    if (alderhost_active_context == NULL) {
        alderhost_contract_failure();
    }
    return alderhost_active_context->source_count;
}

uint64_t alderhost_source_path_len(uint64_t source) {
    return alderhost_source(source)->path_len;
}

uint8_t alderhost_source_path_byte(uint64_t source, uint64_t offset) {
    struct AlderHostSource *item = alderhost_source(source);
    if (offset >= item->path_len) {
        alderhost_contract_failure();
    }
    return (uint8_t)(unsigned char)item->path[(size_t)offset];
}

uint64_t alderhost_source_text_len(uint64_t source) {
    return alderhost_source(source)->text_len;
}

uint8_t alderhost_source_text_byte(uint64_t source, uint64_t offset) {
    struct AlderHostSource *item = alderhost_source(source);
    if (offset >= item->text_len) {
        alderhost_contract_failure();
    }
    return item->text[(size_t)offset];
}

uint64_t alderhost_command(void) {
    if (alderhost_active_context == NULL) {
        alderhost_contract_failure();
    }
    return alderhost_active_context->command;
}

bool alderhost_project_mode(void) {
    return alderhost_active_context != NULL && alderhost_active_context->project_mode;
}

uint64_t alderhost_project_action(void) {
    if (alderhost_active_context == NULL) { alderhost_contract_failure(); }
    return alderhost_active_context->project_action;
}

uint64_t alderhost_manifest_len(void) {
    if (alderhost_active_context == NULL) { alderhost_contract_failure(); }
    return alderhost_active_context->manifest_len;
}

uint8_t alderhost_manifest_byte(uint64_t offset) {
    if (alderhost_active_context == NULL || offset >= alderhost_active_context->manifest_len) {
        alderhost_contract_failure();
    }
    return alderhost_active_context->manifest[(size_t)offset];
}

static uint64_t alderhost_option_len(const char *value) {
    uint64_t length;
    if (alderhost_active_context == NULL) { alderhost_contract_failure(); }
    if (value == NULL) { return UINT64_C(0); }
    if (!alderhost_size_to_u64(strlen(value), &length)) { alderhost_contract_failure(); }
    return length;
}

static uint8_t alderhost_option_byte(const char *value, uint64_t offset) {
    if (value == NULL || offset >= alderhost_option_len(value)) { alderhost_contract_failure(); }
    return (uint8_t)(unsigned char)value[(size_t)offset];
}

uint64_t alderhost_target_len(void) { return alderhost_option_len(alderhost_active_context == NULL ? NULL : alderhost_active_context->target); }
uint8_t alderhost_target_byte(uint64_t offset) { return alderhost_option_byte(alderhost_active_context == NULL ? NULL : alderhost_active_context->target, offset); }
uint64_t alderhost_profile_len(void) { return alderhost_option_len(alderhost_active_context == NULL ? NULL : alderhost_active_context->profile); }
uint8_t alderhost_profile_byte(uint64_t offset) { return alderhost_option_byte(alderhost_active_context == NULL ? NULL : alderhost_active_context->profile, offset); }
uint64_t alderhost_triple_len(void) { return alderhost_option_len(alderhost_active_context == NULL ? NULL : alderhost_active_context->triple); }
uint8_t alderhost_triple_byte(uint64_t offset) { return alderhost_option_byte(alderhost_active_context == NULL ? NULL : alderhost_active_context->triple, offset); }

bool alderhost_format_json(void) {
    if (alderhost_active_context == NULL) {
        alderhost_contract_failure();
    }
    return alderhost_active_context->json;
}

uint64_t alderhost_output_path_len(void) {
    if (alderhost_active_context == NULL) {
        alderhost_contract_failure();
    }
    return alderhost_active_context->output_path_len;
}

uint8_t alderhost_output_path_byte(uint64_t offset) {
    if (alderhost_active_context == NULL ||
        offset >= alderhost_active_context->output_path_len) {
        alderhost_contract_failure();
    }
    return (uint8_t)(unsigned char)alderhost_active_context->output_path[(size_t)offset];
}

bool alderhost_output_mode(uint64_t mode) {
    if (alderhost_active_context == NULL || mode > UINT64_C(2)) {
        return false;
    }
    alderhost_active_context->output_mode = mode;
    return true;
}

bool alderhost_output_failed(void) {
    return alderhost_active_context != NULL &&
           alderhost_active_context->output_failed;
}

bool alderhost_response_reset(void) {
    if (alderhost_active_context == NULL) {
        return false;
    }
    alderhost_active_context->response_len = 0;
    alderhost_active_context->output_mode = 0;
    alderhost_active_context->response_started = false;
    return true;
}

static bool alderhost_response_byte(struct AlderHostContext *context,
                                    uint8_t byte) {
    if (!context->json) {
        return fputc((int)byte, stdout) != EOF;
    }
    if (context->response_len == context->response_capacity) {
        size_t next = context->response_capacity == 0 ? (size_t)4096 :
                      context->response_capacity * (size_t)2;
        uint8_t *grown;
        if (next < context->response_capacity) {
            return false;
        }
        grown = (uint8_t *)realloc(context->response, next);
        if (grown == NULL) {
            return false;
        }
        context->response = grown;
        context->response_capacity = next;
    }
    context->response[context->response_len++] = byte;
    return true;
}

static bool alderhost_artifact_open(struct AlderHostContext *context) {
    size_t suffix;
    unsigned int attempt;
    if (context->artifact != NULL) {
        return true;
    }
    suffix = strlen(context->output_path) + sizeof(".alder-tmp-999");
    context->artifact_temp = (char *)malloc(suffix);
    if (context->artifact_temp == NULL) {
        return false;
    }
    for (attempt = 0; attempt < 1000U; attempt++) {
        int count = snprintf(context->artifact_temp, suffix, "%s.alder-tmp-%u",
                             context->output_path, attempt);
        if (count < 0 || (size_t)count >= suffix) {
            return false;
        }
        errno = 0;
        context->artifact = fopen(context->artifact_temp, "wbx");
        if (context->artifact == NULL && errno != EEXIST) {
            errno = 0;
            context->artifact = fopen(context->artifact_temp, "wb");
        }
        if (context->artifact != NULL) {
            return true;
        }
        if (errno == EEXIST) {
            continue;
        }
        return false;
    }
    return false;
}

static bool alderhost_json_artifact_byte(struct AlderHostContext *context,
                                         uint8_t byte) {
    static const char hex[] = "0123456789abcdef";
    if (byte == (uint8_t)'"' || byte == (uint8_t)'\\') {
        return alderhost_response_byte(context, (uint8_t)'\\') &&
               alderhost_response_byte(context, byte);
    }
    if (byte < UINT8_C(32)) {
        const char *escape = NULL;
        if (byte == UINT8_C(8)) { escape = "\\b"; }
        if (byte == UINT8_C(9)) { escape = "\\t"; }
        if (byte == UINT8_C(10)) { escape = "\\n"; }
        if (byte == UINT8_C(12)) { escape = "\\f"; }
        if (byte == UINT8_C(13)) { escape = "\\r"; }
        if (escape != NULL) {
            return alderhost_response_byte(context, (uint8_t)escape[0]) &&
                   alderhost_response_byte(context, (uint8_t)escape[1]);
        }
        return alderhost_response_byte(context, (uint8_t)'\\') &&
               alderhost_response_byte(context, (uint8_t)'u') &&
               alderhost_response_byte(context, (uint8_t)'0') &&
               alderhost_response_byte(context, (uint8_t)'0') &&
               alderhost_response_byte(context, (uint8_t)hex[byte >> 4U]) &&
               alderhost_response_byte(context, (uint8_t)hex[byte & UINT8_C(15)]);
    }
    return alderhost_response_byte(context, byte);
}

bool alderhost_stdout_byte(uint8_t byte) {
    struct AlderHostContext *context = alderhost_active_context;
    bool wrote = false;
    if (context == NULL) {
        return false;
    }
    if (context->output_mode == UINT64_C(0)) {
        wrote = alderhost_response_byte(context, byte);
    } else if (context->output_mode == UINT64_C(1)) {
        wrote = fputc((int)byte, stderr) != EOF;
    } else if (context->output_path != NULL) {
        wrote = alderhost_artifact_open(context) &&
                fputc((int)byte, context->artifact) != EOF;
    } else if (context->json) {
        wrote = alderhost_json_artifact_byte(context, byte);
    } else {
        wrote = fputc((int)byte, stdout) != EOF;
    }
    if (!wrote) {
        context->output_failed = true;
    } else if (context->output_mode != UINT64_C(2)) {
        context->response_started = true;
    }
    return wrote;
}

/* Emit the same shortest-round-trip finite float spelling as Go's
 * strconv.FormatFloat(value, 'g', -1, 64). The scientific conversion finds
 * the minimum significant digit count that round-trips; the final layout uses
 * Go's fixed/exponent boundary rather than the precision-dependent C %g rule. */
bool alderhost_stdout_f64_bits(uint64_t bits) {
    char scientific[32];
    char digits[18];
    char *end;
    double value;
    double parsed;
    uint64_t parsed_bits;
    long exponent;
    int precision;
    int count;
    size_t digit_count;
    size_t at;
    bool negative;

    if (alderhost_active_context == NULL ||
        ((bits >> 52U) & UINT64_C(0x7ff)) == UINT64_C(0x7ff)) {
        return false;
    }
    (void)memcpy(&value, &bits, sizeof(value));
    count = -1;
    for (precision = 1; precision <= 17; precision++) {
        count = snprintf(scientific, sizeof(scientific), "%.*e", precision - 1,
                         value);
        if (count < 0 || (size_t)count >= sizeof(scientific)) {
            return false;
        }
        end = NULL;
        parsed = strtod(scientific, &end);
        if (end == scientific || *end != '\0') {
            return false;
        }
        (void)memcpy(&parsed_bits, &parsed, sizeof(parsed_bits));
        if (parsed_bits == bits) {
            break;
        }
    }
    if (precision > 17 || count < 0) {
        return false;
    }

    negative = scientific[0] == '-';
    at = negative ? 1U : 0U;
    digit_count = 0U;
    while (scientific[at] != 'e') {
        if (scientific[at] != '.') {
            digits[digit_count++] = scientific[at];
        }
        at++;
    }
    exponent = strtol(&scientific[at + 1U], &end, 10);
    if (*end != '\0' || digit_count == 0U) {
        return false;
    }

#define ALDERHOST_FLOAT_BYTE(byte_) \
    do { \
        if (!alderhost_stdout_byte((uint8_t)(unsigned char)(byte_))) { \
            return false; \
        } \
    } while (0)
    if (negative) {
        ALDERHOST_FLOAT_BYTE('-');
    }
    if (exponent < -4L || exponent >= 6L) {
        ALDERHOST_FLOAT_BYTE(digits[0]);
        if (digit_count > 1U) {
            ALDERHOST_FLOAT_BYTE('.');
            for (at = 1U; at < digit_count; at++) {
                ALDERHOST_FLOAT_BYTE(digits[at]);
            }
        }
        ALDERHOST_FLOAT_BYTE('e');
        ALDERHOST_FLOAT_BYTE(exponent < 0L ? '-' : '+');
        if (exponent < 0L) {
            exponent = -exponent;
        }
        if (exponent < 10L) {
            ALDERHOST_FLOAT_BYTE('0');
        }
        if (exponent >= 100L) {
            ALDERHOST_FLOAT_BYTE((char)('0' + exponent / 100L));
        }
        if (exponent >= 10L) {
            ALDERHOST_FLOAT_BYTE((char)('0' + (exponent / 10L) % 10L));
        }
        ALDERHOST_FLOAT_BYTE((char)('0' + exponent % 10L));
    } else if (exponent < 0L) {
        ALDERHOST_FLOAT_BYTE('0');
        ALDERHOST_FLOAT_BYTE('.');
        for (at = 0U; at < (size_t)(-exponent - 1L); at++) {
            ALDERHOST_FLOAT_BYTE('0');
        }
        for (at = 0U; at < digit_count; at++) {
            ALDERHOST_FLOAT_BYTE(digits[at]);
        }
    } else {
        size_t integer_digits = (size_t)exponent + 1U;
        for (at = 0U; at < integer_digits; at++) {
            ALDERHOST_FLOAT_BYTE(at < digit_count ? digits[at] : '0');
        }
        if (digit_count > integer_digits) {
            ALDERHOST_FLOAT_BYTE('.');
            for (at = integer_digits; at < digit_count; at++) {
                ALDERHOST_FLOAT_BYTE(digits[at]);
            }
        }
    }
#undef ALDERHOST_FLOAT_BYTE
    return true;
}

uint64_t alderhost_decimal_f64_bits(uint64_t negative, uint64_t significand,
                                    int64_t exponent) {
    char text[96];
    char *parsed_end;
    double value;
    uint64_t bits = 0;
    int count;

    count = snprintf(text, sizeof(text), "%s%" PRIu64 "e%" PRId64,
                     negative != 0U ? "-" : "", significand, exponent);
    if (count < 0 || (size_t)count >= sizeof(text)) {
        alderhost_contract_failure();
    }
    parsed_end = NULL;
    value = strtod(text, &parsed_end);
    if (parsed_end == text || *parsed_end != '\0') {
        alderhost_contract_failure();
    }
    (void)memcpy(&bits, &value, sizeof(bits));
    return bits;
}

bool alderhost_stderr_byte(uint8_t byte) {
    bool wrote = alderhost_active_context != NULL &&
                 fputc((int)byte, stderr) != EOF;
    if (wrote) {
        alderhost_active_context->response_started = true;
    }
    return wrote;
}

static int alderhost_compare_paths(const void *left, const void *right) {
    const struct AlderHostSource *a = (const struct AlderHostSource *)left;
    const struct AlderHostSource *b = (const struct AlderHostSource *)right;
    return strcmp(a->path, b->path);
}

static void alderhost_cleanup(struct AlderHostContext *context) {
    uint64_t i;
    for (i = 0; i < context->source_count; i++) {
        free(context->sources[(size_t)i].text);
        if (context->sources[(size_t)i].owned_path) {
            free((void *)context->sources[(size_t)i].path);
        }
    }
    free(context->sources);
    free(context->manifest);
    free(context->source_request);
    free(context->project_paths[0]);
    free(context->project_paths[1]);
    free(context->project_path_request);
    free(context->response);
    free(context->artifact_temp);
}

static bool alderhost_valid_logical_path(const char *path) {
    const char *component = path;
    const char *at = path;
    if (*path == '\0' || *path == '/' || strchr(path, '\\') != NULL ||
        strchr(path, ':') != NULL) {
        return false;
    }
    for (;;) {
        if (*at == '/' || *at == '\0') {
            size_t length = (size_t)(at - component);
            if (length == 0 || (length == 1 && component[0] == '.') ||
                (length == 2 && component[0] == '.' && component[1] == '.')) {
                return false;
            }
            if (*at == '\0') {
                return true;
            }
            component = at + 1;
        }
        at++;
    }
}

static bool alderhost_make_parents(const char *path) {
    char *copy = (char *)malloc(strlen(path) + (size_t)1);
    char *at;
    if (copy == NULL) { return false; }
    (void)strcpy(copy, path);
    for (at = copy; *at != '\0'; at++) {
        if (*at == '/') {
            int made;
            *at = '\0';
#ifdef _WIN32
            made = _mkdir(copy);
#else
            made = mkdir(copy, (mode_t)0777);
#endif
            if (made != 0 && errno != EEXIST) { free(copy); return false; }
            *at = '/';
        }
    }
    free(copy);
    return true;
}

static bool alderhost_al_extension(const char *path) {
    size_t length = strlen(path);
    return length >= (size_t)3 && strcmp(path + length - (size_t)3, ".al") == 0;
}

bool alderhost_sources_sort(void) {
    struct AlderHostContext *context = alderhost_active_context;
    if (context == NULL || !context->project_mode) {
        return false;
    }
    if (context->source_count > UINT64_C(1)) {
        qsort(context->sources, (size_t)context->source_count,
              sizeof(*context->sources), alderhost_compare_paths);
    }
    return true;
}

bool alderhost_source_request_reset(void) {
    if (alderhost_active_context == NULL || !alderhost_active_context->project_mode) {
        return false;
    }
    alderhost_active_context->source_request_len = 0;
    return true;
}

bool alderhost_project_output_reset(uint64_t kind) {
    struct AlderHostContext *context = alderhost_active_context;
    if (context == NULL || !context->project_mode ||
        (context->project_action != UINT64_C(2) && context->project_action != UINT64_C(3)) ||
        (kind != UINT64_C(1) && kind != UINT64_C(2))) {
        return false;
    }
    context->project_path_kind = kind;
    context->project_path_request_len = 0;
    return true;
}

bool alderhost_project_output_byte(uint8_t byte) {
    struct AlderHostContext *context = alderhost_active_context;
    char *grown;
    size_t next;
    if (context == NULL || context->project_path_kind == UINT64_C(0) || byte == UINT8_C(0)) {
        return false;
    }
    if (context->project_path_request_len == context->project_path_request_capacity) {
        next = context->project_path_request_capacity == 0 ? (size_t)64 :
               context->project_path_request_capacity * (size_t)2;
        if (next < context->project_path_request_capacity) { return false; }
        grown = (char *)realloc(context->project_path_request, next);
        if (grown == NULL) { return false; }
        context->project_path_request = grown;
        context->project_path_request_capacity = next;
    }
    context->project_path_request[context->project_path_request_len++] = (char)byte;
    return true;
}

bool alderhost_project_output_finish(void) {
    struct AlderHostContext *context = alderhost_active_context;
    char *path;
    size_t slot;
    if (context == NULL || context->project_path_kind == UINT64_C(0) ||
        context->project_path_request_len == 0 || context->project_path_request_len == SIZE_MAX) {
        return false;
    }
    path = (char *)malloc(context->project_path_request_len + (size_t)1);
    if (path == NULL) { return false; }
    (void)memcpy(path, context->project_path_request, context->project_path_request_len);
    path[context->project_path_request_len] = '\0';
    if (!alderhost_valid_logical_path(path) || strncmp(path, "build/", (size_t)6) != 0) {
        free(path);
        return false;
    }
    if (!alderhost_make_parents(path)) { free(path); return false; }
    slot = (size_t)(context->project_path_kind - UINT64_C(1));
    free(context->project_paths[slot]);
    context->project_paths[slot] = path;
    if (slot == (size_t)0) {
        context->output_path = path;
        context->output_path_len = (uint64_t)context->project_path_request_len;
    }
    context->project_path_kind = UINT64_C(0);
    return true;
}

bool alderhost_project_target_kind(uint64_t kind) {
    struct AlderHostContext *context = alderhost_active_context;
    if (context == NULL || !context->project_mode ||
        (context->project_action != UINT64_C(2) && context->project_action != UINT64_C(3)) ||
        (kind != UINT64_C(1) && kind != UINT64_C(2))) {
        return false;
    }
    context->project_target_kind = kind;
    return true;
}

uint64_t alderhost_project_selected_kind(void) {
    if (alderhost_active_context == NULL || !alderhost_active_context->project_mode) {
        return UINT64_C(0);
    }
    return alderhost_active_context->project_target_kind;
}

bool alderhost_project_entry_source_set(uint64_t source) {
    struct AlderHostContext *context = alderhost_active_context;
    if (context == NULL || !context->project_mode || source == UINT64_C(0) ||
        source > context->source_count) {
        return false;
    }
    context->project_entry_source = source;
    return true;
}

uint64_t alderhost_project_entry_source(void) {
    if (alderhost_active_context == NULL || !alderhost_active_context->project_mode) {
        return UINT64_C(0);
    }
    return alderhost_active_context->project_entry_source;
}

bool alderhost_source_request_byte(uint8_t byte) {
    struct AlderHostContext *context = alderhost_active_context;
    char *grown;
    size_t next;
    if (context == NULL || !context->project_mode || byte == UINT8_C(0)) {
        return false;
    }
    if (context->source_request_len == context->source_request_capacity) {
        next = context->source_request_capacity == 0 ? (size_t)64 : context->source_request_capacity * (size_t)2;
        if (next < context->source_request_capacity) { return false; }
        grown = (char *)realloc(context->source_request, next);
        if (grown == NULL) { return false; }
        context->source_request = grown;
        context->source_request_capacity = next;
    }
    context->source_request[context->source_request_len++] = (char)byte;
    return true;
}

static bool alderhost_option(const char *arg, const char *name,
                             const char **inline_value) {
    size_t length = strlen(name);
    if ((arg[0] == '-' && arg[1] == '-' &&
         strncmp(arg + 2, name, length) == 0) ||
        (arg[0] == '-' && strncmp(arg + 1, name, length) == 0)) {
        const char *rest = arg + (arg[1] == '-' ? 2 : 1) + length;
        if (*rest == '\0') {
            *inline_value = NULL;
            return true;
        }
        if (*rest == '=') {
            *inline_value = rest + 1;
            return true;
        }
    }
    return false;
}

static bool alderhost_wants_json(int argc, char **argv) {
    int i;
    const char *value;
    bool json = false;
    for (i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) {
            break;
        }
        if (alderhost_option(argv[i], "format", &value)) {
            if (value == NULL && i + 1 < argc) {
                value = argv[++i];
            }
            if (value != NULL) {
                json = strcmp(value, "json") == 0;
            }
        }
    }
    return json;
}

static int alderhost_fail(uint64_t command, bool json, int status,
                          const char *kind, const char *message) {
    if (json) {
        const char *command_name = command == UINT64_C(1) ? "check" :
                                   command == UINT64_C(2) || command == UINT64_C(3) ? "compile" : "";
        if (fprintf(stdout,
                    "{\"version\":1,\"command\":\"%s\",\"success\":false,"
                    "\"diagnostics\":[],\"failure\":{\"kind\":\"%s\","
                    "\"message\":\"%s\"}}\n",
                    command_name, kind, message) < 0 || fflush(stdout) != 0) {
            return 3;
        }
    } else {
        if (fprintf(stderr, "alder: %s\n", message) < 0 || fflush(stderr) != 0) {
            return 3;
        }
    }
    return status;
}

static int alderhost_parse_request(int argc, char **argv,
                                   struct AlderHostContext *context) {
    const char *format = "human";
    const char *emit = "c";
    const char *value;
    bool options = true;
    bool profile_set = false;
    size_t source_count = 0;
    int i;

    context->json = alderhost_wants_json(argc, argv);
    if (argc < 2) {
        return alderhost_fail(0, context->json, 2, "usage",
                              "usage: alder check|compile [options] <file.al>...");
    }
    if (strcmp(argv[1], "check") == 0) {
        context->command = UINT64_C(1);
        context->project_action = UINT64_C(1);
    } else if (strcmp(argv[1], "compile") == 0) {
        context->command = UINT64_C(3);
    } else if (strcmp(argv[1], "build") == 0) {
        context->command = UINT64_C(3);
        context->project_action = UINT64_C(2);
    } else if (strcmp(argv[1], "run") == 0) {
        context->command = UINT64_C(3);
        context->project_action = UINT64_C(3);
    } else if (strcmp(argv[1], "test-plan") == 0) {
        context->command = UINT64_C(3);
        context->project_action = UINT64_C(4);
    } else {
        return alderhost_fail(0, context->json, 2, "usage",
                              "usage: alder check|compile|build|run|test-plan [options] [file.al ...]");
    }
    context->sources = (struct AlderHostSource *)calloc(
        argc > 2 ? (size_t)(argc - 2) : (size_t)1, sizeof(*context->sources));
    if (context->sources == NULL) {
        return alderhost_fail(context->command, context->json, 3, "io",
                              "cannot allocate source list");
    }
    for (i = 2; i < argc; i++) {
        const char *arg = argv[i];
        if (options && strcmp(arg, "--") == 0) {
            if (context->project_action == UINT64_C(3) && source_count == 0) {
                context->run_args = &argv[i + 1];
                context->run_arg_count = (size_t)(argc - i - 1);
                break;
            }
            options = false;
            continue;
        }
        if (options && arg[0] == '-') {
            if (strcmp(arg, "--release") == 0) {
                if (profile_set) {
                    return alderhost_fail(context->command, context->json, 2, "usage", "profile specified more than once");
                }
                context->profile = "release";
                profile_set = true;
                continue;
            }
            if (alderhost_option(arg, "format", &value)) {
                if (value == NULL) {
                    if (++i >= argc) {
                        return alderhost_fail(context->command, context->json, 2,
                                              "usage", "invalid command options");
                    }
                    value = argv[i];
                }
                format = value;
                context->json = strcmp(format, "json") == 0;
                continue;
            }
            if (alderhost_option(arg, "target", &value) ||
                alderhost_option(arg, "profile", &value) ||
                alderhost_option(arg, "triple", &value)) {
                const char **slot = alderhost_option(arg, "target", &value) ? &context->target :
                                    alderhost_option(arg, "profile", &value) ? &context->profile : &context->triple;
                if (value == NULL && ++i < argc) { value = argv[i]; }
                if (value == NULL || *value == '\0') {
                    return alderhost_fail(context->command, context->json, 2, "usage", "invalid command options");
                }
                if (slot == &context->profile) {
                    if (profile_set) {
                        return alderhost_fail(context->command, context->json, 2, "usage", "profile specified more than once");
                    }
                    profile_set = true;
                }
                *slot = value;
                continue;
            }
            if (alderhost_option(arg, "emit", &value)) {
                if (context->command == UINT64_C(1)) {
                    return alderhost_fail(context->command, context->json, 2,
                                          "usage", "invalid command options");
                }
                if (value == NULL) {
                    if (++i >= argc) {
                        return alderhost_fail(context->command, context->json, 2,
                                              "usage", "invalid command options");
                    }
                    value = argv[i];
                }
                emit = value;
                continue;
            }
            if (alderhost_option(arg, "o", &value)) {
                if (context->command == UINT64_C(1)) {
                    return alderhost_fail(context->command, context->json, 2,
                                          "usage", "invalid command options");
                }
                if (value == NULL) {
                    if (++i >= argc) {
                        return alderhost_fail(context->command, context->json, 2,
                                              "usage", "invalid command options");
                    }
                    value = argv[i];
                }
                context->output_path = value;
                continue;
            }
            return alderhost_fail(context->command, context->json, 2, "usage",
                                  "invalid command options");
        }
        options = false;
        context->sources[source_count++].path = arg;
    }
    if (strcmp(format, "human") != 0 && strcmp(format, "json") != 0) {
        return alderhost_fail(context->command, context->json, 2, "usage",
                              "format must be human or json");
    }
    if (source_count == 0) {
        if (context->project_action == UINT64_C(0)) {
            return alderhost_fail(context->command, context->json, 2, "usage",
                                  "at least one input file is required");
        }
        if (context->json && (context->project_action == UINT64_C(2) ||
                              context->project_action == UINT64_C(3))) {
            return alderhost_fail(context->command, context->json, 2, "usage",
                                  "JSON format is not supported for build or run");
        }
        if (context->triple != NULL && strcmp(context->triple, "host") != 0 &&
            strcmp(context->triple, ALDER_HOST_TRIPLE) != 0) {
            return alderhost_fail(context->command, context->json, 2, "request",
                                  "requested target triple is not supported by this compiler");
        }
        context->triple = ALDER_HOST_TRIPLE;
        context->project_mode = true;
        return 0;
    }
    if (context->project_action != UINT64_C(0) && context->project_action != UINT64_C(1)) {
        return alderhost_fail(context->command, context->json, 2, "usage",
                              "project commands do not accept explicit source files");
    }
    context->project_action = UINT64_C(0);
    if (context->command != UINT64_C(1)) {
        if (strcmp(emit, "mir") == 0) {
            context->command = UINT64_C(2);
        } else if (strcmp(emit, "c") != 0) {
            return alderhost_fail(context->command, context->json, 2, "request",
                                  "emit must be mir or c");
        }
    }
    for (i = 0; i < (int)source_count; i++) {
        struct AlderHostSource *source = &context->sources[(size_t)i];
        if (!alderhost_al_extension(source->path)) {
            return alderhost_fail(context->command, context->json, 2, "request",
                                  "inputs must have the case-sensitive .al extension");
        }
        if (!alderhost_valid_logical_path(source->path) ||
            !alderhost_size_to_u64(strlen(source->path), &source->path_len)) {
            return alderhost_fail(context->command, context->json, 2, "request",
                                  "inputs must be canonical workspace-relative slash paths");
        }
    }
    if (context->output_path != NULL &&
        (!alderhost_valid_logical_path(context->output_path) ||
         !alderhost_size_to_u64(strlen(context->output_path),
                                &context->output_path_len))) {
        return alderhost_fail(context->command, context->json, 2, "request",
                              "output must be a canonical workspace-relative slash path");
    }
    context->source_count = (uint64_t)source_count;
    context->source_capacity = argc > 2 ? (size_t)(argc - 2) : (size_t)1;
    if (source_count > (size_t)1) {
        qsort(context->sources, source_count, sizeof(*context->sources),
              alderhost_compare_paths);
    }
    for (i = 1; i < (int)source_count; i++) {
        if (strcmp(context->sources[(size_t)i - (size_t)1].path,
                   context->sources[(size_t)i].path) == 0) {
            return alderhost_fail(context->command, context->json, 2, "request",
                                  "duplicate input path");
        }
    }
    return 0;
}

#ifdef ALDER_HOST_CONFORMANCE
static int alderhost_parse_conformance(int argc, char **argv,
                                       struct AlderHostContext *context) {
    size_t count = argc > 1 ? (size_t)(argc - 1) : (size_t)0;
    size_t i;
    context->command = UINT64_C(2);
    context->sources = (struct AlderHostSource *)calloc(
        count != 0 ? count : (size_t)1, sizeof(*context->sources));
    if (context->sources == NULL) {
        (void)fputs("alder host: cannot allocate source list\n", stderr);
        return EXIT_FAILURE;
    }
    if (!alderhost_size_to_u64(count, &context->source_count)) {
        (void)fputs("alder host: too many sources\n", stderr);
        return EXIT_FAILURE;
    }
    for (i = 0; i < count; i++) {
        context->sources[i].path = argv[i + (size_t)1];
        if (!alderhost_size_to_u64(strlen(context->sources[i].path),
                                   &context->sources[i].path_len)) {
            (void)fputs("alder host: source path too large\n", stderr);
            return EXIT_FAILURE;
        }
    }
    if (count > (size_t)1) {
        qsort(context->sources, count, sizeof(*context->sources),
              alderhost_compare_paths);
    }
    for (i = 1; i < count; i++) {
        if (strcmp(context->sources[i - (size_t)1].path,
                   context->sources[i].path) == 0) {
            (void)fprintf(stderr, "alder host: duplicate source: %s\n",
                          context->sources[i].path);
            return EXIT_FAILURE;
        }
    }
    return 0;
}
#endif

static bool alderhost_load(struct AlderHostSource *source) {
    FILE *file = fopen(source->path, "rb");
    uint8_t *data = NULL;
    size_t length = 0;
    size_t capacity = 0;
    if (file == NULL) {
#ifdef ALDER_HOST_CONFORMANCE
        (void)fprintf(stderr, "alder host: cannot open source: %s\n",
                      source->path);
#endif
        return false;
    }
    for (;;) {
        size_t available;
        size_t got;
        if (length == capacity) {
            size_t next = capacity == 0 ? (size_t)4096 : capacity * (size_t)2;
            uint64_t represented;
            uint8_t *grown;
            if (next < capacity || next > SIZE_MAX - (size_t)1 ||
                !alderhost_size_to_u64(next, &represented)) {
#ifdef ALDER_HOST_CONFORMANCE
                (void)fprintf(stderr, "alder host: source too large: %s\n",
                              source->path);
#endif
                free(data);
                (void)fclose(file);
                return false;
            }
            grown = (uint8_t *)realloc(data, next);
            if (grown == NULL) {
#ifdef ALDER_HOST_CONFORMANCE
                (void)fprintf(stderr, "alder host: cannot load source: %s\n",
                              source->path);
#endif
                free(data);
                (void)fclose(file);
                return false;
            }
            data = grown;
            capacity = next;
        }
        available = capacity - length;
        got = fread(data + length, (size_t)1, available, file);
        length += got;
        if (got < available) {
            if (ferror(file) != 0) {
#ifdef ALDER_HOST_CONFORMANCE
                (void)fprintf(stderr, "alder host: cannot read source: %s\n",
                              source->path);
#endif
                free(data);
                (void)fclose(file);
                return false;
            }
            break;
        }
    }
    if (fclose(file) != 0) {
#ifdef ALDER_HOST_CONFORMANCE
        (void)fprintf(stderr, "alder host: cannot read source: %s\n",
                      source->path);
#endif
        free(data);
        return false;
    }
    if (!alderhost_size_to_u64(length, &source->text_len)) {
#ifdef ALDER_HOST_CONFORMANCE
        (void)fprintf(stderr, "alder host: source too large: %s\n",
                      source->path);
#endif
        free(data);
        return false;
    }
    source->text = data;
    return true;
}

uint64_t alderhost_source_request_finish(void) {
    struct AlderHostContext *context = alderhost_active_context;
    struct AlderHostSource *grown;
    struct AlderHostSource *source;
    char *path;
    uint64_t i;
    size_t next;
    if (context == NULL || !context->project_mode || context->source_request_len == 0 ||
        context->source_request_len == SIZE_MAX) {
        return UINT64_C(0);
    }
    path = (char *)malloc(context->source_request_len + (size_t)1);
    if (path == NULL) { return UINT64_C(0); }
    (void)memcpy(path, context->source_request, context->source_request_len);
    path[context->source_request_len] = '\0';
    if (!alderhost_valid_logical_path(path) || !alderhost_al_extension(path)) {
        free(path);
        return UINT64_C(0);
    }
    for (i = 0; i < context->source_count; i++) {
        if (strcmp(context->sources[(size_t)i].path, path) == 0) {
            free(path);
            return i + UINT64_C(1);
        }
    }
    if (context->source_count == UINT64_MAX) { free(path); return UINT64_C(0); }
    if ((size_t)context->source_count == context->source_capacity) {
        next = context->source_capacity == 0 ? (size_t)4 : context->source_capacity * (size_t)2;
        if (next < context->source_capacity) { free(path); return UINT64_C(0); }
        grown = (struct AlderHostSource *)realloc(context->sources, next * sizeof(*grown));
        if (grown == NULL) { free(path); return UINT64_C(0); }
        context->sources = grown;
        context->source_capacity = next;
    }
    source = &context->sources[(size_t)context->source_count];
    (void)memset(source, 0, sizeof(*source));
    source->path = path;
    source->owned_path = true;
    if (!alderhost_size_to_u64(context->source_request_len, &source->path_len) ||
        !alderhost_load(source)) {
        free(path);
        (void)memset(source, 0, sizeof(*source));
        return UINT64_C(0);
    }
    context->source_count++;
    return context->source_count;
}

#ifndef ALDER_HOST_CONFORMANCE
static int alderhost_wait_argv(char *const argv[]) {
#ifdef _WIN32
    intptr_t result = _spawnvp(_P_WAIT, argv[0], (const char *const *)argv);
    return result < 0 || result > INT_MAX ? -1 : (int)result;
#else
    pid_t child = fork();
    int status;
    if (child < (pid_t)0) { return -1; }
    if (child == (pid_t)0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    while (waitpid(child, &status, 0) < (pid_t)0) {
        if (errno != EINTR) { return -1; }
    }
    if (WIFEXITED(status)) { return WEXITSTATUS(status); }
    if (WIFSIGNALED(status)) { return 128 + WTERMSIG(status); }
    return -1;
#endif
}

static bool alderhost_replace(const char *from, const char *to) {
#ifdef _WIN32
    return MoveFileExA(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
    return rename(from, to) == 0;
#endif
}

static int alderhost_native_build(struct AlderHostContext *context, bool *built) {
    const char driver_text[] = "#include <stdint.h>\nextern int32_t alder_program_entry(void *);\nint main(void){int context=0;return (int)alder_program_entry(&context);}\n";
    char *binary_temp;
    char *driver_temp;
    FILE *driver;
    int count;
    int result;
    size_t binary_size;
    size_t driver_size;
    char *compile_argv[22];
    char **run_argv;
    *built = false;
    if (context->project_paths[0] == NULL || context->project_paths[1] == NULL) { return -1; }
    binary_size = strlen(context->project_paths[1]) + sizeof(".alder-tmp-bin");
    driver_size = strlen(context->project_paths[0]) + sizeof(".alder-driver.c");
    binary_temp = (char *)malloc(binary_size);
    driver_temp = (char *)malloc(driver_size);
    if (binary_temp == NULL || driver_temp == NULL) { free(binary_temp); free(driver_temp); return -1; }
    count = snprintf(binary_temp, binary_size, "%s.alder-tmp-bin", context->project_paths[1]);
    if (count < 0 || (size_t)count >= binary_size) { free(binary_temp); free(driver_temp); return -1; }
    count = snprintf(driver_temp, driver_size, "%s.alder-driver.c", context->project_paths[0]);
    if (count < 0 || (size_t)count >= driver_size) { free(binary_temp); free(driver_temp); return -1; }
    (void)remove(binary_temp);
    compile_argv[0] = (char *)ALDER_HOST_CC;
    compile_argv[1] = "-std=c11"; compile_argv[2] = "-Wall"; compile_argv[3] = "-Wextra";
    compile_argv[4] = "-Werror"; compile_argv[5] = "-pedantic"; compile_argv[6] = "-Wshadow";
    compile_argv[7] = "-Wconversion"; compile_argv[8] = "-I"; compile_argv[9] = (char *)ALDER_HOST_RUNTIME_INCLUDE_DIR;
    compile_argv[10] = "-I"; compile_argv[11] = (char *)ALDER_HOST_INCLUDE_DIR;
    compile_argv[12] = context->profile != NULL && strcmp(context->profile, "release") == 0 ? "-O2" : "-O0";
    compile_argv[13] = "-x"; compile_argv[14] = "c";
    compile_argv[15] = context->artifact_temp != NULL ? context->artifact_temp : context->project_paths[0];
    if (context->project_target_kind == UINT64_C(2)) {
        compile_argv[16] = "-c"; compile_argv[17] = "-o";
        compile_argv[18] = binary_temp; compile_argv[19] = NULL;
    } else {
        driver = fopen(driver_temp, "wb");
        if (driver == NULL || fwrite(driver_text, (size_t)1, sizeof(driver_text) - (size_t)1, driver) != sizeof(driver_text) - (size_t)1) {
            if (driver != NULL) { (void)fclose(driver); }
            (void)remove(driver_temp); free(binary_temp); free(driver_temp); return -1;
        }
        if (fclose(driver) != 0) {
            (void)remove(driver_temp); free(binary_temp); free(driver_temp); return -1;
        }
        compile_argv[16] = (char *)ALDER_HOST_RUNTIME_C; compile_argv[17] = driver_temp;
        compile_argv[18] = "-o"; compile_argv[19] = binary_temp; compile_argv[20] = NULL;
    }
    result = alderhost_wait_argv(compile_argv);
    (void)remove(driver_temp);
    if (result != 0 || !alderhost_replace(binary_temp, context->project_paths[1])) {
        (void)remove(binary_temp); free(binary_temp); free(driver_temp); return result == 0 ? -1 : result;
    }
    *built = true;
    free(binary_temp); free(driver_temp);
    if (context->project_action == UINT64_C(3)) {
        size_t at;
        int run_status;
        if (context->run_arg_count > (SIZE_MAX / sizeof(*run_argv)) - (size_t)2) { return -1; }
        run_argv = (char **)malloc((context->run_arg_count + (size_t)2) * sizeof(*run_argv));
        if (run_argv == NULL) { return -1; }
        run_argv[0] = context->project_paths[1];
        for (at = 0; at < context->run_arg_count; at++) { run_argv[at + (size_t)1] = context->run_args[at]; }
        run_argv[context->run_arg_count + (size_t)1] = NULL;
        run_status = alderhost_wait_argv(run_argv);
        free(run_argv);
        return run_status;
    }
    return 0;
}
#endif

int main(int argc, char **argv) {
    struct AlderHostContext context = {0};
    uint64_t i;
    int status;
    bool flush_ok = true;
#ifndef ALDER_HOST_CONFORMANCE
    bool native_built = false;
    bool propagate_run_status = false;
#endif
    if (!alderhost_configure_stack()) {
        (void)fputs("alder host: cannot configure compiler stack\n", stderr);
        return 3;
    }
#ifdef _WIN32
    if (_setmode(_fileno(stdout), _O_BINARY) == -1 ||
        _setmode(_fileno(stderr), _O_BINARY) == -1) {
        (void)fputs("alder host: cannot configure binary output\n", stderr);
#ifdef ALDER_HOST_CONFORMANCE
        return EXIT_FAILURE;
#else
        return 3;
#endif
    }
#endif
#ifdef ALDER_HOST_CONFORMANCE
    (void)alderhost_parse_request;
    status = alderhost_parse_conformance(argc, argv, &context);
#else
    status = alderhost_parse_request(argc, argv, &context);
#endif
    if (status != 0) {
        alderhost_cleanup(&context);
        return status;
    }
    if (context.project_mode) {
        struct AlderHostSource manifest = {0};
        manifest.path = "alder.toml";
        if (!alderhost_load(&manifest)) {
            alderhost_cleanup(&context);
            return alderhost_fail(context.command, context.json, 3, "io",
                                  "cannot read alder.toml");
        }
        context.manifest = manifest.text;
        context.manifest_len = manifest.text_len;
    }
    for (i = 0; i < context.source_count; i++) {
        if (!alderhost_load(&context.sources[(size_t)i])) {
#ifdef ALDER_HOST_CONFORMANCE
            alderhost_cleanup(&context);
            return EXIT_FAILURE;
#else
            alderhost_cleanup(&context);
            return alderhost_fail(context.command, context.json, 3, "io",
                                  "cannot read input file");
#endif
        }
    }
    alderhost_active_context = &context;
    status = (int)alder_program_entry((void *)&context);
    alderhost_active_context = NULL;

#ifdef ALDER_HOST_CONFORMANCE
    flush_ok = fflush(stdout) == 0;
    flush_ok = fflush(stderr) == 0 && flush_ok;
    alderhost_cleanup(&context);
    return status == 0 && flush_ok ? EXIT_SUCCESS : EXIT_FAILURE;
#else
    if (status != 0 && !context.response_started) {
        context.response_len = 0;
        if (status == 3 && context.output_failed) {
            status = alderhost_fail(context.command, context.json, 3, "io",
                                    "cannot write compiler output");
        } else {
            status = alderhost_fail(context.command, context.json, 4, "internal",
                                    "internal compiler failure");
        }
    }

    if (context.artifact != NULL) {
        flush_ok = fflush(context.artifact) == 0;
        flush_ok = fclose(context.artifact) == 0 && flush_ok;
        context.artifact = NULL;
        if (status == 0 && flush_ok &&
            !(context.project_mode && (context.project_action == UINT64_C(2) ||
                                        context.project_action == UINT64_C(3)))) {
            if (rename(context.artifact_temp, context.output_path) != 0) {
                flush_ok = false;
            }
        }
        if (status != 0 || !flush_ok) {
            (void)remove(context.artifact_temp);
        }
    }
    if (!flush_ok) {
        status = 3;
        context.response_len = 0;
        (void)alderhost_fail(context.command, context.json, 3, "io",
                             "cannot write output file");
    } else if (status == 0 && context.project_mode &&
               (context.project_action == UINT64_C(2) || context.project_action == UINT64_C(3))) {
        status = alderhost_native_build(&context, &native_built);
        propagate_run_status = native_built && context.project_action == UINT64_C(3);
        if (!native_built) {
            if (context.artifact_temp != NULL) { (void)remove(context.artifact_temp); }
            context.response_len = 0;
            status = alderhost_fail(context.command, context.json, 3, "io",
                                    "native C11 build failed");
        } else if (!alderhost_replace(context.artifact_temp, context.output_path)) {
            status = alderhost_fail(context.command, context.json, 3, "io",
                                    "cannot commit generated C output");
        }
    }
    if (context.json && context.response_len != 0 && !propagate_run_status) {
        if (fwrite(context.response, (size_t)1, context.response_len, stdout) !=
            context.response_len) {
            status = 3;
        }
    }
    if (fflush(stdout) != 0 || fflush(stderr) != 0) {
        status = 3;
    }
    alderhost_cleanup(&context);
    if (propagate_run_status) {
        return status < 0 ? 3 : status;
    }
    if (status < 0 || status > 4) {
        return 4;
    }
    return status;
#endif
}
