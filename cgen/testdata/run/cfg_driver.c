/* Driver for the cfg golden: block parameters, branch arguments, switch
 * bindings, failure-edge arguments, fail, and a dead block. */
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

static AsterTy12 shape(int64_t tag, int64_t payload) {
    AsterTy12 s = {0};
    s.aster_tag = (uint32_t)tag;
    if (tag == 0) {
        s.aster_u.aster_p0 = payload;
    } else if (tag == 1) {
        s.aster_u.aster_p1 = payload;
    }
    return s;
}

int main(void) {
    /* bb_then: p = 5, q = 6. */
    CHECK(aster_fn_cfg_0(true, 5, shape(0, 3)) == 18);   /* Circle: 6 * 3 */
    CHECK(aster_fn_cfg_0(true, 5, shape(1, 4)) == 24);   /* Square: 6 * 4 */
    CHECK(aster_fn_cfg_0(true, 5, shape(2, 0)) == 6);    /* Dot: q */
    /* bb_else: returns the passed zero. */
    CHECK(aster_fn_cfg_0(false, 5, shape(0, 3)) == 0);
    /* Failure edge with an argument: q overflows. */
    CHECK(aster_fn_cfg_0(true, INT64_MAX, shape(2, 0)) == 0);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
