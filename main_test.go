package main

import (
	"strings"
	"testing"

	"github.com/ikedamiho41-hue3333333333/phone-touchpad-plus/inputcontrol"
)

type baseTestController struct {
	moves [][2]int
}

func (c *baseTestController) Close() error                       { return nil }
func (c *baseTestController) KeyboardText(string) error          { return nil }
func (c *baseTestController) KeyboardKey(inputcontrol.Key) error { return nil }
func (c *baseTestController) PointerButton(inputcontrol.PointerButton, bool) error {
	return nil
}
func (c *baseTestController) PointerMove(x, y int) error {
	c.moves = append(c.moves, [2]int{x, y})
	return nil
}
func (c *baseTestController) PointerScroll(int, int, bool) error { return nil }

type gestureTestController struct {
	*baseTestController
}

func (c *gestureTestController) Gesture(inputcontrol.GestureAction) error { return nil }

func TestControllerCapabilitiesReflectGestureInterface(t *testing.T) {
	if got := controllerCapabilities(&baseTestController{}); got.Gestures {
		t.Fatal("base controller reported gesture support")
	}
	if got := controllerCapabilities(&gestureTestController{&baseTestController{}}); !got.Gestures {
		t.Fatal("gesture controller did not report gesture support")
	}
}

func TestControllerCapabilitiesDoNotBlockBasePointerCommands(t *testing.T) {
	controller := &baseTestController{}
	if err := processCommand(controller, "g0"); err == nil ||
		!strings.Contains(err.Error(), "unsupported") {
		t.Fatalf("gesture command error = %v, want unsupported error", err)
	}
	if err := processCommand(controller, "m3;-2"); err != nil {
		t.Fatal(err)
	}
	if len(controller.moves) != 1 || controller.moves[0] != [2]int{3, -2} {
		t.Fatalf("pointer moves = %#v, want [[3 -2]]", controller.moves)
	}
}
