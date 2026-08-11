package verify

import "testing"

func TestHostedABIExternalNamesAreValid(t *testing.T) {
	names := []string{
		"alderhost_source_count",
		"alderhost_source_path_len",
		"alderhost_source_path_byte",
		"alderhost_source_text_len",
		"alderhost_source_text_byte",
		"alderhost_stdout_byte",
		"alderhost_stderr_byte",
	}
	for _, name := range names {
		if !validCExternalName(name) {
			t.Errorf("host external name %q rejected", name)
		}
	}
}
