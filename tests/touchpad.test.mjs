import assert from "node:assert/strict";
import test from "node:test";

import Touchpad from "../webdata/app/touchpad.mjs";

const createTouchpadHarness = () => {
    const listeners = new Map();
    const feedback = [];
    globalThis.document = {
        addEventListener(type, listener) {
            const typeListeners = listeners.get(type) || [];
            typeListeners.push(listener);
            listeners.set(type, typeListeners);
        },
        dispatchEvent(event) {
            feedback.push(event.detail);
        },
    };
    globalThis.CustomEvent = class {
        constructor(type, options) {
            this.type = type;
            this.detail = options.detail;
        }
    };
    Object.defineProperty(globalThis, "navigator", {
        configurable: true,
        value: {vibrate() {}},
    });

    const gestures = [];
    const scrolls = [];
    const buttons = [];
    const moves = [];
    const inputController = {
        gesture(action) { gestures.push(action); return true; },
        pointerButton(button, press) { buttons.push({button, press}); },
        pointerMove(x, y) { moves.push({x, y}); },
        pointerScroll(x, y, finish) { scrolls.push({x, y, finish}); },
    };
    const target = {};
    new Touchpad(inputController, () => true).configure({moveSpeed: 1, scrollSpeed: 1});

    const touch = (identifier, pageX, pageY) => ({identifier, pageX, pageY, target});
    const fire = (type, changedTouches, timeStamp) => {
        for (const listener of listeners.get(type) || []) {
            listener({changedTouches, timeStamp, preventDefault() {}});
        }
    };
    return {buttons, feedback, fire, gestures, moves, scrolls, touch};
};

test("single-finger tap releases the left button immediately", () => {
    const {buttons, fire, touch} = createTouchpadHarness();

    fire("touchstart", [touch(1, 20, 20)], 0);
    fire("touchend", [touch(1, 20, 20)], 100);

    assert.deepEqual(buttons, [
        {button: 0, press: true},
        {button: 0, press: false},
    ]);
});

test("holding before moving starts and finishes a drag", () => {
    const {buttons, fire, moves, touch} = createTouchpadHarness();

    fire("touchstart", [touch(1, 20, 20)], 0);
    fire("touchmove", [touch(1, 40, 20)], 400);
    fire("touchend", [touch(1, 40, 20)], 450);

    assert.deepEqual(buttons, [
        {button: 0, press: true},
        {button: 0, press: false},
    ]);
    assert.ok(moves.length > 0);
});

test("ordinary pointer movement never holds the left button", () => {
    const {buttons, fire, touch} = createTouchpadHarness();

    fire("touchstart", [touch(1, 20, 20)], 0);
    fire("touchmove", [touch(1, 40, 20)], 100);
    fire("touchmove", [touch(1, 60, 20)], 400);
    fire("touchend", [touch(1, 60, 20)], 450);

    assert.deepEqual(buttons, []);
});

test("two-finger scrolling drift does not emit a zoom gesture", () => {
    const {fire, gestures, scrolls, touch} = createTouchpadHarness();

    fire("touchstart", [touch(1, 0, 0), touch(2, 100, 0)], 0);
    fire("touchmove", [touch(1, -12, 10)], 300);
    fire("touchmove", [touch(1, -24, 20)], 320);

    assert.deepEqual(gestures, []);
    assert.ok(scrolls.some(({x, y}) => x !== 0 || y !== 0));
});

test("opposite two-finger expansion emits zoom in without keyboard text", () => {
    const {fire, gestures, touch} = createTouchpadHarness();

    fire("touchstart", [touch(1, 0, 0), touch(2, 100, 0)], 0);
    fire("touchmove", [touch(1, -20, 0), touch(2, 120, 0)], 300);

    assert.deepEqual(gestures, [4]); // GestureZoomIn
});

test("opposite two-finger contraction emits zoom out", () => {
    const {fire, gestures, touch} = createTouchpadHarness();

    fire("touchstart", [touch(1, 0, 0), touch(2, 100, 0)], 0);
    fire("touchmove", [touch(1, 20, 0), touch(2, 80, 0)], 300);

    assert.deepEqual(gestures, [5]); // GestureZoomOut
});

const performThreeFingerSwipe = (deltaX, deltaY) => {
    const harness = createTouchpadHarness();
    const starts = [
        harness.touch(1, 0, 0),
        harness.touch(2, 20, 0),
        harness.touch(3, 40, 0),
    ];
    const ends = starts.map(({identifier, pageX, pageY}) =>
        harness.touch(identifier, pageX + deltaX, pageY + deltaY));
    harness.fire("touchstart", starts, 0);
    harness.fire("touchmove", ends, 300);
    harness.fire("touchend", ends, 320);
    return harness;
};

test("three-finger swipe left switches to the next desktop", () => {
    assert.deepEqual(performThreeFingerSwipe(-60, 0).gestures, [3]); // GestureAppNext
});

test("three-finger swipe right switches to the previous desktop", () => {
    assert.deepEqual(performThreeFingerSwipe(60, 0).gestures, [2]); // GestureAppPrevious
});

test("three-finger swipe up opens the overview", () => {
    assert.deepEqual(performThreeFingerSwipe(0, -60).gestures, [0]); // GestureOverview
});

test("three-finger swipe down shows the desktop", () => {
    assert.deepEqual(performThreeFingerSwipe(0, 60).gestures, [1]); // GestureShowDesktop
});

test("three-finger horizontal swipe triggers before release and only once", () => {
    const harness = createTouchpadHarness();
    const starts = [
        harness.touch(1, 0, 0),
        harness.touch(2, 20, 0),
        harness.touch(3, 40, 0),
    ];
    const ends = starts.map(({identifier, pageX, pageY}) =>
        harness.touch(identifier, pageX - 60, pageY));

    harness.fire("touchstart", starts, 0);
    harness.fire("touchmove", ends, 300);
    assert.deepEqual(harness.gestures, [3]); // GestureAppNext
    assert.deepEqual(harness.feedback, ["下一个桌面"]);

    harness.fire("touchend", ends, 320);
    assert.deepEqual(harness.gestures, [3]);
});
