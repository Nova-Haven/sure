import { Controller } from "@hotwired/stimulus";

// Sets a CSS variable --vh to 1% of the viewport height to avoid mobile 100vh issues
// and adds an app-no-overscroll class to html/body to reduce pull-to-refresh/overscroll gaps.
export default class extends Controller {
  connect() {
    this.setVh();
    this.enableNoOverscroll();
    this.enablePwaTouchBlock();
    this.onResize = this.setVh.bind(this);
    window.addEventListener("resize", this.onResize, { passive: true });
    window.addEventListener("orientationchange", this.onResize, {
      passive: true,
    });
    window.addEventListener(
      "load",
      () => {
        setTimeout(this.setVh.bind(this), 250);
      },
      { passive: true }
    );
  }

  setVh() {
    const vh = window.innerHeight * 0.01;
    document.documentElement.style.setProperty("--vh", `${vh}px`);
  }

  enableNoOverscroll() {
    document.documentElement.classList.add("app-no-overscroll");
    document.body.classList.add("app-no-overscroll");
  }

  // When running as a PWA (standalone/installed), iOS/Android can still allow
  // the outer viewport to be pulled/bounced. Install touch handlers that
  // prevent scrolling the document while still allowing inner scrollable
  // elements to function normally.
  enablePwaTouchBlock() {
    if (!this.isStandalone()) return;

    this._touch = { startY: 0, lastY: 0, target: null };

    this._onTouchStart = (e) => {
      if (!e.touches || e.touches.length !== 1) return;
      this._touch.startY = e.touches[0].clientY;
      this._touch.lastY = this._touch.startY;
      this._touch.target = e.target;
    };

    // Allow inner scrollables but prevent gestures that would overscroll the
    // root document. We must use non-passive to be able to preventDefault.
    this._onTouchMove = (e) => {
      if (!e.touches || e.touches.length !== 1) return;
      const curY = e.touches[0].clientY;
      const deltaY = curY - this._touch.lastY;
      this._touch.lastY = curY;

      const scrollable = this.findScrollableAncestor(this._touch.target);

      if (!scrollable) {
        // No inner scrollable — prevent any document scroll
        e.preventDefault();
        return;
      }

      // If the scrollable element is at the top and the user is pulling down,
      // prevent the event so it doesn't bubble to the document and cause
      // overscroll. Likewise for bottom.
      const atTop = scrollable.scrollTop <= 0;
      const atBottom =
        scrollable.scrollTop + scrollable.clientHeight >=
        scrollable.scrollHeight - 1;

      if ((atTop && deltaY > 0) || (atBottom && deltaY < 0)) {
        e.preventDefault();
      }
    };

    this._onTouchEnd = () => {
      this._touch.startY = 0;
      this._touch.lastY = 0;
      this._touch.target = null;
    };

    document.addEventListener("touchstart", this._onTouchStart, {
      passive: true,
    });
    document.addEventListener("touchmove", this._onTouchMove, {
      passive: false,
    });
    document.addEventListener("touchend", this._onTouchEnd, { passive: true });
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize);
    window.removeEventListener("orientationchange", this.onResize);
    if (this._onTouchStart)
      document.removeEventListener("touchstart", this._onTouchStart);
    if (this._onTouchMove)
      document.removeEventListener("touchmove", this._onTouchMove);
    if (this._onTouchEnd)
      document.removeEventListener("touchend", this._onTouchEnd);
  }

  isStandalone() {
    try {
      return (
        (window.matchMedia &&
          window.matchMedia("(display-mode: standalone)").matches) ||
        window.navigator.standalone ||
        window.matchMedia("(display-mode: fullscreen)").matches
      );
    } catch (e) {
      return false;
    }
  }

  findScrollableAncestor(el) {
    while (el && el !== document.documentElement) {
      try {
        const style = window.getComputedStyle(el);
        const overflowY = style.overflowY;
        const canScroll =
          (overflowY === "auto" || overflowY === "scroll") &&
          el.scrollHeight > el.clientHeight;
        if (canScroll) return el;
      } catch (e) {
        // ignore tainted nodes
      }
      el = el.parentElement;
    }
    return null;
  }
}
