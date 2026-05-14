package caps

import (
	"strings"
	"testing"
)

func TestReadPermittedFrom(t *testing.T) {
	content := `Name:	cat
CapPrm:	00000000000001c0
CapEff:	00000000000001c0
`
	val, err := readPermittedFrom(strings.NewReader(content))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// 0x1c0 = 448 = bits 6,7,8 set
	if val != 0x1c0 {
		t.Errorf("got 0x%x, want 0x1c0", val)
	}
}

func TestReadPermittedFromMissing(t *testing.T) {
	_, err := readPermittedFrom(strings.NewReader("Name: foo\n"))
	if err == nil {
		t.Fatal("expected error when CapPrm missing")
	}
}

func TestIsEnabledLogic(t *testing.T) {
	// 0x1c0 = bits 6,7,8 set (SETUID=6, SETGID=7)
	// bit 0 (CAP_CHOWN) and bit 1 (CAP_DAC_OVERRIDE) are NOT set
	val := uint64(0x1c0)

	cases := []struct {
		bit  int
		want bool
	}{
		{CAP_CHOWN, false},
		{CAP_DAC_OVERRIDE, false},
		{CAP_SETUID, true},
		{CAP_SETGID, true},
	}

	for _, tc := range cases {
		got := val&(1<<uint(tc.bit)) != 0
		if got != tc.want {
			t.Errorf("bit %d: got %v, want %v", tc.bit, got, tc.want)
		}
	}
}

func TestReadPermittedInvalidHex(t *testing.T) {
	content := "CapPrm:\tZZZZZZZZ\n"
	_, err := readPermittedFrom(strings.NewReader(content))
	if err == nil {
		t.Fatal("expected error for invalid hex")
	}
}
