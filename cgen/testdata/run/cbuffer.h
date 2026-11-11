/* Fixture binding for cbuffer.mir: one opaque byte buffer type behind
 * pointers. Both functions reject a null pointer even when the count is
 * zero, so an empty Alder buffer must arrive as a valid address. */
#ifndef CBUFFER_H
#define CBUFFER_H

#include <stddef.h>

typedef struct CBuffer CBuffer;

size_t cbuf_fill(CBuffer *buffer, size_t count);
size_t cbuf_sum(const CBuffer *buffer, size_t count);

#endif /* CBUFFER_H */
