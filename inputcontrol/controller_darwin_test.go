//go:build darwin

package inputcontrol

import (
	"errors"
	"testing"
)

func TestInitDarwinControllerRejectsMissingAccessibilityPermission(t *testing.T) {
	controller, err := initDarwinController(func() bool { return false })
	if controller != nil {
		_ = controller.Close()
		t.Fatal("controller was created without Accessibility permission")
	}
	if !errors.Is(err, errDarwinAccessibilityPermission) {
		t.Fatalf("error = %v, want Accessibility permission error", err)
	}
	var unsupported *UnsupportedPlatformError
	if errors.As(err, &unsupported) {
		t.Fatal("missing Accessibility permission was reported as an unsupported platform")
	}
}

func TestDarwinGestureShortcuts(t *testing.T) {
	tests := []struct {
		name   string
		action GestureAction
		key    uint16
		flags  uint64
	}{
		{name: "mission control", action: GestureOverview, key: 126, flags: 0x00040000},
		{name: "show desktop", action: GestureShowDesktop, key: 99, flags: 0x00100000},
		{name: "previous application", action: GestureAppPrevious, key: 48, flags: 0x00120000},
		{name: "next application", action: GestureAppNext, key: 48, flags: 0x00100000},
		{name: "zoom in", action: GestureZoomIn, key: 24, flags: 0x00120000},
		{name: "zoom out", action: GestureZoomOut, key: 27, flags: 0x00100000},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			shortcut, err := darwinGestureShortcut(test.action)
			if err != nil {
				t.Fatal(err)
			}
			if got := uint16(shortcut.virtualKey); got != test.key {
				t.Fatalf("virtual key = %d, want %d", got, test.key)
			}
			if got := uint64(shortcut.flags); got != test.flags {
				t.Fatalf("flags = %#x, want %#x", got, test.flags)
			}
		})
	}
}

func TestDarwinGestureShortcutRejectsUnknownAction(t *testing.T) {
	if _, err := darwinGestureShortcut(GestureLimit); err == nil {
		t.Fatal("darwinGestureShortcut() succeeded for an unknown action")
	}
}
