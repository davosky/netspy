import { Controller } from "@hotwired/stimulus"

// Polls a LanscanRun's JSON endpoint and drives the progress bar: percentage,
// elapsed time, and a final message with the total time once the scan ends.
// When a scan that was still running finishes, it refreshes the page so the
// results list below picks up the new rows.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1500 },
    doneTemplate: String, // "... %{duration} ... %{hosts} ..."
    failText: String,
  }
  static targets = ["running", "bar", "percent", "elapsed", "status"]

  connect() {
    this.wasActive = false
    this.tick()
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.refreshTimer)
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
      this.finish(data)
      // Only act if we actually watched the scan run (not when the page just
      // loaded on an already-finished run) — avoids a reload loop.
      if (this.wasActive) {
        this.resetForm()
        this.refreshTimer = setTimeout(() => this.refreshPage(), 600)
      }
    } else {
      this.wasActive = true
    }
  }

  // Back to the initial state (form.reset() puts the LAN <select> back to its
  // first option).
  resetForm() {
    document.getElementById("lanscan-launch-form")?.reset()
  }

  finish(data) {
    if (this.hasRunningTarget) this.runningTarget.hidden = true

    if (data.status === "completed") {
      this.statusTarget.textContent = this.doneTemplateValue
        .replace("%{duration}", this.formatDuration(data.elapsed))
        .replace("%{hosts}", data.hosts_found)
    } else {
      this.statusTarget.textContent = data.error || this.failTextValue
      this.statusTarget.classList.add("text-danger")
    }
    this.statusTarget.hidden = false
  }

  refreshPage() {
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }

  formatDuration(seconds) {
    const total = Math.round(seconds || 0)
    const minutes = Math.floor(total / 60)
    return `${minutes}:${String(total % 60).padStart(2, "0")}`
  }
}
