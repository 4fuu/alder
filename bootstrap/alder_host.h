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
bool alderhost_project_mode(void);
uint64_t alderhost_project_action(void);
uint64_t alderhost_manifest_len(void);
uint8_t alderhost_manifest_byte(uint64_t offset);
uint64_t alderhost_target_len(void);
uint8_t alderhost_target_byte(uint64_t offset);
uint64_t alderhost_profile_len(void);
uint8_t alderhost_profile_byte(uint64_t offset);
uint64_t alderhost_triple_len(void);
uint8_t alderhost_triple_byte(uint64_t offset);
bool alderhost_source_request_reset(void);
bool alderhost_source_request_byte(uint8_t byte);
uint64_t alderhost_source_request_finish(void);
bool alderhost_sources_sort(void);
bool alderhost_project_output_reset(uint64_t kind);
bool alderhost_project_output_byte(uint8_t byte);
bool alderhost_project_output_finish(void);
bool alderhost_project_target_kind(uint64_t kind);
uint64_t alderhost_project_selected_kind(void);
bool alderhost_project_entry_source_set(uint64_t source);
uint64_t alderhost_project_entry_source(void);
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
