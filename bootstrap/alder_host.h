#ifndef ALDER_HOST_H
#define ALDER_HOST_H

#include <stdbool.h>
#include <stdint.h>

#define ALDER_PROGRAM_FAILURE_STATUS INT32_MIN

int32_t alder_program_entry(void *host_context);

uint64_t alderhost_source_count(void);
uint64_t alderhost_source_path_len(uint64_t source);
uint8_t alderhost_source_path_byte(uint64_t source, uint64_t offset);
uint64_t alderhost_source_text_len(uint64_t source);
uint8_t alderhost_source_text_byte(uint64_t source, uint64_t offset);
uint64_t alderhost_command(void);
bool alderhost_format_json(void);
uint64_t alderhost_output_path_len(void);
uint8_t alderhost_output_path_byte(uint64_t offset);
bool alderhost_output_mode(uint64_t mode);
bool alderhost_output_failed(void);
bool alderhost_response_reset(void);
bool alderhost_stdout_byte(uint8_t byte);
bool alderhost_stdout_f64_bits(uint64_t bits);
uint64_t alderhost_decimal_f64_bits(uint64_t negative, uint64_t significand, int64_t exponent);
bool alderhost_stderr_byte(uint8_t byte);

#endif /* ALDER_HOST_H */
