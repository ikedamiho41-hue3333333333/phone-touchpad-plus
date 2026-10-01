const INTERACTIVE_SELECTOR = "button, input, textarea, select, a";

export const allowsTouchpadInput = (target) =>
    target?.closest?.(".touch-input") != null &&
    target.closest(INTERACTIVE_SELECTOR) == null;
