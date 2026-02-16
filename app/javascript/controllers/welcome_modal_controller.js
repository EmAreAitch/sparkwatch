import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal"]

    connect() {
        if (!localStorage.getItem("sparkwatch_welcomed")) {
            this.show()
        }
    }

    dismiss() {
        localStorage.setItem("sparkwatch_welcomed", "true")
        this.hide()
    }

    reopen() {
        this.show()
    }

    show() {
        this.modalTarget.classList.remove("hidden")
        requestAnimationFrame(() => {
            this.modalTarget.querySelector("[data-fade]").classList.remove("opacity-0")
        })
    }

    hide() {
        const inner = this.modalTarget.querySelector("[data-fade]")
        inner.classList.add("opacity-0")
        setTimeout(() => this.modalTarget.classList.add("hidden"), 200)
    }
}
