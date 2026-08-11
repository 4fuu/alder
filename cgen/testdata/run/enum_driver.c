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
static AsterTy12 make_circle(int64_t r) {
    AsterTy12 s = {0};
    s.aster_tag = (uint32_t)0;
    s.aster_u.aster_p0 = r;
    return s;
}

static AsterTy12 make_square(int64_t t) {
    AsterTy12 s = {0};
    s.aster_tag = (uint32_t)1;
    s.aster_u.aster_p1 = t;
    return s;
}

static AsterTy12 make_dot(void) {
    AsterTy12 s = {0};
    s.aster_tag = (uint32_t)2;
    return s;
}

static int64_t tag_of(AsterTy12 s) { return (int64_t)s.aster_tag; }

int main(void) {
    /* classify: 0 -> Dot, negative -> Circle, positive -> Square. */
    CHECK(tag_of(aster_fn_classify_0(0)) == 2);
    CHECK(tag_of(aster_fn_classify_0(-3)) == 0);
    CHECK(tag_of(aster_fn_classify_0(7)) == 1);

    /* area: Circle(3) -> 9, Square(4) -> 16, Dot -> 0. */
    CHECK(aster_fn_area_1(make_circle(3)) == 9);
    CHECK(aster_fn_area_1(make_square(4)) == 16);
    CHECK(aster_fn_area_1(make_dot()) == 0);

    /* half: even -> some(n/2), odd -> none. The option layout is the same
     * tagged union: tag 0 = none, tag 1 = some(payload in aster_p1). */
    AsterTy13 even = aster_fn_half_2(10);
    CHECK(even.aster_tag == (uint32_t)1);
    CHECK(even.aster_u.aster_p1 == 5);
    AsterTy13 odd = aster_fn_half_2(7);
    CHECK(odd.aster_tag == (uint32_t)0);

    /* checked_div: 10 / 2 -> ok(5); 1 / 0 -> err(Dot). The result layout:
     * tag 0 = ok, tag 1 = err. */
    AsterTy14 ok = aster_fn_checked_div_3(10, 2);
    CHECK(ok.aster_tag == (uint32_t)0);
    CHECK(ok.aster_u.aster_p0 == 5);
    AsterTy14 err = aster_fn_checked_div_3(1, 0);
    CHECK(err.aster_tag == (uint32_t)1);
    CHECK(err.aster_u.aster_p1.aster_tag == (uint32_t)2); /* Dot */

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
