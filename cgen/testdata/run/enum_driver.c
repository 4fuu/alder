/* Driver for enum.mir: enum, option, and result construction, dispatch,
 * payload binding, and payload extraction. */
#include "gen.c"

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

/* The generated @Shape type: tag 0 = Circle(i64), 1 = Square(i64),
 * 2 = Dot. */
static AlderTy12 make_circle(int64_t r) {
    AlderTy12 s = {0};
    s.alder_tag = (uint32_t)0;
    s.alder_u.alder_p0 = r;
    return s;
}

static AlderTy12 make_square(int64_t t) {
    AlderTy12 s = {0};
    s.alder_tag = (uint32_t)1;
    s.alder_u.alder_p1 = t;
    return s;
}

static AlderTy12 make_dot(void) {
    AlderTy12 s = {0};
    s.alder_tag = (uint32_t)2;
    return s;
}

static int64_t tag_of(AlderTy12 s) { return (int64_t)s.alder_tag; }

int main(void) {
    /* classify: 0 -> Dot, negative -> Circle, positive -> Square. */
    CHECK(tag_of(alder_fn_classify_0(0)) == 2);
    CHECK(tag_of(alder_fn_classify_0(-3)) == 0);
    CHECK(tag_of(alder_fn_classify_0(7)) == 1);

    /* area: Circle(3) -> 9, Square(4) -> 16, Dot -> 0. */
    CHECK(alder_fn_area_1(make_circle(3)) == 9);
    CHECK(alder_fn_area_1(make_square(4)) == 16);
    CHECK(alder_fn_area_1(make_dot()) == 0);

    /* half: even -> some(n/2), odd -> none. The option layout is the same
     * tagged union: tag 0 = none, tag 1 = some(payload in alder_p1). */
    AlderTy13 even = alder_fn_half_2(10);
    CHECK(even.alder_tag == (uint32_t)1);
    CHECK(even.alder_u.alder_p1 == 5);
    AlderTy13 odd = alder_fn_half_2(7);
    CHECK(odd.alder_tag == (uint32_t)0);

    /* checked_div: 10 / 2 -> ok(5); 1 / 0 -> err(Dot). The result layout:
     * tag 0 = ok, tag 1 = err. */
    AlderTy14 ok = alder_fn_checked_div_3(10, 2);
    CHECK(ok.alder_tag == (uint32_t)0);
    CHECK(ok.alder_u.alder_p0 == 5);
    AlderTy14 err = alder_fn_checked_div_3(1, 0);
    CHECK(err.alder_tag == (uint32_t)1);
    CHECK(err.alder_u.alder_p1.alder_tag == (uint32_t)2); /* Dot */

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
