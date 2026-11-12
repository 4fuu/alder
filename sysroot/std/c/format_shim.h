/*
 * Toolchain-owned float formatting shim for std.format.
 *
 * C's printf rounds a binary value to decimal, but the spelling depends on the
 * ambient numeric locale and %g alone does not promise the shortest text that
 * round-trips. This helper runs snprintf/strtod (or snprintf/strtof) under a
 * per-thread C numeric locale, finds the shortest round-tripping general form,
 * and writes only ASCII with a '.' decimal point. Fixed and scientific styles
 * use their explicit precision. NaN and infinities are spelled nan/inf; a
 * negative zero keeps its sign.
 *
 * Names stay outside the reserved alder_/Alder_/ALDER_ prefix.
 */
#ifndef FORMAT_SHIM_H
#define FORMAT_SHIM_H

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE 1
#endif

#include <locale.h>
#include <float.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <locale.h>
#endif

static inline int format_copy_text(const char *text, unsigned char *out, size_t capacity) {
    size_t length = strlen(text);
    if (length >= capacity) { return -1; }
    if (length != 0) { memcpy(out, text, length); }
    return (int)length;
}

#if defined(_WIN32)

static inline int format_f64_bits(uint64_t bits, int precision, int style,
                                  unsigned char *out, size_t capacity) {
    double value;
    _locale_t locale;
    char text[256];
    int written;
    memcpy(&value, &bits, sizeof value);
    locale = _create_locale(LC_NUMERIC, "C");
    if (locale == NULL) { return -1; }
    if (value != value) { written = snprintf(text, sizeof text, "nan"); }
    else if (value > DBL_MAX || value < -DBL_MAX) { written = snprintf(text, sizeof text, value < 0.0 ? "-inf" : "inf"); }
    else if (style == 0) {
        int p;
        written = -1;
        for (p = 1; p <= 17; p++) {
            char candidate[256];
            int count = _snprintf_l(candidate, sizeof candidate, "%.*g", locale, p, value);
            if (count > 0 && (size_t)count < sizeof candidate) {
                double parsed = _strtod_l(candidate, NULL, locale);
                uint64_t parsed_bits;
                memcpy(&parsed_bits, &parsed, sizeof parsed_bits);
                if (parsed_bits == bits) {
                    memcpy(text, candidate, (size_t)count + 1);
                    written = count;
                    break;
                }
            }
        }
        if (written < 0) { written = _snprintf_l(text, sizeof text, "%.*g", locale, 17, value); }
    } else if (style == 1) {
        written = _snprintf_l(text, sizeof text, "%.*f", locale, precision < 0 ? 6 : precision, value);
    } else {
        written = _snprintf_l(text, sizeof text, "%.*e", locale, precision < 0 ? 6 : precision, value);
    }
    _free_locale(locale);
    if (written < 0 || (size_t)written >= sizeof text) { return -1; }
    return format_copy_text(text, out, capacity);
}

static inline int format_f32_bits(uint32_t bits, int precision, int style,
                                  unsigned char *out, size_t capacity) {
    float value;
    _locale_t locale;
    char text[256];
    int written;
    memcpy(&value, &bits, sizeof value);
    locale = _create_locale(LC_NUMERIC, "C");
    if (locale == NULL) { return -1; }
    if (value != value) { written = snprintf(text, sizeof text, "nan"); }
    else if (value > DBL_MAX || value < -DBL_MAX) { written = snprintf(text, sizeof text, value < 0.0 ? "-inf" : "inf"); }
    else if (style == 0) {
        int p;
        written = -1;
        for (p = 1; p <= 9; p++) {
            char candidate[256];
            int count = _snprintf_l(candidate, sizeof candidate, "%.*g", locale, p, (double)value);
            if (count > 0 && (size_t)count < sizeof candidate) {
                float parsed = (float)_strtod_l(candidate, NULL, locale);
                uint32_t parsed_bits;
                memcpy(&parsed_bits, &parsed, sizeof parsed_bits);
                if (parsed_bits == bits) {
                    memcpy(text, candidate, (size_t)count + 1);
                    written = count;
                    break;
                }
            }
        }
        if (written < 0) { written = _snprintf_l(text, sizeof text, "%.*g", locale, 9, (double)value); }
    } else if (style == 1) {
        written = _snprintf_l(text, sizeof text, "%.*f", locale, precision < 0 ? 6 : precision, (double)value);
    } else {
        written = _snprintf_l(text, sizeof text, "%.*e", locale, precision < 0 ? 6 : precision, (double)value);
    }
    _free_locale(locale);
    if (written < 0 || (size_t)written >= sizeof text) { return -1; }
    return format_copy_text(text, out, capacity);
}

