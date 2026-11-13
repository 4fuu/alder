#include "alder.h"

#include <assert.h>
#include <stdint.h>

static uint64_t hash_bytes(uint64_t k0, uint64_t k1, const uint8_t *data, uint64_t len) {
    AlderHashState state;
    alder_hash_init(&state, k0, k1);
    alder_hash_write_bytes(&state, data, len);
    return alder_hash_finish(&state);
}

int main(void) {
    const uint64_t k0 = UINT64_C(506097522914230528);  /* 0x0706050403020100 */
    const uint64_t k1 = UINT64_C(1084818905618843912); /* 0x0f0e0d0c0b0a0908 */
    uint8_t bytes[16];
    uint64_t at;

    for (at = 0; at < UINT64_C(16); at++) {
        bytes[at] = (uint8_t)at;
    }
    /* SipHash-1-3 standard vectors from the independent go-sip13 tests. */
    assert(hash_bytes(k0, k1, bytes, UINT64_C(0)) == UINT64_C(12370263754033579228));
    assert(hash_bytes(k0, k1, bytes, UINT64_C(1)) == UINT64_C(14552427766023178899));
    assert(hash_bytes(k0, k1, bytes, UINT64_C(8)) == UINT64_C(3931806377309739662));
    assert(hash_bytes(k0, k1, bytes, UINT64_C(16)) == UINT64_C(14722228812742953830));

    {
        AlderHashState state;
        alder_hash_init(&state, UINT64_C(0), UINT64_C(0));
        alder_hash_write_u64(&state, UINT64_C(7));
        assert(alder_hash_finish(&state) == UINT64_C(7364705619221056123));
    }
    return 0;
}
