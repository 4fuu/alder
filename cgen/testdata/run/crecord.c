#include "crecord.h"

struct crec_pair crec_make(long left, unsigned long right) {
    struct crec_pair pair;
    pair.left = left;
    pair.right = right;
    return pair;
}

long crec_left(struct crec_pair pair) {
    return pair.left;
}

unsigned long crec_right(struct crec_pair pair) {
    return pair.right;
}

struct crec_pair crec_bump_left(struct crec_pair pair, long delta) {
    pair.left = pair.left + delta;
    return pair;
}

long crec_total(struct crec_pair pair) {
    return pair.left + (long)pair.right;
}
