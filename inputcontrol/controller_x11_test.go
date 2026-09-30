//go:build x11

package inputcontrol

import (
	"reflect"
	"testing"
)

func TestGestureKeysymsSwitchesApplicationsInCurrentWorkspace(t *testing.T) {
	tests := []struct {
		name   string
		action GestureAction
		want   []Keysym
	}{
		{
			name:   "previous application",
			action: GestureAppPrevious,
			want:   []Keysym{0xffe9, 0xffe1, 0xff09}, // Alt+Shift+Tab
		},
		{
			name:   "next application",
			action: GestureAppNext,
			want:   []Keysym{0xffe9, 0xff09}, // Alt+Tab
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := gestureKeysyms(test.action)
			if err != nil {
				t.Fatalf("gestureKeysyms(%v) returned error: %v", test.action, err)
			}
			if !reflect.DeepEqual(got, test.want) {
				t.Fatalf("gestureKeysyms(%v) = %#v, want %#v", test.action, got, test.want)
			}
		})
	}
}
