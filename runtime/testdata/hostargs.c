#include "alder.h"

#include <stddef.h>
#include <string.h>

int main(int argc, char **argv) {
    char *vector[3];
    (void)argc;
    (void)argv;

    if (alder_host_arg_count() != 0) { return 1; }
    vector[0] = (char *)"program";
    vector[1] = (char *)"first";
    vector[2] = (char *)"second";
    alder_host_set_args(3, vector);
    if (alder_host_arg_count() != 3) { return 2; }
    if (strcmp(alder_host_arg(0), "program") != 0) { return 3; }
    if (strcmp(alder_host_arg(1), "first") != 0) { return 4; }
    if (strcmp(alder_host_arg(2), "second") != 0) { return 5; }
    if (alder_host_arg(-1) != NULL || alder_host_arg(3) != NULL) { return 6; }

    alder_host_set_args(0, NULL);
    if (alder_host_arg_count() != 0 || alder_host_arg(0) != NULL) { return 7; }
    alder_host_set_args(-1, vector);
    if (alder_host_arg_count() != 0 || alder_host_arg(0) != NULL) { return 8; }
    return 0;
}
