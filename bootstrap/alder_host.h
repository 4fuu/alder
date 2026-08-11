#ifndef ALDER_HOST_H
#define ALDER_HOST_H

#include <stdint.h>

#define ALDER_PROGRAM_FAILURE_STATUS INT32_MIN

int32_t alder_program_entry(void *host_context);

#endif /* ALDER_HOST_H */
