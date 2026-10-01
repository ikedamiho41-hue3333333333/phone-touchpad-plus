//go:build darwin

/*
 *    Copyright (c) 2026 Unrud <unrud@outlook.com>
 *
 *    This file is part of Remote-Touchpad.
 *
 *    Remote-Touchpad is free software: you can redistribute it and/or modify
 *    it under the terms of the GNU General Public License as published by
 *    the Free Software Foundation, either version 3 of the License, or
 *    (at your option) any later version.
 *
 *    Remote-Touchpad is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with Remote-Touchpad.  If not, see <http://www.gnu.org/licenses/>.
 */

package inputcontrol

// #cgo LDFLAGS: -framework CoreGraphics -framework ApplicationServices
// #include <ApplicationServices/ApplicationServices.h>
// #include <Carbon/Carbon.h>
// #include <IOKit/hidsystem/ev_keymap.h>
//
// static double phoneTouchpadSystemDoubleClickInterval(void) {
//     CFPropertyListRef value = CFPreferencesCopyValue(
//         CFSTR("com.apple.mouse.doubleClickThreshold"),
//         kCFPreferencesAnyApplication,
//         kCFPreferencesCurrentUser,
//         kCFPreferencesAnyHost
//     );
//     double seconds = 0;
//     if (value != NULL && CFGetTypeID(value) == CFNumberGetTypeID()) {
//         CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &seconds);
//     }
//     if (value != NULL) {
//         CFRelease(value);
//     }
//     return seconds;
// }
import "C"

import (
	"errors"
	"fmt"
	"math"
	"sync"
	"time"
	"unicode/utf16"
)

// Undocumented constants
const (
	kCGEventSubtype C.CGEventField = 0x53
	kCGEventData1   C.CGEventField = 0x95
	kCGEventData2   C.CGEventField = 0x96
)

const (
	doubleClickDistanceSquared        = 36.0
	fallbackDarwinDoubleClickInterval = 500 * time.Millisecond
)

var errDarwinAccessibilityPermission = errors.New(
	"macOS Accessibility permission is required for Phone Touchpad Plus",
)

type darwinPointerButtonState struct {
	Pressed    bool
	ClickCount int
	T          time.Time
	X          float64
	Y          float64
}

func updateDarwinClickState(state *darwinPointerButtonState, press bool,
	now time.Time, x, y float64, clickInterval time.Duration) int {
	if !press {
		state.Pressed = false
		return min(state.ClickCount, 2)
	}
	clickCount := 1
	delta := now.Sub(state.T)
	dx := x - state.X
	dy := y - state.Y
	if !state.T.IsZero() && state.ClickCount < 2 &&
		delta >= 0 && delta <= clickInterval &&
		dx*dx+dy*dy <= doubleClickDistanceSquared {
		clickCount = state.ClickCount + 1
	}
	state.Pressed = true
	state.ClickCount = clickCount
	state.T = now
	state.X = x
	state.Y = y
	return clickCount
}

func darwinDoubleClickIntervalFromSeconds(seconds float64) time.Duration {
	if math.IsNaN(seconds) || math.IsInf(seconds, 0) || seconds <= 0 || seconds > 2 {
		return fallbackDarwinDoubleClickInterval
	}
	return time.Duration(seconds * float64(time.Second))
}

func darwinSystemDoubleClickInterval() time.Duration {
	return darwinDoubleClickIntervalFromSeconds(
		float64(C.phoneTouchpadSystemDoubleClickInterval()),
	)
}

type darwinController struct {
	eventSrc           C.CGEventSourceRef
	clickInterval      time.Duration
	lock               sync.Mutex
	pointerButtonState [PointerButtonLimit]darwinPointerButtonState
}

type darwinShortcut struct {
	virtualKey C.CGKeyCode
	flags      C.CGEventFlags
}

func darwinGestureShortcut(action GestureAction) (darwinShortcut, error) {
	switch action {
	case GestureOverview:
		return darwinShortcut{C.kVK_UpArrow, C.kCGEventFlagMaskControl}, nil
	case GestureShowDesktop:
		return darwinShortcut{C.kVK_F3, C.kCGEventFlagMaskCommand}, nil
	case GestureAppPrevious:
		return darwinShortcut{C.kVK_LeftArrow, C.kCGEventFlagMaskControl}, nil
	case GestureAppNext:
		return darwinShortcut{C.kVK_RightArrow, C.kCGEventFlagMaskControl}, nil
	case GestureZoomIn:
		return darwinShortcut{C.kVK_ANSI_Equal, C.kCGEventFlagMaskCommand | C.kCGEventFlagMaskShift}, nil
	case GestureZoomOut:
		return darwinShortcut{C.kVK_ANSI_Minus, C.kCGEventFlagMaskCommand}, nil
	default:
		return darwinShortcut{}, fmt.Errorf("unsupported gesture action: %#v", action)
	}
}

func init() {
	RegisterController("Darwin", InitDarwinController, 0)
}

func InitDarwinController() (Controller, error) {
	return initDarwinController(func() bool {
		if bool(C.CGPreflightPostEventAccess()) {
			return true
		}
		return bool(C.CGRequestPostEventAccess())
	})
}

