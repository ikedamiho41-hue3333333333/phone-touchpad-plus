import assert from "node:assert/strict";
import test from "node:test";

import {applyGestureCapability} from "../webdata/app/capabilities.mjs";
import InputController from "../webdata/app/inputcontroller.mjs";

const createSocket = () => ({
    sent: [],
    send(message) {
        this.sent.push(message);
    },
});

const createCapabilityElement = () => ({
    hidden: false,
    classList: {
        toggle(name, force) {
            assert.equal(name, "hidden");
            this.owner.hidden = force;
        },
        owner: null,
    },
});

test("gesture capability sends commands and reveals enhanced controls", () => {
    const socket = createSocket();
    const inputController = new InputController(socket);
    inputController.configure({updateRate: 0, capabilities: {gestures: true}});

    assert.equal(inputController.gesture(2), true);
    assert.deepEqual(socket.sent, ["g2"]);

    const element = createCapabilityElement();
    element.classList.owner = element;
    assert.equal(applyGestureCapability({capabilities: {gestures: true}}, [element]), true);
    assert.equal(element.hidden, false);
});

test("pointer click keeps the button down long enough for macOS", async () => {
    const socket = createSocket();
    const inputController = new InputController(socket);

    inputController.pointerClick(0);
    assert.deepEqual(socket.sent, ["r0", "b0;1"]);
    await new Promise((resolve) => setTimeout(resolve, 10));
    assert.deepEqual(socket.sent, ["r0", "b0;1"]);
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.deepEqual(socket.sent, ["r0", "b0;1", "b0;0"]);
});

test("explicit double click sends one deliberate two-click sequence", async () => {
    const socket = createSocket();
    const inputController = new InputController(socket);

    inputController.pointerDoubleClick(0);
    assert.deepEqual(socket.sent, ["r0", "b0;1"]);
    await new Promise((resolve) => setTimeout(resolve, 45));
    assert.deepEqual(socket.sent, ["r0", "b0;1", "b0;0"]);
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.deepEqual(socket.sent, ["r0", "b0;1", "b0;0", "b0;1"]);
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.deepEqual(socket.sent, ["r0", "b0;1", "b0;0", "b0;1", "b0;0"]);
});

for (const [name, config] of [
    ["explicitly disabled", {updateRate: 0, capabilities: {gestures: false}}],
    ["missing from an older server", {updateRate: 0}],
]) {
    test(`${name} gesture capability suppresses gestures but preserves pointer input`, () => {
        const socket = createSocket();
        const inputController = new InputController(socket);
        inputController.configure(config);

        assert.equal(inputController.gesture(3), false);
        inputController.pointerButton(0, true);
        inputController.pointerMove(3, -2);
        inputController.pointerScroll(0, 20, false);
        assert.deepEqual(socket.sent, ["b0;1", "m3;-2", "s0;20"]);

        const element = createCapabilityElement();
        element.classList.owner = element;
        assert.equal(applyGestureCapability(config, [element]), false);
        assert.equal(element.hidden, true);
    });
}
