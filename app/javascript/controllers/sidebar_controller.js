import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay"]
  static classes = ["open"]

  open() {
    this.sidebarTarget.classList.remove(this.openClass)
    this.overlayTarget.classList.remove("hidden")
  }

  close() {
    this.sidebarTarget.classList.add(this.openClass)
    this.overlayTarget.classList.add("hidden")
  }

  connect() {
    this.close()
  }
}
