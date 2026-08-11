/* Generational table tests: insert/lookup/remove, stale ids, foreign-table
 * ids, slot reuse with fresh generations, growth, and element integrity. */
#include "aster.h"

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

typedef struct {
    uint64_t key;
    double value;
    char label[16];
} Item;

static bool lookup_item(AsterTable *table, AsterTableId id, Item **out) {
    void *raw = NULL;
    if (!aster_table_lookup(table, id, &raw)) {
        return false;
    }
    *out = (Item *)raw;
    return true;
}

static bool lookup_mut_item(AsterTable *table, AsterTableId id, Item **out) {
    void *raw = NULL;
    if (!aster_table_lookup_mut(table, id, &raw)) {
        return false;
    }
    *out = (Item *)raw;
    return true;
}

static void test_insert_lookup_remove(void) {
    AsterDomain domain = {0};
    CHECK(aster_domain_init(&domain, NULL));
    AsterTable table = {0};
    CHECK(aster_table_init(&table, &domain, sizeof(Item), _Alignof(Item)));

    Item items[3] = {
        {1, 1.5, "one"},
        {2, 2.5, "two"},
        {3, 3.5, "three"},
    };
    AsterTableId ids[3];
    CHECK(aster_table_insert(&table, &items[0], &ids[0]));
    CHECK(aster_table_insert(&table, &items[1], &ids[1]));
    CHECK(aster_table_insert(&table, &items[2], &ids[2]));
    CHECK(ids[0].table_serial == ids[1].table_serial);
    CHECK(ids[0].slot != ids[1].slot);

    for (int i = 0; i < 3; i++) {
        Item *view = NULL;
        CHECK(lookup_item(&table, ids[i], &view));
        CHECK(view != NULL);
        CHECK(view->key == items[i].key);
        CHECK(view->value == items[i].value);
        CHECK(strcmp(view->label, items[i].label) == 0);
        Item *mut = NULL;
        CHECK(lookup_mut_item(&table, ids[i], &mut));
        CHECK(mut == view); /* both views address the same storage */
    }

    /* Removal invalidates the id. */
    CHECK(aster_table_remove(&table, ids[1]));
    Item *gone = NULL;
    CHECK(!lookup_item(&table, ids[1], &gone));
    CHECK(!aster_table_remove(&table, ids[1])); /* already gone */

    /* The other ids still resolve. */
    Item *view = NULL;
    CHECK(lookup_item(&table, ids[0], &view));
    CHECK(view->key == 1);

    /* The freed slot is reused with a fresh generation, so the stale id
     * cannot resolve to the replacement object. */
    Item replacement = {9, 9.5, "nine"};
    AsterTableId fresh;
    CHECK(aster_table_insert(&table, &replacement, &fresh));
    CHECK(fresh.slot == ids[1].slot);
    CHECK(fresh.generation != ids[1].generation);
    Item *replaced = NULL;
    CHECK(lookup_item(&table, fresh, &replaced));
    CHECK(replaced->key == 9);
    CHECK(!lookup_item(&table, ids[1], &replaced));

    aster_domain_destroy(&domain);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_stale_and_foreign_ids(void) {
    AsterDomain domain = {0};
    CHECK(aster_domain_init(&domain, NULL));
    AsterTable table = {0};
    CHECK(aster_table_init(&table, &domain, sizeof(Item), _Alignof(Item)));

    Item item = {42, 0.5, "answer"};
    AsterTableId id;
    CHECK(aster_table_insert(&table, &item, &id));

    /* Corrupted ids are rejected in the documented order. */
    AsterTableId wrong_serial = id;
    wrong_serial.table_serial = id.table_serial + 1;
    Item *view = NULL;
    CHECK(!lookup_item(&table, wrong_serial, &view));

    AsterTableId out_of_bounds = id;
    out_of_bounds.slot = UINT64_MAX;
    CHECK(!lookup_item(&table, out_of_bounds, &view));

    AsterTableId wrong_generation = id;
    wrong_generation.generation = id.generation + 1;
    CHECK(!lookup_item(&table, wrong_generation, &view));

    /* A second table never accepts the first table's ids. */
    AsterTable other = {0};
    CHECK(aster_table_init(&other, &domain, sizeof(Item), _Alignof(Item)));
    AsterTableId other_id;
    CHECK(aster_table_insert(&other, &item, &other_id));
    CHECK(other_id.table_serial != table.serial);
    CHECK(!lookup_item(&table, other_id, &view));

    /* Re-initializing a table at the same address gives it a fresh serial:
     * the old id must not resolve, the new id must. */
    AsterDomain domain2 = {0};
    CHECK(aster_domain_init(&domain2, NULL));
    AsterTable *t2 = (AsterTable *)&table;
    *t2 = (AsterTable){0};
    CHECK(aster_table_init(t2, &domain2, sizeof(Item), _Alignof(Item)));
    AsterTableId t2_id;
    CHECK(aster_table_insert(t2, &item, &t2_id));
    CHECK(t2_id.table_serial != id.table_serial);
    CHECK(!lookup_item(&table, id, &view));
    CHECK(lookup_item(&table, t2_id, &view));
    aster_domain_destroy(&domain2);

    aster_domain_destroy(&domain);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_growth(void) {
    AsterDomain domain = {0};
    CHECK(aster_domain_init(&domain, NULL));
    AsterTable table = {0};
    CHECK(aster_table_init(&table, &domain, sizeof(Item), _Alignof(Item)));

    enum { N = 1000 };
    Item items[N];
    AsterTableId ids[N];
    for (int i = 0; i < N; i++) {
        items[i].key = (uint64_t)i;
        items[i].value = (double)i + 0.25;
        items[i].label[0] = (char)('a' + (i % 26));
        items[i].label[1] = '\0';
        CHECK(aster_table_insert(&table, &items[i], &ids[i]));
    }
    CHECK(table.capacity > 8); /* the table grew */
    for (int i = 0; i < N; i++) {
        Item *view = NULL;
        CHECK(lookup_item(&table, ids[i], &view));
        CHECK(view->key == (uint64_t)i);
        CHECK(view->value == (double)i + 0.25);
    }
    /* Removing everything and reusing the table must not resurrect ids. */
    for (int i = 0; i < N; i++) {
        CHECK(aster_table_remove(&table, ids[i]));
    }
    for (int i = 0; i < N; i++) {
        Item *view = NULL;
        CHECK(!lookup_item(&table, ids[i], &view));
    }
    for (int i = 0; i < N; i++) {
        AsterTableId fresh;
        CHECK(aster_table_insert(&table, &items[i], &fresh));
        CHECK(fresh.generation != ids[i].generation);
    }

    aster_domain_destroy(&domain);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_domain_epoch_invalidation(void) {
    AsterDomain domain = {0};
    AsterTable table = {0};
    Item item = {7, 7.5, "seven"};
    AsterTableId id;
    CHECK(aster_domain_init(&domain, NULL));
    CHECK(aster_table_init(&table, &domain, sizeof(Item), _Alignof(Item)));
    AsterDomainMark mark = aster_domain_mark(&domain);
    CHECK(aster_table_insert(&table, &item, &id));
    CHECK(aster_domain_reset(&domain, mark));

    Item *replacement =
        (Item *)aster_domain_alloc(&domain, sizeof(Item), _Alignof(Item));
    CHECK(replacement != NULL);
    replacement->key = 999;
    Item *view = NULL;
    AsterTableId untouched = {91, 92, 93};
    CHECK(!lookup_item(&table, id, &view));
    CHECK(!aster_table_remove(&table, id));
    CHECK(!aster_table_insert(&table, &item, &untouched));
    CHECK(untouched.table_serial == 91 && untouched.slot == 92 &&
          untouched.generation == 93);

    /* A new table can be initialized explicitly after discarding the old
     * invalid handle. */
    table = (AsterTable){0};
    CHECK(aster_table_init(&table, &domain, sizeof(Item), _Alignof(Item)));
    CHECK(aster_table_insert(&table, &item, &id));
    CHECK(lookup_item(&table, id, &view));

    /* Destroy/re-init at the same domain address cannot revive the table. */
    aster_domain_destroy(&domain);
    CHECK(aster_domain_init(&domain, NULL));
    CHECK(!lookup_item(&table, id, &view));
    aster_domain_destroy(&domain);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_invalid(void) {
    AsterDomain domain = {0};
    CHECK(aster_domain_init(&domain, NULL));
    AsterTable table = {0};

    CHECK(!aster_table_init(&table, &domain, 0, 8));        /* zero size */
    CHECK(!aster_table_init(&table, &domain, 8, 3));        /* bad align */
    CHECK(!aster_table_init(&table, NULL, 8, 8));           /* no domain */
    CHECK(table.serial == 0 && table.slots == NULL);
#if SIZE_MAX < UINT64_MAX
    CHECK(!aster_table_init(&table, &domain, UINT64_MAX, 8));
    CHECK(!aster_table_init(&table, &domain, 8, UINT64_MAX));
    CHECK(table.serial == 0 && table.slots == NULL);
#endif
    AsterDomain dead = {0};
    CHECK(aster_domain_init(&dead, NULL));
    aster_domain_destroy(&dead);
    CHECK(!aster_table_init(&table, &dead, 8, 8)); /* dead domain */
    CHECK(aster_table_init(&table, &domain, 8, 8));
    CHECK(!aster_table_init(&table, &domain, 8, 8)); /* double init */

    /* Insert and lookup against an invalid table fail cleanly. */
    Item item = {1, 1.0, "x"};
    AsterTableId id;
    CHECK(!aster_table_insert(&table, NULL, &id));
    void *view = NULL;
    CHECK(!aster_table_lookup(&table, (AsterTableId){0, 0, 0}, &view));
    CHECK(!aster_table_remove(&table, (AsterTableId){0, 0, 0}));

    uint64_t generation = table.generation_counter;
    table.generation_counter = UINT64_MAX;
    AsterTableId untouched = {11, 12, 13};
    uint64_t count = table.count;
    CHECK(!aster_table_insert(&table, &item, &untouched));
    CHECK(untouched.table_serial == 11 && untouched.slot == 12 &&
          untouched.generation == 13);
    CHECK(table.count == count);
    table.generation_counter = generation;

    /* After the domain dies, table operations report failure without
     * touching released slot memory. */
    CHECK(aster_table_insert(&table, &item, &id));
    aster_domain_destroy(&domain);
    CHECK(!aster_table_insert(&table, &item, &id));
    CHECK(!aster_table_lookup(&table, id, &view));
    CHECK(!aster_table_remove(&table, id));
    CHECK(aster_runtime_live_allocations() == 0u);
}

int main(void) {
    test_insert_lookup_remove();
    test_stale_and_foreign_ids();
    test_growth();
    test_domain_epoch_invalidation();
    test_invalid();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
