/* String UTF-8 validator tests: alder_string_utf8_valid backs str.from_bytes
 * lowering, so every malformed-shape class must be rejected individually. */
#include "alder.h"

#include <stdint.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

static void test_valid(void) {
    CHECK(alder_string_utf8_valid((const uint8_t *)"", 0));
    {
        uint8_t nul[1] = {0};
        CHECK(alder_string_utf8_valid(nul, 1)); /* embedded NUL is data */
    }
    CHECK(alder_string_utf8_valid((const uint8_t *)"abc", 3));
    {
        /* U+00E9 in two bytes, U+20AC in three, U+1F600 in four. */
        const uint8_t seq[] = {0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80};
        CHECK(alder_string_utf8_valid(seq, 9));
        CHECK(alder_string_utf8_valid(seq, 2));
        CHECK(alder_string_utf8_valid(seq + 2, 3));
        CHECK(alder_string_utf8_valid(seq + 5, 4));
    }
    {
        /* U+07FF boundary minimum of three-byte range: encoded U+07FF. */
        const uint8_t seq[] = {0xDF, 0xBF};
        CHECK(alder_string_utf8_valid(seq, 2));
    }
    {
        /* U+10000 boundary minimum of the four-byte range. */
        const uint8_t seq[] = {0xF0, 0x90, 0x80, 0x80};
        CHECK(alder_string_utf8_valid(seq, 4));
    }
    {
        /* U+10FFFE, one below the maximum code point. */
        const uint8_t seq[] = {0xF4, 0x8F, 0xBF, 0xBE};
        CHECK(alder_string_utf8_valid(seq, 4));
    }
}

static void test_invalid(void) {
    {
        /* Bare continuation bytes and impossible leads. */
        const uint8_t cont[] = {0x80};
        const uint8_t lead[] = {0xF8, 0x80, 0x80, 0x80, 0x80};
        const uint8_t fe[] = {0xFE};
        const uint8_t ff[] = {0xFF};
        CHECK(!alder_string_utf8_valid(cont, 1));
        CHECK(!alder_string_utf8_valid(lead, 5));
        CHECK(!alder_string_utf8_valid(fe, 1));
        CHECK(!alder_string_utf8_valid(ff, 1));
    }
    {
        /* Truncated sequences. */
        const uint8_t two[] = {0xC3};
        const uint8_t three[] = {0xE2, 0x82};
        const uint8_t four[] = {0xF0, 0x9F, 0x98};
        CHECK(!alder_string_utf8_valid(two, 1));
        CHECK(!alder_string_utf8_valid(three, 2));
        CHECK(!alder_string_utf8_valid(four, 3));
    }
    {
        /* Overlong encodings. */
        const uint8_t over2[] = {0xC0, 0x80};       /* NUL overlong */
        const uint8_t over3[] = {0xE0, 0x80, 0x80}; /* U+0000 overlong */
        const uint8_t over4[] = {0xF0, 0x80, 0x80, 0x80};
        CHECK(!alder_string_utf8_valid(over2, 2));
        CHECK(!alder_string_utf8_valid(over3, 3));
        CHECK(!alder_string_utf8_valid(over4, 4));
    }
    {
        /* Surrogate code points and values beyond U+10FFFF. */
        const uint8_t surrogate[] = {0xED, 0xA0, 0x80}; /* U+D800 */
        const uint8_t beyond[] = {0xF4, 0x90, 0x80, 0x80};
        const uint8_t max[] = {0xF7, 0xBF, 0xBF, 0xBF}; /* U+1FFFFF */
        CHECK(!alder_string_utf8_valid(surrogate, 3));
        CHECK(!alder_string_utf8_valid(beyond, 4));
        CHECK(!alder_string_utf8_valid(max, 4));
    }
    {
        /* A valid prefix must not swallow a bad tail. */
        const uint8_t mixed[] = {'a', 0xC3, 0xA9, 0xED, 0xA0, 0x80};
        CHECK(!alder_string_utf8_valid(mixed, 6));
    }
    {
        /* NULL data is valid only for a zero length. */
        CHECK(!alder_string_utf8_valid(NULL, 1));
        CHECK(alder_string_utf8_valid(NULL, 0));
    }
}

int main(void) {
    test_valid();
    test_invalid();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