static inline int format_f64(double value, int precision, int style,
                             unsigned char *out, size_t capacity) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    return format_f64_bits(bits, precision, style, out, capacity);
}

static inline int format_f32(float value, int precision, int style,
                             unsigned char *out, size_t capacity) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    return format_f32_bits(bits, precision, style, out, capacity);
}

#else

static inline int format_f64_bits(uint64_t bits, int precision, int style,
                                  unsigned char *out, size_t capacity) {
    double value;
    locale_t c_locale;
    locale_t previous;
    char text[256];
    int written;
    memcpy(&value, &bits, sizeof value);
    c_locale = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
    if (c_locale == (locale_t)0) { return -1; }
    previous = uselocale(c_locale);
    if (value != value) { written = snprintf(text, sizeof text, "nan"); }
    else if (value > DBL_MAX || value < -DBL_MAX) { written = snprintf(text, sizeof text, value < 0.0 ? "-inf" : "inf"); }
    else if (style == 0) {
        int p;
        written = -1;
        for (p = 1; p <= 17; p++) {
            char candidate[256];
            int count = snprintf(candidate, sizeof candidate, "%.*g", p, value);
            if (count > 0 && (size_t)count < sizeof candidate) {
                double parsed = strtod(candidate, NULL);
                uint64_t parsed_bits;
                memcpy(&parsed_bits, &parsed, sizeof parsed_bits);
                if (parsed_bits == bits) {
                    memcpy(text, candidate, (size_t)count + 1);
                    written = count;
                    break;
                }
            }
        }
        if (written < 0) { written = snprintf(text, sizeof text, "%.*g", 17, value); }
    } else if (style == 1) {
        written = snprintf(text, sizeof text, "%.*f", precision < 0 ? 6 : precision, value);
    } else {
        written = snprintf(text, sizeof text, "%.*e", precision < 0 ? 6 : precision, value);
    }
    (void)uselocale(previous);
    freelocale(c_locale);
    if (written < 0 || (size_t)written >= sizeof text) { return -1; }
    return format_copy_text(text, out, capacity);
}

static inline int format_f32_bits(uint32_t bits, int precision, int style,
                                  unsigned char *out, size_t capacity) {
    float value;
    locale_t c_locale;
    locale_t previous;
    char text[256];
    int written;
    memcpy(&value, &bits, sizeof value);
    c_locale = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
    if (c_locale == (locale_t)0) { return -1; }
    previous = uselocale(c_locale);
    if (value != value) { written = snprintf(text, sizeof text, "nan"); }
    else if (value > DBL_MAX || value < -DBL_MAX) { written = snprintf(text, sizeof text, value < 0.0 ? "-inf" : "inf"); }
    else if (style == 0) {
        int p;
        written = -1;
        for (p = 1; p <= 9; p++) {
            char candidate[256];
            int count = snprintf(candidate, sizeof candidate, "%.*g", p, (double)value);
            if (count > 0 && (size_t)count < sizeof candidate) {
                float parsed = strtof(candidate, NULL);
                uint32_t parsed_bits;
                memcpy(&parsed_bits, &parsed, sizeof parsed_bits);
                if (parsed_bits == bits) {
                    memcpy(text, candidate, (size_t)count + 1);
                    written = count;
                    break;
                }
            }
        }
        if (written < 0) { written = snprintf(text, sizeof text, "%.*g", 9, (double)value); }
    } else if (style == 1) {
        written = snprintf(text, sizeof text, "%.*f", precision < 0 ? 6 : precision, (double)value);
    } else {
        written = snprintf(text, sizeof text, "%.*e", precision < 0 ? 6 : precision, (double)value);
    }
    (void)uselocale(previous);
    freelocale(c_locale);
    if (written < 0 || (size_t)written >= sizeof text) { return -1; }
    return format_copy_text(text, out, capacity);
}

static inline int format_f64(double value, int precision, int style,
                             unsigned char *out, size_t capacity) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    return format_f64_bits(bits, precision, style, out, capacity);
}

static inline int format_f32(float value, int precision, int style,
                             unsigned char *out, size_t capacity) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    return format_f32_bits(bits, precision, style, out, capacity);
}

#endif

#endif /* FORMAT_SHIM_H */