func initDarwinController(hasPostEventAccess func() bool) (Controller, error) {
	if !hasPostEventAccess() {
		return nil, errDarwinAccessibilityPermission
	}
	eventSrc := C.CGEventSourceCreate(C.kCGEventSourceStatePrivate)
	if eventSrc == 0 {
		return nil, &UnsupportedPlatformError{
			fmt.Errorf("failed to create event source"),
		}
	}
	return &darwinController{
		eventSrc:      eventSrc,
		clickInterval: darwinSystemDoubleClickInterval(),
	}, nil
}

func (p *darwinController) Close() error {
	C.CFRelease(C.CFTypeRef(p.eventSrc))
	return nil
}

func (p *darwinController) sendKeyboardKey(virtualKey C.CGKeyCode, keyDown bool, flags C.CGEventFlags, unicode []rune) error {
	event := C.CGEventCreateKeyboardEvent(p.eventSrc, virtualKey, C.bool(keyDown))
	if event == 0 {
		return fmt.Errorf("failed to create keyboard event")
	}
	defer C.CFRelease(C.CFTypeRef(event))
	if flags != 0 {
		C.CGEventSetFlags(event, flags)
	}
	if unicode != nil {
		unicodeUtf16 := utf16.Encode(unicode)
		C.CGEventKeyboardSetUnicodeString(event, C.UniCharCount(len(unicodeUtf16)), (*C.UniChar)(&unicodeUtf16[0]))
	}
	C.CGEventPost(C.kCGHIDEventTap, event)
	return nil
}

func (p *darwinController) sendKeyboardKeyPress(virtualKey C.CGKeyCode, flags C.CGEventFlags, unicode []rune) error {
	for _, keyDown := range []bool{true, false} {
		if err := p.sendKeyboardKey(virtualKey, keyDown, flags, unicode); err != nil {
			return err
		}
	}
	return nil
}

func (p *darwinController) sendSpecialKey(nxKey uint8, keyDown bool) error {
	event := C.CGEventCreate(p.eventSrc)
	if event == 0 {
		return fmt.Errorf("failed to create event")
	}
	defer C.CFRelease(C.CFTypeRef(event))
	var flags C.CGEventFlags
	if keyDown {
		flags |= C.NX_KEYDOWN << 8
	} else {
		flags |= C.NX_KEYUP << 8
	}
	C.CGEventSetType(event, C.NX_SYSDEFINED)
	C.CGEventSetFlags(event, flags)
	C.CGEventSetIntegerValueField(
		event,
		kCGEventSubtype,
		C.NX_SUBTYPE_AUX_CONTROL_BUTTONS,
	)
	C.CGEventSetIntegerValueField(
		event,
		kCGEventData1,
		(C.int64_t(nxKey)<<16)|C.int64_t(flags),
	)
	C.CGEventSetIntegerValueField(
		event,
		kCGEventData2,
		-1,
	)
	C.CGEventPost(C.kCGHIDEventTap, event)
	return nil
}

func (p *darwinController) sendSpecialKeyPress(nxKey uint8) error {
	for _, keyDown := range []bool{true, false} {
		if err := p.sendSpecialKey(nxKey, keyDown); err != nil {
			return err
		}
	}
	return nil
}

func (p *darwinController) KeyboardText(text string) error {
	for _, r := range text {
		// Use Unicode string rather than the acutal key codes
		if err := p.sendKeyboardKeyPress(0, 0, []rune{r}); err != nil {
			return err
		}
	}
	return nil
}

func (p *darwinController) KeyboardKey(key Key) error {
	switch key {
	case KeyBackSpace:
		return p.sendKeyboardKeyPress(C.kVK_Delete, 0, nil)
	case KeyReturn:
		return p.sendKeyboardKeyPress(C.kVK_Return, 0, nil)
	case KeyLeft:
		return p.sendKeyboardKeyPress(C.kVK_LeftArrow, 0, nil)
	case KeyUp:
		return p.sendKeyboardKeyPress(C.kVK_UpArrow, 0, nil)
	case KeyRight:
		return p.sendKeyboardKeyPress(C.kVK_RightArrow, 0, nil)
	case KeyDown:
		return p.sendKeyboardKeyPress(C.kVK_DownArrow, 0, nil)
	case KeyDelete:
		return p.sendKeyboardKeyPress(C.kVK_ForwardDelete, 0, nil)
	case KeySuper:
		return p.sendKeyboardKeyPress(C.kVK_UpArrow, C.kCGEventFlagMaskControl, nil)
	case KeyHome, KeyBrowserBack:
		return p.sendKeyboardKeyPress(C.kVK_LeftArrow, C.kCGEventFlagMaskCommand, nil)
	case KeyEnd, KeyBrowserForward:
		return p.sendKeyboardKeyPress(C.kVK_RightArrow, C.kCGEventFlagMaskCommand, nil)
	case KeyVolumeMute:
		return p.sendSpecialKeyPress(C.NX_KEYTYPE_MUTE)
	case KeyVolumeDown:
		return p.sendSpecialKeyPress(C.NX_KEYTYPE_SOUND_DOWN)
	case KeyVolumeUp:
		return p.sendSpecialKeyPress(C.NX_KEYTYPE_SOUND_UP)
	case KeyMediaNextTrack:
		return p.sendSpecialKeyPress(C.NX_KEYTYPE_NEXT)
	case KeyMediaPrevTrack:
		return p.sendSpecialKeyPress(C.NX_KEYTYPE_PREVIOUS)
	case KeyMediaPlayPause:
		return p.sendSpecialKeyPress(C.NX_KEYTYPE_PLAY)
	default:
		return fmt.Errorf("key not mapped to virtual-key code: %#v", key)
	}
}

