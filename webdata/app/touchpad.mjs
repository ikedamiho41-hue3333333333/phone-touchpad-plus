/*
 *    Copyright (c) 2018-2019, 2023 Unrud <unrud@outlook.com>
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

import {
    GESTURE_OVERVIEW,
    GESTURE_SHOW_DESKTOP,
    GESTURE_APP_PREVIOUS,
    GESTURE_APP_NEXT,
    GESTURE_ZOOM_IN,
    GESTURE_ZOOM_OUT,
    POINTER_BUTTON_LEFT,
    POINTER_BUTTON_MIDDLE,
    POINTER_BUTTON_RIGHT,
} from "./inputcontroller.mjs";

// [1 Touch, 2 Touches, 3 Touches] (as pixel)
const TOUCH_MOVE_THRESHOLD = [10, 8, 15];
// Max time between consecutive touches for clicking or dragging (as milliseconds)
const TOUCH_TIMEOUT = 250;
const MULTI_SWIPE_THRESHOLD = 52;
const PINCH_START_THRESHOLD = 10;
const PINCH_FINGER_MOVE_THRESHOLD = 5;
const PINCH_STEP = 22;
// [[pixel/second, multiplicator], ...]
const POINTER_ACCELERATION = [
    [0, 0],
    [87, 1],
    [173, 1],
    [553, 2],
];

const copyTouch = (touch, timeStamp) => ({
    identifier: touch.identifier,
    pageX: touch.pageX,
    pageXStart: touch.pageX,
    pageY: touch.pageY,
    pageYStart: touch.pageY,
    timeStamp: timeStamp,
});

const calculateAccelerationMult = (speed) => {
    for (let i = 0; i < POINTER_ACCELERATION.length; i += 1) {
        const s2 = POINTER_ACCELERATION[i][0];
        const a2 = POINTER_ACCELERATION[i][1];
        if (s2 <= speed) {
            continue;
        }
        if (i == 0) {
            return a2;
        }
        const s1 = POINTER_ACCELERATION[i - 1][0];
        const a1 = POINTER_ACCELERATION[i - 1][1];
        return ((speed - s1) / (s2 - s1)) * (a2 - a1) + a1;
    }
    if (POINTER_ACCELERATION.length > 0) {
        return POINTER_ACCELERATION[POINTER_ACCELERATION.length - 1][1];
    }
    return 1;
};

export default class Touchpad {
    #moveSpeed = 1;
    #scrollSpeed = 1;

    #moved = false;
    #startTimeStamp = 0;
    #lastEndTimeStamp = 0;
    #releasedCount = 0;
    #ongoingTouches = [];
    #dragging = false;
    #draggingTimeout = null;
    #gestureFingerCount = 0;
    #gestureStartCentroid = null;
    #gestureLastCentroid = null;
    #multiGestureTriggered = false;
    #twoFingerMode = "";
    #twoFingerStartCentroid = null;
    #pinchStartDistance = 0;
    #pinchLastDistance = 0;
    #pinchAccumulator = 0;
    #inputController;
    #checkAllowedCallback;

    constructor(inputController, checkAllowedCallback) {
        this.#inputController = inputController;
        this.#checkAllowedCallback = checkAllowedCallback;
        document.addEventListener("touchstart", this.#handleTouchstart.bind(this));
        document.addEventListener("touchend", this.#handleTouchend.bind(this));
        document.addEventListener("touchcancel", this.#handleTouchend.bind(this));
        document.addEventListener("touchmove", this.#handleTouchmove.bind(this));
    }

    configure(config) {
        this.#moveSpeed = config.moveSpeed;
        this.#scrollSpeed = config.scrollSpeed;
    }

    #ongoingTouchIndexById(idToFind) {
        for (let i = 0; i < this.#ongoingTouches.length; i += 1) {
            if (this.#ongoingTouches[i].identifier == idToFind) {
                return i;
            }
        }
        return -1;
    }

    #handleDraggingTimeout() {
        this.#draggingTimeout = null;
        this.#inputController.pointerButton(POINTER_BUTTON_LEFT, false);
    }

    #centroid() {
        if (this.#ongoingTouches.length == 0) {
            return null;
        }
        let x = 0;
        let y = 0;
        for (const touch of this.#ongoingTouches) {
            x += touch.pageX;
            y += touch.pageY;
        }
        return {
            x: x / this.#ongoingTouches.length,
            y: y / this.#ongoingTouches.length,
        };
    }

    #twoFingerDistance() {
        if (this.#ongoingTouches.length != 2) {
            return 0;
        }
        return Math.hypot(
            this.#ongoingTouches[0].pageX - this.#ongoingTouches[1].pageX,
            this.#ongoingTouches[0].pageY - this.#ongoingTouches[1].pageY,
        );
    }

    #fingersMovedOppositely() {
        if (this.#ongoingTouches.length != 2) {
            return false;
        }
        const movements = this.#ongoingTouches.map((touch) => ({
            x: touch.pageX - touch.pageXStart,
            y: touch.pageY - touch.pageYStart,
        }));
        if (movements.some((movement) =>
            Math.hypot(movement.x, movement.y) < PINCH_FINGER_MOVE_THRESHOLD)) {
            return false;
        }
        return movements[0].x * movements[1].x +
            movements[0].y * movements[1].y < 0;
    }

    #beginMultiGesture() {
        if (this.#ongoingTouches.length < 3 || this.#gestureFingerCount != 0) {
            return;
        }
        this.#gestureFingerCount = this.#ongoingTouches.length;
        this.#gestureStartCentroid = this.#centroid();
        this.#gestureLastCentroid = this.#gestureStartCentroid;
    }

    #feedback(message) {
        document.dispatchEvent(new CustomEvent("gesturefeedback", {detail: message}));
        navigator.vibrate?.(12);
    }

    #finishMultiGesture(allowTap = true) {
        if (this.#gestureStartCentroid == null || this.#gestureLastCentroid == null) {
            return false;
        }
        const dx = this.#gestureLastCentroid.x - this.#gestureStartCentroid.x;
        const dy = this.#gestureLastCentroid.y - this.#gestureStartCentroid.y;
        if (Math.max(Math.abs(dx), Math.abs(dy)) < MULTI_SWIPE_THRESHOLD) {
            if (allowTap && this.#gestureFingerCount == 3) {
                this.#inputController.pointerButton(POINTER_BUTTON_MIDDLE, true);
                this.#inputController.pointerButton(POINTER_BUTTON_MIDDLE, false);
                this.#feedback("三指轻点 · 中键");
                return true;
            }
            return false;
        }
        if (Math.abs(dx) > Math.abs(dy)) {
            if (dx < 0) {
                if (this.#inputController.gesture(GESTURE_APP_NEXT)) {
                    this.#feedback("下一个桌面");
                }
            } else {
                if (this.#inputController.gesture(GESTURE_APP_PREVIOUS)) {
                    this.#feedback("上一个桌面");
                }
            }
        } else if (dy < 0) {
            if (this.#inputController.gesture(GESTURE_OVERVIEW)) {
                this.#feedback("活动概览");
            }
        } else {
            if (this.#inputController.gesture(GESTURE_SHOW_DESKTOP)) {
                this.#feedback("显示桌面");
            }
        }
        return true;
    }

    #resetGestureState() {
        this.#gestureFingerCount = 0;
        this.#gestureStartCentroid = null;
        this.#gestureLastCentroid = null;
        this.#multiGestureTriggered = false;
        this.#twoFingerMode = "";
        this.#twoFingerStartCentroid = null;
        this.#pinchStartDistance = 0;
        this.#pinchLastDistance = 0;
        this.#pinchAccumulator = 0;
    }

    #handleTouchstart(event) {
        // Might get called multiple times for the same touches
        if (this.#ongoingTouches.length == 0) {
            this.#startTimeStamp = event.timeStamp;
            this.#moved = false;
            this.#resetGestureState();
        }
        const touches = event.changedTouches;
        let foundTouch = false;
        for (let i = 0; i < touches.length; i += 1) {
            if (this.#ongoingTouches.length == 0 &&
                !this.#checkAllowedCallback(touches[i].target)) {
                continue;
            }
            foundTouch = true;
            const touch = copyTouch(touches[i], event.timeStamp);
            const idx = this.#ongoingTouchIndexById(touch.identifier);
            if (idx < 0) {
                this.#ongoingTouches.push(touch);
            } else {
                this.#ongoingTouches[idx] = touch;
            }
        }
        if (!foundTouch) {
            return;
        }
        event.preventDefault();
        this.#lastEndTimeStamp = 0;
        if (this.#draggingTimeout != null) {
            clearTimeout(this.#draggingTimeout);
            this.#draggingTimeout = null;
            this.#dragging = true;
        }
        if (this.#ongoingTouches.length == 2) {
            this.#twoFingerStartCentroid = this.#centroid();
            this.#pinchStartDistance = this.#twoFingerDistance();
            this.#pinchLastDistance = this.#pinchStartDistance;
        }
        this.#beginMultiGesture();
        this.#inputController.pointerScroll(0, 0, true);
    }

    #handleTouchend(event) {
        const touches = event.changedTouches;
        let foundTouch = false;
        for (let i = 0; i < touches.length; i += 1) {
            const idx = this.#ongoingTouchIndexById(touches[i].identifier);
            if (idx < 0) {
                continue;
            }
            foundTouch = true;
            this.#ongoingTouches[idx].pageX = touches[i].pageX;
            this.#ongoingTouches[idx].pageY = touches[i].pageY;
        }
        if (this.#gestureFingerCount >= 3) {
            this.#gestureLastCentroid = this.#centroid();
        }
        for (let i = 0; i < touches.length; i += 1) {
            const idx = this.#ongoingTouchIndexById(touches[i].identifier);
            if (idx < 0) {
                continue;
            }
            this.#ongoingTouches.splice(idx, 1);
            this.#releasedCount += 1;
        }
        if (!foundTouch) {
            return;
        }
        event.preventDefault();
        this.#lastEndTimeStamp = event.timeStamp;
        this.#inputController.pointerScroll(0, 0, true);
        if (this.#releasedCount > TOUCH_MOVE_THRESHOLD.length) {
            this.#moved = true;
        }
        if (this.#ongoingTouches.length == 0 && this.#releasedCount >= 1) {
            if (this.#dragging) {
                this.#dragging = false;
                this.#inputController.pointerButton(POINTER_BUTTON_LEFT, false);
            }
            const handledMultiGesture = this.#gestureFingerCount >= 3 &&
                (this.#multiGestureTriggered || this.#finishMultiGesture());
            if (handledMultiGesture) {
                this.#moved = true;
            }
            if (!handledMultiGesture && !this.#moved &&
                event.timeStamp - this.#startTimeStamp < TOUCH_TIMEOUT) {
                let button = 0;
                if (this.#releasedCount == 1) {
                    button = POINTER_BUTTON_LEFT;
                } else if (this.#releasedCount == 2) {
                    button = POINTER_BUTTON_RIGHT;
                } else if (this.#releasedCount == 3) {
                    button = POINTER_BUTTON_MIDDLE;
                }
                this.#inputController.pointerButton(button, true);
                if (button == POINTER_BUTTON_LEFT) {
                    this.#draggingTimeout = setTimeout(
                        this.#handleDraggingTimeout.bind(this), TOUCH_TIMEOUT);
                } else {
                    this.#inputController.pointerButton(button, false);
                }
            }
            this.#releasedCount = 0;
            this.#resetGestureState();
        }
    }

    #handleTouchmove(event) {
        let sumX = 0;
        let sumY = 0;
        const touches = event.changedTouches;
        let foundTouch = false;
        for (let i = 0; i < touches.length; i += 1) {
            const idx = this.#ongoingTouchIndexById(touches[i].identifier);
            if (idx < 0) {
                continue;
            }
            foundTouch = true;
            if (!this.#moved) {
                const dist = Math.sqrt(
                    Math.pow(touches[i].pageX - this.#ongoingTouches[idx].pageXStart, 2) +
                    Math.pow(touches[i].pageY - this.#ongoingTouches[idx].pageYStart, 2)
                );
                if (this.#ongoingTouches.length > TOUCH_MOVE_THRESHOLD.length ||
                    dist > TOUCH_MOVE_THRESHOLD[this.#ongoingTouches.length - 1] ||
                    event.timeStamp - this.#startTimeStamp >= TOUCH_TIMEOUT) {
                    this.#moved = true;
                }
            }
            const dx = touches[i].pageX - this.#ongoingTouches[idx].pageX;
            const dy = touches[i].pageY - this.#ongoingTouches[idx].pageY;
            const timeDelta = event.timeStamp - this.#ongoingTouches[idx].timeStamp;
            sumX += dx * calculateAccelerationMult(Math.abs(dx) / timeDelta * 1000);
            sumY += dy * calculateAccelerationMult(Math.abs(dy) / timeDelta * 1000);
            this.#ongoingTouches[idx].pageX = touches[i].pageX;
            this.#ongoingTouches[idx].pageY = touches[i].pageY;
            this.#ongoingTouches[idx].timeStamp = event.timeStamp;
        }
        if (!foundTouch) {
            return;
        }
        event.preventDefault();
        this.#beginMultiGesture();
        if (this.#gestureFingerCount >= 3) {
            if (this.#ongoingTouches.length >= 3) {
                this.#gestureFingerCount = Math.max(
                    this.#gestureFingerCount, this.#ongoingTouches.length);
                this.#gestureLastCentroid = this.#centroid();
            }
            if (!this.#multiGestureTriggered && this.#finishMultiGesture(false)) {
                this.#multiGestureTriggered = true;
            }
            this.#moved = true;
            return;
        }
        if (this.#moved && event.timeStamp - this.#lastEndTimeStamp >= TOUCH_TIMEOUT) {
            if (this.#ongoingTouches.length == 1 || this.#dragging) {
                this.#inputController.pointerMove(
                    sumX * this.#moveSpeed, sumY * this.#moveSpeed);
            } else if (this.#ongoingTouches.length == 2) {
                const centroid = this.#centroid();
                const distance = this.#twoFingerDistance();
                const distanceFromStart = distance - this.#pinchStartDistance;
                const centroidFromStart = this.#twoFingerStartCentroid == null ? 0 : Math.hypot(
                    centroid.x - this.#twoFingerStartCentroid.x,
                    centroid.y - this.#twoFingerStartCentroid.y,
                );
                if (this.#twoFingerMode == "" &&
                    Math.abs(distanceFromStart) >= PINCH_START_THRESHOLD &&
                    Math.abs(distanceFromStart) > centroidFromStart &&
                    this.#fingersMovedOppositely()) {
                    this.#twoFingerMode = "pinch";
                } else if (this.#twoFingerMode == "" && centroidFromStart >= 8) {
                    this.#twoFingerMode = "scroll";
                }
                if (this.#twoFingerMode == "pinch") {
                    this.#pinchAccumulator += distance - this.#pinchLastDistance;
                    while (Math.abs(this.#pinchAccumulator) >= PINCH_STEP) {
                        const zoomIn = this.#pinchAccumulator > 0;
                        const sent = this.#inputController.gesture(
                            zoomIn ? GESTURE_ZOOM_IN : GESTURE_ZOOM_OUT);
                        this.#pinchAccumulator += zoomIn ? -PINCH_STEP : PINCH_STEP;
                        if (sent) {
                            this.#feedback(zoomIn ? "放大" : "缩小");
                        }
                    }
                } else if (this.#twoFingerMode == "scroll") {
                    this.#inputController.pointerScroll(
                        -sumX * this.#scrollSpeed, -sumY * this.#scrollSpeed, false);
                }
                this.#pinchLastDistance = distance;
            }
        }
    }
}
