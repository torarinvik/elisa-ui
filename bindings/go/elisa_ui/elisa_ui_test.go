package elisa_ui

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestValidTextPrefix(t *testing.T) {
	full := strings.Repeat("a", MaxTextBytes+4)
	cutRune := strings.Repeat("x", MaxTextBytes-1) + "é"
	exactRunes := strings.Repeat("é", MaxTextBytes/2)
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{name: "empty", input: "", want: ""},
		{name: "embedded NUL", input: "A\x00B", want: "A\x00B"},
		{name: "invalid UTF-8 suffix", input: "ok" + string([]byte{0xff}) + "discard", want: "ok"},
		{name: "invalid UTF-8 prefix", input: string([]byte{0xff}) + "discard", want: ""},
		{name: "byte cap", input: full, want: full[:MaxTextBytes]},
		{name: "complete rune at cap", input: exactRunes, want: exactRunes},
		{name: "rune crossing cap", input: cutRune, want: cutRune[:MaxTextBytes-1]},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := validTextPrefix(test.input)
			if got != test.want {
				t.Fatalf("validTextPrefix() length=%d, want length=%d", len(got), len(test.want))
			}
			if !utf8.ValidString(got) {
				t.Fatal("validTextPrefix() returned malformed UTF-8")
			}
		})
	}
}

var textPrefixSink string

func TestValidTextPrefixDoesNotAllocate(t *testing.T) {
	input := strings.Repeat("x", MaxTextBytes*1024)
	allocations := testing.AllocsPerRun(100, func() {
		textPrefixSink = validTextPrefix(input)
	})
	if allocations != 0 {
		t.Fatalf("validTextPrefix() allocated %g times per call; want zero", allocations)
	}
}
