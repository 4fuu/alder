#include "cbuffer.h"

size_t cbuf_fill(CBuffer *buffer, size_t count) {
    if (buffer == NULL) { return (size_t)-1; }
    unsigned char *bytes = (unsigned char *)buffer;
    for (size_t i = 0; i < count; i++) { bytes[i] = 7; }
    return count;
}

size_t cbuf_sum(const CBuffer *buffer, size_t count) {
    if (buffer == NULL) { return (size_t)-1; }
    const unsigned char *bytes = (const unsigned char *)buffer;
    size_t total = 0;
    for (size_t i = 0; i < count; i++) { total += bytes[i]; }
    return total;
}
