import { Controller } from "@hotwired/stimulus";
import { Alert } from "bootstrap";

// Connects to data-controller="flash"
export default class extends Controller {
  static values = { delay: { type: Number, default: 2000 } };

  connect() {
    this.timeout = setTimeout(() => {
      Alert.getOrCreateInstance(this.element).close();
    }, this.delayValue);
  }

  disconnect() {
    clearTimeout(this.timeout);
  }
}
