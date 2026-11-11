/* Fixture record and functions for crecord.mir: a plain non-bitfield
 * struct passed by value in both directions, with field reads and writes
 * through the verified binding spellings. */
#ifndef CRECORD_H
#define CRECORD_H

struct crec_pair {
    long left;
    unsigned long right;
};

struct crec_pair crec_make(long left, unsigned long right);
long crec_left(struct crec_pair pair);
unsigned long crec_right(struct crec_pair pair);
struct crec_pair crec_bump_left(struct crec_pair pair, long delta);
long crec_total(struct crec_pair pair);

#endif /* CRECORD_H */
