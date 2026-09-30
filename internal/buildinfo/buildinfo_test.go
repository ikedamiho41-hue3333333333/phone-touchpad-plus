package buildinfo

import "testing"

func TestReleaseIdentity(t *testing.T) {
	tests := []struct {
		name string
		got  string
		want string
	}{
		{name: "application name", got: AppName, want: "Phone Touchpad Plus"},
		{name: "application version", got: Version, want: "0.1.0"},
		{name: "upstream name", got: UpstreamName, want: "Remote Touchpad"},
		{name: "upstream version", got: UpstreamVersion, want: "1.5.5"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if test.got != test.want {
				t.Fatalf("got %q, want %q", test.got, test.want)
			}
		})
	}
}
