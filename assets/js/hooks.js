let Hooks = {}

Hooks.LocalTime = {
    mounted() { this.format() },
    updated() { this.format() },
    format() {
        const utc = this.el.dataset.utc
        if (!utc) return
        const date = new Date(utc)
        const prefix = this.el.dataset.prefix || ""
        this.el.textContent = prefix + date.toLocaleString([], {
            month: "2-digit", day: "2-digit", year: "numeric",
            hour: "2-digit", minute: "2-digit"
        })
    }
}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

export default Hooks