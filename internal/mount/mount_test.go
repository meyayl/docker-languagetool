package mount

import (
	"strings"
	"testing"
)

func TestParseROMount(t *testing.T) {
	cases := []struct {
		name    string
		content string
		want    bool
	}{
		{
			name: "root is ro",
			content: `sysfs /sys sysfs rw,nosuid 0 0
rootfs / rootfs ro 0 0
overlay / overlay ro,relatime 0 0
tmpfs /tmp tmpfs rw,exec 0 0
`,
			want: true,
		},
		{
			name: "root is rw",
			content: `overlay / overlay rw,relatime 0 0
tmpfs /tmp tmpfs rw,exec 0 0
`,
			want: false,
		},
		{
			name: "rootfs entry skipped, real entry is rw",
			content: `rootfs / rootfs ro 0 0
overlay / overlay rw,relatime 0 0
`,
			want: false,
		},
		{
			name:    "no root mount",
			content: `tmpfs /tmp tmpfs rw,exec 0 0` + "\n",
			want:    false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseROMount(strings.NewReader(tc.content))
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %v, want %v", got, tc.want)
			}
		})
	}
}
