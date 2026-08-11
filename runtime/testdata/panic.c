/* Panic behavior: aster_runtime_panic prints a message and terminates. The
 * harness expects a nonzero exit and the message on stderr. */
#include "aster.h"

int main(void) {
    aster_runtime_panic("intentional panic for the test harness");
    return 0; /* never reached */
}
