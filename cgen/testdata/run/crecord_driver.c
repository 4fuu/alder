/* Driver for crecord.mir: by-value C records move through binding calls in
 * both directions, and the c.field forms read and write the declared field
 * spellings on a record value held in a MIR local. */
#include "gen.c"

#include <stdint.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(cond)                                                         \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                  \
        }                                                                   \
    } while (0)

int main(void) {
    /* By-value results move every member out of the C callee, and by-value
     * parameters hand the whole struct back in. */
    struct crec_pair made = alder_fn_round_trip_pair_4(7L, 9uL);

    /* Field reads observe both members through the binding spellings. */
    CHECK(alder_fn_read_left_0(made) == 7);
    CHECK(alder_fn_read_right_1(made) == 9uL);

    /* A field write through a MIR local is visible to the C callee and
     * the subsequent read, and leaves the other member intact. */
    struct crec_pair written = alder_fn_write_left_2(made, -3L);
    CHECK(written.left == -3L);
    CHECK(written.right == 9uL);
    CHECK(crec_left(written) == -3L);
    CHECK(alder_fn_read_left_0(written) == -3L);

    /* By-value results and parameters carry every member. */
    CHECK(alder_fn_round_trip_3(40L, 2uL) == 42L);
    CHECK(alder_fn_bump_and_read_5(made, 13L) == 20L);

    if (failures != 0) {
        return 1;
    }
    return 0;
}
