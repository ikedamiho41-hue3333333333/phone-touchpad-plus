export const gestureCapabilityEnabled = (config) => {
    return config.capabilities?.gestures === true;
};

export const applyGestureCapability = (config, elements) => {
    const enabled = gestureCapabilityEnabled(config);
    for (const element of elements) {
        element.classList.toggle("hidden", !enabled);
    }
    return enabled;
};
