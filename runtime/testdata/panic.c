/* Panic behavior: alder_runtime_panic prints a message and terminates. The
 * harness expects a nonzero exit and the message on stderr. */
#include "alder.h"

int main(void) {
    alder_runtime_panic("intentional panic for the test harness");
    return 0; /* never reached */
}
