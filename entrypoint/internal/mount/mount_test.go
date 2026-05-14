package mount

import "testing"

func TestIsROMount_NoError(t *testing.T) {
	_, err := IsROMount()
	if err != nil {
		t.Fatalf("IsROMount: %v", err)
	}
}
