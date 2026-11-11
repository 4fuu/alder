#include "cstr.h"
size_t cstr_length(const char *text) { size_t n = 0; while (text && text[n] != 0) { n = n + 1; } return n; }
size_t cstr_first_byte(const char *text) { return text ? (size_t)(unsigned char)text[0] : 0; }
