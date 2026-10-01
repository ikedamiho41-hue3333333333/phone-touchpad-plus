import assert from "node:assert/strict";
import test from "node:test";

import {allowsTouchpadInput} from "../webdata/app/touch-target.mjs";

const target = ({insidePad, interactive = false}) => ({
    closest(selector) {
        if (selector == ".touch-input") {
            return insidePad ? {} : null;
        }
        if (selector == "button, input, textarea, select, a") {
            return interactive ? {} : null;
        }
        return null;
    },
});

test("content nested inside the pad accepts touchpad input", () => {
    assert.equal(allowsTouchpadInput(target({insidePad: true})), true);
});

test("buttons inside the pad keep their own action", () => {
    assert.equal(allowsTouchpadInput(target({insidePad: true, interactive: true})), false);
});

test("content outside a touch input scene is ignored", () => {
    assert.equal(allowsTouchpadInput(target({insidePad: false})), false);
});
