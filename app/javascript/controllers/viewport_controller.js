import { Controller } from "@hotwired/stimulus"

// Sets a CSS variable --vh to 1% of the viewport height to avoid mobile 100vh issues
// and adds an app-no-overscroll class to html/body to reduce pull-to-refresh/overscroll gaps.
export default class extends Controller {
  connect() {
    this.setVh()
    this.enableNoOverscroll()
    this.onResize = this.setVh.bind(this)
    window.addEventListener('resize', this.onResize, { passive: true })
    window.addEventListener('orientationchange', this.onResize, { passive: true })
    window.addEventListener('load', () => { setTimeout(this.setVh.bind(this), 250) }, { passive: true })
  }

  disconnect() {
    window.removeEventListener('resize', this.onResize)
    window.removeEventListener('orientationchange', this.onResize)
  }

  setVh() {
    const vh = window.innerHeight * 0.01
    document.documentElement.style.setProperty('--vh', `${vh}px`)
  }

  enableNoOverscroll() {
    document.documentElement.classList.add('app-no-overscroll')
    document.body.classList.add('app-no-overscroll')
  }
}
