import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "endpoint",
    "modelSelect",
    "modelContainer",
    "blacklistContainer",
    "refreshButton",
    "providerInfo",
  ];

  connect() {
    this.updateProviderInfo();
  }

  async refreshModels() {
    const refreshButton = this.refreshButtonTarget;
    const originalText = refreshButton.textContent;

    refreshButton.textContent = "Refreshing...";
    refreshButton.disabled = true;

    try {
      const endpoint = this.endpointTarget.value;
      const token = document.querySelector(
        'input[name="setting[openai_access_token]"]'
      ).value;

      const response = await fetch("/settings/hosting/openai_models", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
        },
        body: JSON.stringify({
          endpoint: endpoint,
          access_token: token !== "********" ? token : null,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        this.updateModelOptions(data.models);
        this.updateProviderInfo();
      } else {
        console.error("Failed to refresh models");
      }
    } catch (error) {
      console.error("Error refreshing models:", error);
    } finally {
      refreshButton.textContent = originalText;
      refreshButton.disabled = false;
    }
  }

  updateModelOptions(models) {
    const select = this.modelSelectTarget;
    const currentValue = select.value;

    // Clear existing options
    select.innerHTML = "";

    // Add new options
    models.forEach((model) => {
      const option = document.createElement("option");
      option.value = model;
      option.textContent = model;
      option.selected = model === currentValue;
      select.appendChild(option);
    });

    // If current value is not in new list, select first option
    if (!models.includes(currentValue) && models.length > 0) {
      select.value = models[0];
      // Trigger change event to submit form
      select.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }

  updateProviderInfo() {
    const endpoint = this.endpointTarget.value;
    let providerType = "Custom";
    let providerInfo = "";

    if (endpoint.includes("openai.com")) {
      providerType = "OpenAI";
      providerInfo = "Official OpenAI API";
    } else if (
      endpoint.includes("localhost") ||
      endpoint.includes("127.0.0.1") ||
      endpoint.includes("0.0.0.0") ||
      endpoint.includes("host.docker.internal")
    ) {
      providerType = "Local";
      providerInfo = "Local server (e.g., LM Studio)";
    } else if (endpoint.includes("openrouter.ai")) {
      providerType = "OpenRouter";
      providerInfo = "OpenRouter proxy service";
    } else {
      providerInfo = "Custom endpoint";
    }

    this.providerInfoTarget.textContent = `Provider: ${providerType} - ${providerInfo}`;
  }

  addBlacklistItem() {
    const container = this.blacklistContainerTarget;
    const newItem = document.createElement("div");
    newItem.className = "flex items-center gap-2";
    newItem.innerHTML = `
      <input type="text" 
             name="setting[openai_model_blacklist][]" 
             class="flex-1 rounded-md border-secondary shadow-sm focus:border-accent focus:ring-accent sm:text-sm"
             placeholder="e.g., text-embedding, whisper, dall-e">
      <button type="button" 
              class="rounded-md border border-destructive bg-destructive-surface px-3 py-2 text-sm text-destructive hover:bg-destructive-surface-hover"
              data-action="click->openai-settings#removeBlacklistItem">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M18 6 6 18"/><path d="m6 6 12 12"/>
        </svg>
      </button>
    `;

    // Insert before the "Add" button
    const addButton = container.querySelector(
      'button[data-action="click->openai-settings#addBlacklistItem"]'
    );
    container.insertBefore(newItem, addButton);
  }

  removeBlacklistItem(event) {
    event.target.closest(".flex").remove();

    // Trigger form submission to save changes
    const form = this.element.closest("form");
    if (form) {
      form.requestSubmit();
    }
  }

  endpointChanged() {
    this.updateProviderInfo();
  }
}
