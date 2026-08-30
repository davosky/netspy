import { Controller } from "@hotwired/stimulus"

// Polls a LanscanRun's JSON endpoint and drives the progress bar: percentage,
// elapsed time, and a final message with the total time once the scan ends.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1500 },
    doneTemplate: String, // "... %{duration} ... %{count} ..."
    failText: String,
  }
  static targets = ["bar", "percent", "elapsed", "status"]

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async tick() {
    let data
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      data = await response.json()
    } catch {
      return
    }

    const percent = Math.min(100, Math.max(0, data.percent || 0))
    this.barTarget.style.width = `${percent}%`
    this.barTarget.setAttribute("aria-valuenow", Math.round(percent))
    if (this.hasPercentTarget) this.percentTarget.textContent = `${percent}%`
    if (this.hasElapsedTarget && data.elapsed != null) {
      this.elapsedTarget.textContent = this.formatDuration(data.elapsed)
    }

    if (data.status === "completed" || data.status === "failed") {
      clearInterval(this.timer)
      this.barTarget.classList.remove("progress-bar-striped", "progress-bar-animated")
      this.finish(data)
    }
  }

  finish(data) {
    if (data.status === "completed") {
      this.barTarget.style.width = "100%"
      this.statusTarget.textContent = this.doneTemplateValue
        .replace("%{duration}", this.formatDuration(data.elapsed))
        .replace("%{hosts}", data.hosts_found)
    } else {
      this.barTarget.classList.add("bg-danger")
      this.statusTarget.textContent = data.error || this.failTextValue
      this.statusTarget.classList.add("text-danger")
    }
    this.statusTarget.hidden = false
  }

  formatDuration(seconds) {
    const total = Math.round(seconds || 0)
    const minutes = Math.floor(total / 60)
    return `${minutes}:${String(total % 60).padStart(2, "0")}`
  }
}