func (p *darwinController) Gesture(action GestureAction) error {
	shortcut, err := darwinGestureShortcut(action)
	if err != nil {
		return err
	}
	return p.sendKeyboardKeyPress(shortcut.virtualKey, shortcut.flags, nil)
}

func (p *darwinController) mouseLocation() (C.CGPoint, error) {
	event := C.CGEventCreate(p.eventSrc)
	if event == 0 {
		return C.CGPointZero, fmt.Errorf("failed to create event")
	}
	location := C.CGEventGetLocation(event)
	return location, nil
}

func (p *darwinController) PointerButton(button PointerButton, press bool) error {
	location, err := p.mouseLocation()
	if err != nil {
		return err
	}
	p.lock.Lock()
	defer p.lock.Unlock()
	state := &p.pointerButtonState[button]
	now := time.Now()
	var event C.CGEventRef
	if button == PointerButtonLeft && press {
		event = C.CGEventCreateMouseEvent(p.eventSrc, C.kCGEventLeftMouseDown, location, C.kCGMouseButtonLeft)
	} else if button == PointerButtonLeft {
		event = C.CGEventCreateMouseEvent(p.eventSrc, C.kCGEventLeftMouseUp, location, C.kCGMouseButtonLeft)
	} else if button == PointerButtonMiddle && press {
		event = C.CGEventCreateMouseEvent(p.eventSrc, C.kCGEventOtherMouseDown, location, C.kCGMouseButtonCenter)
	} else if button == PointerButtonMiddle {
		event = C.CGEventCreateMouseEvent(p.eventSrc, C.kCGEventOtherMouseUp, location, C.kCGMouseButtonCenter)
	} else if button == PointerButtonRight && press {
		event = C.CGEventCreateMouseEvent(p.eventSrc, C.kCGEventRightMouseDown, location, C.kCGMouseButtonRight)
	} else if button == PointerButtonRight {
		event = C.CGEventCreateMouseEvent(p.eventSrc, C.kCGEventRightMouseUp, location, C.kCGMouseButtonRight)
	} else {
		return fmt.Errorf("unsupported pointer button: %#v", button)
	}
	if event == 0 {
		return fmt.Errorf("failed to create mouse event")
	}
	defer C.CFRelease(C.CFTypeRef(event))
	clickCount := updateDarwinClickState(state, press, now,
		float64(location.x), float64(location.y), p.clickInterval)
	C.CGEventSetIntegerValueField(event, C.kCGMouseEventClickState, C.int64_t(clickCount))
	C.CGEventPost(C.kCGHIDEventTap, event)
	return nil
}

func (p *darwinController) PointerMove(deltaX, deltaY int) error {
	location, err := p.mouseLocation()
	if err != nil {
		return err
	}
	location.x += C.CGFloat(deltaX)
	location.y += C.CGFloat(deltaY)
	var mouseType C.CGEventType = C.kCGEventMouseMoved
	var mouseButton C.CGMouseButton
	if p.pointerButtonState[PointerButtonLeft].Pressed {
		mouseType = C.kCGEventLeftMouseDragged
		mouseButton = C.kCGMouseButtonLeft
	} else if p.pointerButtonState[PointerButtonRight].Pressed {
		mouseType = C.kCGEventRightMouseDragged
		mouseButton = C.kCGMouseButtonRight
	} else if p.pointerButtonState[PointerButtonMiddle].Pressed {
		mouseType = C.kCGEventOtherMouseDragged
		mouseButton = C.kCGMouseButtonCenter
	}
	event := C.CGEventCreateMouseEvent(p.eventSrc, mouseType, location, mouseButton)
	if event == 0 {
		return fmt.Errorf("failed to create mouse event")
	}
	defer C.CFRelease(C.CFTypeRef(event))
	C.CGEventPost(C.kCGHIDEventTap, event)
	return nil
}

func (p *darwinController) PointerScroll(deltaHorizontal, deltaVertical int, finish bool) error {
	event := C.CGEventCreateScrollWheelEvent2(p.eventSrc, C.kCGScrollEventUnitPixel, 2, C.int32_t(deltaVertical), C.int32_t(deltaHorizontal), 0)
	if event == 0 {
		return fmt.Errorf("failed to create scroll wheel event")
	}
	defer C.CFRelease(C.CFTypeRef(event))
	C.CGEventPost(C.kCGHIDEventTap, event)
	return nil
}
