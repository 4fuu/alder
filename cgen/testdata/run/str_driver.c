/* Driver for str.mir: the byte-sequence surface. Checks byte-level results
 * (lengths count bytes, not characters), the out-of-range failure edges of
 * str.byte.checked and str.slice.checked, content of str.concat and
 * str.slice.checked results, str.to_bytes reinterpreting a string, and
 * str.from_bytes yielding none on invalid UTF-8. */
#include "gen.c"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

static AlderString str_of(const char *s, uint64_t len) {
    AlderString v;
    v.data = (const uint8_t *)s;
    v.len = len;
    return v;
}

static AlderBytes bytes_of(const char *s, uint64_t len) {
    AlderBytes v;
    v.data = (const uint8_t *)s;
    v.len = len;
    return v;
}

static int has_prefix(AlderString s, const char *p, uint64_t n) {
    return s.len == n && memcmp(s.data, p, (size_t)n) == 0;
}

static int bytes_equal(AlderBytes b, const char *p, uint64_t n) {
    return b.len == n && memcmp(b.data, p, (size_t)n) == 0;
}

int main(void) {
    AlderDomain root = {0};
    CHECK(alder_domain_init(&root, NULL));

    /* len counts bytes: "hello" is 5, "" is 0, "héllo" is 6. */
    CHECK(alder_fn_len_of_0(str_of("hello", 5)) == 5);
    CHECK(alder_fn_len_of_0(str_of("", 0)) == 0);
    CHECK(alder_fn_len_of_0(str_of("h\xc3\xa9llo", 6)) == 6);

    /* byte_of reads the byte at an index; out of range takes the checked
     * edge, which this fixture's fail block turns into 0. */
    CHECK(alder_fn_byte_of_1(str_of("hello", 5), 0) == 'h');
    CHECK(alder_fn_byte_of_1(str_of("hello", 5), 4) == 'o');
    CHECK(alder_fn_byte_of_1(str_of("h\xc3\xa9llo", 6), 1) == 0xc3);
    CHECK(alder_fn_byte_of_1(str_of("hello", 5), 5) == 0);
    CHECK(alder_fn_byte_of_1(str_of("hello", 5), 99) == 0);

    /* cat joins both operands and owns the result bytes. */
    AlderString joined = alder_fn_cat_2(&root, str_of("hello", 5), str_of(" world", 6));
    CHECK(has_prefix(joined, "hello world", 11));
    AlderString joined_bytes = alder_fn_cat_2(&root, str_of("h\xc3\xa9", 3), str_of("y", 1));
    CHECK(has_prefix(joined_bytes, "h\xc3\xa9y", 4));
    AlderString joined_empty = alder_fn_cat_2(&root, str_of("", 0), str_of("", 0));
    CHECK(joined_empty.len == 0);
    CHECK(joined_empty.data != NULL);

    /* cut slices within bounds and takes the checked edge otherwise; this
     * fixture's fail block yields the empty bytes constant. */
    AlderBytes piece = alder_fn_cut_3(&root, bytes_of("abcd", 4), 1, 3);
    CHECK(bytes_equal(piece, "bc", 2));
    AlderBytes whole = alder_fn_cut_3(&root, bytes_of("abcd", 4), 0, 4);
    CHECK(bytes_equal(whole, "abcd", 4));
    AlderBytes empty_range = alder_fn_cut_3(&root, bytes_of("abcd", 4), 2, 2);
    CHECK(empty_range.len == 0);
    CHECK(empty_range.data != NULL);
    CHECK(alder_fn_cut_3(&root, bytes_of("abcd", 4), 3, 1).len == 0); /* lo > hi */
    CHECK(alder_fn_cut_3(&root, bytes_of("abcd", 4), 0, 5).len == 0); /* hi > len */

    /* as_bytes reinterprets the string bytes without copying. */
    AlderBytes view = alder_fn_as_bytes_4(str_of("h\xc3\xa9", 3));
    CHECK(bytes_equal(view, "h\xc3\xa9", 3));

    /* parse validates UTF-8: "h\xc3\xa9" is some, a lone lead byte is none,
     * and "" is some with an owned (non-NULL) pointer. */
    AlderTy15 good = alder_fn_parse_5(&root, bytes_of("h\xc3\xa9", 3));
    CHECK(good.alder_tag == (uint32_t)1);
    CHECK(has_prefix(good.alder_u.alder_p1, "h\xc3\xa9", 3));
    AlderTy15 bad = alder_fn_parse_5(&root, bytes_of("\xc3", 1));
    CHECK(bad.alder_tag == (uint32_t)0);
    AlderTy15 blank = alder_fn_parse_5(&root, bytes_of("", 0));
    CHECK(blank.alder_tag == (uint32_t)1);
    CHECK(has_prefix(blank.alder_u.alder_p1, "", 0));

    alder_domain_destroy(&root);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
