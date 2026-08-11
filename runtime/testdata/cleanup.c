/* Scoped cleanup tests: reverse-order execution, disarm, exactly-once runs,
 * success and failure paths, and contract violations that must not leak. */
#include "alder.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

static int failures = 0;
static char run_log[64];
static size_t run_log_len = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

typedef struct {
    char tag;
    int *count;
} Ctx;

static void record(char tag) {
    if (run_log_len + 1 < sizeof(run_log)) {
        run_log[run_log_len++] = tag;
        run_log[run_log_len] = '\0';
    }
}

static void cleanup_fn(void *context) {
    Ctx *c = (Ctx *)context;
    record(c->tag);
    if (c->count != NULL) {
        *(c->count) += 1;
    }
}

static void reset_log(void) {
    run_log[0] = '\0';
    run_log_len = 0;
}

static void test_reverse_order_and_exactly_once(void) {
    AlderCleanupScope scope = {0};
    CHECK(alder_cleanup_scope_begin(&scope));
    CHECK(!alder_cleanup_scope_begin(&scope)); /* double begin rejected */

    int count_a = 0, count_b = 0, count_c = 0;
    Ctx a = {'a', &count_a}, b = {'b', &count_b}, c = {'c', &count_c};
    AlderCleanupId id_a, id_b, id_c;
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &a, &id_a));
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &b, &id_b));
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &c, &id_c));
    CHECK(id_a != NULL && id_b != NULL && id_c != NULL);

    /* Runs execute in reverse registration order. */
    reset_log();
    CHECK(alder_cleanup_run(&scope));
    CHECK(run_log[0] == 'c' && run_log[1] == 'b' && run_log[2] == 'a');
    CHECK(run_log[3] == '\0');
    CHECK(count_a == 1 && count_b == 1 && count_c == 1);

    /* A second run executes nothing: each entry runs exactly once. */
    reset_log();
    CHECK(alder_cleanup_run(&scope));
    CHECK(run_log[0] == '\0');
    CHECK(count_a == 1 && count_b == 1 && count_c == 1);

    CHECK(alder_cleanup_end(&scope));
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_disarm(void) {
    AlderCleanupScope scope = {0};
    CHECK(alder_cleanup_scope_begin(&scope));

    int count_a = 0, count_b = 0;
    Ctx a = {'a', &count_a}, b = {'b', &count_b};
    AlderCleanupId id_a, id_b;
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &a, &id_a));
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &b, &id_b));

    /* Disarming an entry skips it at run time. */
    CHECK(alder_cleanup_disarm(id_b));
    CHECK(!alder_cleanup_disarm(id_b)); /* already disarmed */
    CHECK(!alder_cleanup_disarm(NULL));
    reset_log();
    CHECK(alder_cleanup_run(&scope));
    CHECK(run_log[0] == 'a');
    CHECK(count_a == 1 && count_b == 0);

    CHECK(alder_cleanup_end(&scope));
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void exercise_exit_path(bool failed) {
    AlderCleanupScope scope = {0};
    CHECK(alder_cleanup_scope_begin(&scope));
    int count = 0;
    Ctx ctx = {'x', &count};
    AlderCleanupId id;
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &ctx, &id));

    reset_log();
    if (failed) {
        CHECK(alder_cleanup_run(&scope));
        CHECK(alder_cleanup_end(&scope));
    } else {
        CHECK(alder_cleanup_run(&scope));
        CHECK(alder_cleanup_end(&scope));
    }
    CHECK(count == 1);
    CHECK(run_log[0] == 'x');
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_failure_path_exactly_once(void) {
    /* Exercise both generated exit shapes: run + end must execute before
     * either return or fail. */
    exercise_exit_path(false);
    exercise_exit_path(true);
}

static void test_end_contract(void) {
    /* end without run is a contract violation: it reports false but frees
     * everything. */
    AlderCleanupScope scope = {0};
    CHECK(alder_cleanup_scope_begin(&scope));
    AlderCleanupId id;
    Ctx ctx = {'z', NULL};
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &ctx, &id));
    CHECK(!alder_cleanup_end(&scope)); /* armed entries remain */
    CHECK(alder_runtime_live_allocations() == 0u);

    /* end after run with nothing armed succeeds. */
    CHECK(alder_cleanup_scope_begin(&scope));
    CHECK(alder_cleanup_run(&scope));
    CHECK(alder_cleanup_end(&scope));
    CHECK(!alder_cleanup_end(&scope)); /* inactive scope */
    CHECK(!alder_cleanup_run(&scope)); /* inactive scope */
    CHECK(!alder_cleanup_push(&scope, cleanup_fn, &ctx, &id));

    /* begin, run, push, end: the late push is a violation that must not
     * leak. */
    CHECK(alder_cleanup_scope_begin(&scope));
    CHECK(alder_cleanup_run(&scope));
    CHECK(alder_cleanup_push(&scope, cleanup_fn, &ctx, &id));
    CHECK(!alder_cleanup_end(&scope));
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_many_entries(void) {
    AlderCleanupScope scope = {0};
    CHECK(alder_cleanup_scope_begin(&scope));
    enum { N = 50 }; /* must fit the run log */
    Ctx ctxs[N];
    int counts[N] = {0};
    for (int i = 0; i < N; i++) {
        ctxs[i].tag = (char)('A' + (i % 26));
        ctxs[i].count = &counts[i];
        AlderCleanupId id;
        CHECK(alder_cleanup_push(&scope, cleanup_fn, &ctxs[i], &id));
    }
    reset_log();
    CHECK(alder_cleanup_run(&scope));
    /* The last pushed entry runs first. */
    CHECK(run_log[0] == (char)('A' + ((N - 1) % 26)));
    CHECK(run_log[N - 1] == 'A');
    for (int i = 0; i < N; i++) {
        CHECK(counts[i] == 1);
    }
    CHECK(alder_cleanup_end(&scope));
    CHECK(alder_runtime_live_allocations() == 0u);
}

int main(void) {
    test_reverse_order_and_exactly_once();
    test_disarm();
    test_failure_path_exactly_once();
    test_end_contract();
    test_many_entries();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
