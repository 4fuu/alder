/* Driver for cleanup.mir: cleanup registration order, disarming, and
 * exactly-once execution on success and failure paths. record_c observes the
 * calls through the FFI boundary. */
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

static int64_t record_log[8];
static int record_log_len = 0;

int64_t record_c(int64_t x) {
    if (record_log_len < 8) {
        record_log[record_log_len++] = x;
    }
    return 0;
}

int main(void) {
    /* Success path: entries 1, 2, 3 pushed; 1 disarmed; run executes the
     * armed entries in reverse registration order: 3, 2. */
    record_log_len = 0;
    CHECK(alder_fn_scoped_1(true) == 0);
    CHECK(record_log_len == 2);
    CHECK(record_log[0] == 3 && record_log[1] == 2);

    /* Failure path: same registration, fail exits through run as well, and
     * the entries still run exactly once. */
    record_log_len = 0;
    CHECK(alder_fn_scoped_1(false) == 0);
    CHECK(record_log_len == 2);
    CHECK(record_log[0] == 3 && record_log[1] == 2);

    /* Repeated calls keep the per-site context consistent. */
    record_log_len = 0;
    CHECK(alder_fn_scoped_1(true) == 0);
    CHECK(record_log_len == 2 && record_log[0] == 3 && record_log[1] == 2);
    CHECK(alder_runtime_live_allocations() == 0u);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
