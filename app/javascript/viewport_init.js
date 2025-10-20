// Small, fast initial set of --vh to avoid initial rendering without a viewport value.
// This module runs immediately when imported by the app entry so the --vh
// custom property is available early in the lifecycle.
(() => {
  try {
    const vh = window.innerHeight * 0.01;
    document.documentElement.style.setProperty("--vh", `${vh}px`);
  } catch (e) {
    // noop
  }
})();
