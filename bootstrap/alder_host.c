#include "alder_host.h"

#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

struct AlderHostSource {
    const char *path;
    uint64_t path_len;
    uint8_t *text;
    uint64_t text_len;
};

struct AlderHostContext {
    struct AlderHostSource *sources;
    uint64_t source_count;
};

static struct AlderHostContext *alderhost_active_context;

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

bool alderhost_stdout_byte(uint8_t byte) {
    return alderhost_active_context != NULL && fputc((int)byte, stdout) != EOF;
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
        if (fputc((int)(unsigned char)(byte_), stdout) == EOF) { \
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
    return alderhost_active_context != NULL && fputc((int)byte, stderr) != EOF;
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
    }
    free(context->sources);
}

static bool alderhost_load(struct AlderHostSource *source) {
    FILE *file = fopen(source->path, "rb");
    uint8_t *data = NULL;
    size_t length = 0;
    size_t capacity = 0;
    if (file == NULL) {
        (void)fprintf(stderr, "alder host: cannot open source: %s\n", source->path);
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
                (void)fprintf(stderr, "alder host: source too large: %s\n", source->path);
                free(data);
                (void)fclose(file);
                return false;
            }
            grown = (uint8_t *)realloc(data, next);
            if (grown == NULL) {
                (void)fprintf(stderr, "alder host: cannot load source: %s\n", source->path);
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
                (void)fprintf(stderr, "alder host: cannot read source: %s\n", source->path);
                free(data);
                (void)fclose(file);
                return false;
            }
            break;
        }
    }
    if (fclose(file) != 0) {
        (void)fprintf(stderr, "alder host: cannot read source: %s\n", source->path);
        free(data);
        return false;
    }
    if (!alderhost_size_to_u64(length, &source->text_len)) {
        (void)fprintf(stderr, "alder host: source too large: %s\n", source->path);
        free(data);
        return false;
    }
    source->text = data;
    return true;
}

int main(int argc, char **argv) {
    struct AlderHostContext context = {NULL, 0};
    size_t count = argc > 1 ? (size_t)(argc - 1) : (size_t)0;
    size_t i;
    int32_t status;
    bool flush_ok;
#ifdef _WIN32
    if (_setmode(_fileno(stdout), _O_BINARY) == -1 ||
        _setmode(_fileno(stderr), _O_BINARY) == -1) {
        (void)fputs("alder host: cannot configure binary output\n", stderr);
        return EXIT_FAILURE;
    }
#endif
    if (count > 0) {
        context.sources = (struct AlderHostSource *)calloc(count, sizeof(*context.sources));
        if (context.sources == NULL) {
            (void)fputs("alder host: cannot allocate source list\n", stderr);
            return EXIT_FAILURE;
        }
    }
    if (!alderhost_size_to_u64(count, &context.source_count)) {
        (void)fputs("alder host: too many sources\n", stderr);
        alderhost_cleanup(&context);
        return EXIT_FAILURE;
    }
    for (i = 0; i < count; i++) {
        context.sources[i].path = argv[i + (size_t)1];
        if (!alderhost_size_to_u64(strlen(context.sources[i].path),
                                   &context.sources[i].path_len)) {
            (void)fputs("alder host: source path too large\n", stderr);
            alderhost_cleanup(&context);
            return EXIT_FAILURE;
        }
    }
    if (count > (size_t)1) {
        qsort(context.sources, count, sizeof(*context.sources), alderhost_compare_paths);
    }
    for (i = 1; i < count; i++) {
        if (strcmp(context.sources[i - (size_t)1].path, context.sources[i].path) == 0) {
            (void)fprintf(stderr, "alder host: duplicate source: %s\n", context.sources[i].path);
            alderhost_cleanup(&context);
            return EXIT_FAILURE;
        }
    }
    for (i = 0; i < count; i++) {
        if (!alderhost_load(&context.sources[i])) {
            alderhost_cleanup(&context);
            return EXIT_FAILURE;
        }
    }
    alderhost_active_context = &context;
    status = alder_program_entry((void *)&context);
    alderhost_active_context = NULL;
    flush_ok = fflush(stdout) == 0;
    flush_ok = fflush(stderr) == 0 && flush_ok;
    alderhost_cleanup(&context);
    return status == (int32_t)0 && flush_ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
