//go:build darwin

package inputcontrol

import (
	"errors"
	"testing"
	"time"
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
		{name: "previous desktop", action: GestureAppPrevious, key: 123, flags: 0x00040000},
		{name: "next desktop", action: GestureAppNext, key: 124, flags: 0x00040000},
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

func TestDarwinClickCountRequiresNearbyTap(t *testing.T) {
	var state darwinPointerButtonState
	start := time.Unix(100, 0)
	if got := updateDarwinClickState(&state, true, start, 10, 10); got != 1 {
		t.Fatalf("first click count = %d, want 1", got)
	}
	updateDarwinClickState(&state, false, start.Add(40*time.Millisecond), 10, 10)
	if got := updateDarwinClickState(&state, true, start.Add(200*time.Millisecond), 100, 10); got != 1 {
		t.Fatalf("moved click count = %d, want 1", got)
	}
}

func TestDarwinClickCountRecognizesNearbyDoubleTap(t *testing.T) {
	var state darwinPointerButtonState
	start := time.Unix(100, 0)
	updateDarwinClickState(&state, true, start, 10, 10)
	updateDarwinClickState(&state, false, start.Add(40*time.Millisecond), 10, 10)
	if got := updateDarwinClickState(&state, true, start.Add(200*time.Millisecond), 13, 12); got != 2 {
		t.Fatalf("nearby click count = %d, want 2", got)
	}
}

func TestDarwinClickCountStartsFreshAfterDoubleTap(t *testing.T) {
	var state darwinPointerButtonState
	start := time.Unix(100, 0)
	updateDarwinClickState(&state, true, start, 10, 10)
	updateDarwinClickState(&state, false, start.Add(40*time.Millisecond), 10, 10)
	updateDarwinClickState(&state, true, start.Add(180*time.Millisecond), 10, 10)
	updateDarwinClickState(&state, false, start.Add(220*time.Millisecond), 10, 10)
	if got := updateDarwinClickState(&state, true, start.Add(300*time.Millisecond), 10, 10); got != 1 {
		t.Fatalf("click after completed double tap = %d, want 1", got)
	}
}

func TestDarwinClickCountDoesNotMergeSlowTaps(t *testing.T) {
	var state darwinPointerButtonState
	start := time.Unix(100, 0)
	updateDarwinClickState(&state, true, start, 10, 10)
	updateDarwinClickState(&state, false, start.Add(40*time.Millisecond), 10, 10)
	if got := updateDarwinClickState(&state, true, start.Add(400*time.Millisecond), 10, 10); got != 1 {
		t.Fatalf("slow second click count = %d, want 1", got)
	}
}

func TestDarwinClickCountUsesPressTime(t *testing.T) {
	var state darwinPointerButtonState
	start := time.Unix(100, 0)
	updateDarwinClickState(&state, true, start, 10, 10)
	updateDarwinClickState(&state, false, start.Add(450*time.Millisecond), 10, 10)
	if got := updateDarwinClickState(&state, true, start.Add(600*time.Millisecond), 10, 10); got != 1 {
		t.Fatalf("late second click count = %d, want 1", got)
	}
}
