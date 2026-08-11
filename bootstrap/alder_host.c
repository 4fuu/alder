#include "alder_host.h"

#include <stdlib.h>

struct AlderHostContext {
    unsigned char invocation_marker;
};

int main(void) {
    struct AlderHostContext context = {0};
    int32_t status = alder_program_entry((void *)&context);
    return status == (int32_t)0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
