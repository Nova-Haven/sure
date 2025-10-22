import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "endpoint",
    "modelSelect",
    "blacklist",
    "refreshButton",
    "providerInfo",
  ];

  connect() {
    // Initialize immediately; Stimulus connects when the element is ready
    this.initializeUI();

    // Ensure provider info is restored after Turbo-driven updates/saves
    this._handleTurboEvent = () => {
      // Defer to allow DOM to settle after frame/form replacement
      setTimeout(() => this.updateProviderInfo(), 0);
    };
    document.addEventListener("turbo:load", this._handleTurboEvent);
    document.addEventListener("turbo:frame-load", this._handleTurboEvent);
    document.addEventListener("turbo:submit-end", this._handleTurboEvent);
  }

  initializeUI() {
    // Always update provider info first
    this.updateProviderInfo();

    // Check current state
    const currentOptions = Array.from(this.modelSelectTarget.options);
    const hasSelectedModel =
      this.modelSelectTarget.value && this.modelSelectTarget.value !== "";
    const hasEndpoint =
      this.hasEndpointTarget && this.endpointTarget.value.trim();
    const hasLimitedOptions = currentOptions.length <= 2; // Just current model + prompt option

    // Only auto-refresh if we have very limited options and an endpoint
    // The server should now preserve models from session
    if (hasLimitedOptions && hasEndpoint && hasSelectedModel) {
      setTimeout(() => this.refreshModels(), 100);
    } else if (!hasSelectedModel && hasEndpoint && hasLimitedOptions) {
      // If no model selected but we have an endpoint, populate options
      setTimeout(() => this.refreshModels(), 100);
    } else if (!hasSelectedModel && !hasEndpoint && hasLimitedOptions) {
      // No model, no endpoint, load defaults
      this.loadDefaultModels();
    }
  }

  disconnect() {
    // Controller disconnected
    if (this._handleTurboEvent) {
      document.removeEventListener("turbo:load", this._handleTurboEvent);
      document.removeEventListener("turbo:frame-load", this._handleTurboEvent);
      document.removeEventListener("turbo:submit-end", this._handleTurboEvent);
    }
  }

  async refreshModels() {
    const refreshButton = this.refreshButtonTarget;

    // Store original HTML content to preserve icon
    const originalHTML = refreshButton.innerHTML;
    const originalDisabledState = refreshButton.disabled;

    // Extract just the text content while preserving icon
    const textNodes = Array.from(refreshButton.childNodes).filter(
      (node) =>
        node.nodeType === Node.TEXT_NODE && node.textContent.trim() !== ""
    );
    const originalText =
      textNodes.length > 0 ? textNodes[0].textContent.trim() : "Refresh models";

    const modelSelect = this.modelSelectTarget;

    // Store the current value BEFORE clearing the select
    const originalValue = modelSelect.value;

    // Update button text while preserving icon structure
    refreshButton.innerHTML = refreshButton.innerHTML.replace(
      originalText,
      "Refreshing..."
    );
    refreshButton.disabled = true;

    // Show loading state in select
    modelSelect.innerHTML = '<option value="">Loading models...</option>';
    modelSelect.disabled = true;

    try {
      const endpoint = this.endpointTarget.value.trim();
      const tokenInput = document.querySelector(
        'input[name="setting[openai_access_token]"]'
      );
      const token = tokenInput ? tokenInput.value : "";

      // If no endpoint, load default models
      if (!endpoint) {
        this.loadDefaultModels(originalValue);
        return;
      }

      const csrfToken = document.querySelector(
        'meta[name="csrf-token"]'
      )?.content;

      const response = await fetch("/settings/hosting/openai_models", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        body: JSON.stringify({
          endpoint: endpoint,
          access_token: token !== "********" ? token : null,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        this.updateModelOptions(data.models, originalValue);
        this.updateProviderInfo();
      } else {
        const errorData = await response.json();
        // Fall back to default models if fetch fails
        if (errorData.models) {
          this.updateModelOptions(errorData.models, originalValue);
        } else {
          this.loadDefaultModels(originalValue);
        }
      }
    } catch (error) {
      this.loadDefaultModels(originalValue);
    } finally {
      // Restore original button content and state
      refreshButton.innerHTML = originalHTML;
      refreshButton.disabled = originalDisabledState;
      // Always enable the model select to allow overriding ENV configuration
      modelSelect.disabled = false;
    }
  }

  loadDefaultModels(preservedValue = null) {
    // Load basic default models when no endpoint is configured
    const defaultModels = ["gpt-4o", "gpt-4.1"];
    this.updateModelOptions(defaultModels, preservedValue);
  }

  updateModelOptions(models, preservedValue = null) {
    const select = this.modelSelectTarget;

    // Use preserved value if provided, otherwise current value
    const currentValue =
      preservedValue !== null ? preservedValue : select.value;

    // Completely clear all existing options
    select.innerHTML = "";

    // Add prompt option
    const promptOption = document.createElement("option");
    promptOption.value = "";
    promptOption.textContent = "Select a model...";
    select.appendChild(promptOption);

    // Add new model options
    let selectedOptionFound = false;
    models.forEach((model) => {
      const option = document.createElement("option");
      option.value = model;
      option.textContent = model;
      // Select this option if it matches the current value
      if (model === currentValue) {
        option.selected = true;
        selectedOptionFound = true;
      }
      select.appendChild(option);
    });

    // If current value is not in new list, keep it selected but mark as custom
    if (currentValue && !selectedOptionFound && currentValue !== "") {
      const customOption = document.createElement("option");
      customOption.value = currentValue;
      customOption.textContent = `${currentValue} (custom)`;
      customOption.selected = true;
      select.appendChild(customOption);
    }
  }

  updateProviderInfo() {
    if (!this.hasProviderInfoTarget) {
      return;
    }

    // Be resilient if the endpoint field is not present in this DOM fragment
    const endpoint = this.hasEndpointTarget
      ? this.endpointTarget.value.trim()
      : "";

    let providerType = "OpenAI";
    let providerInfo = "Official OpenAI API";

    if (!endpoint) {
      providerInfo = "Default OpenAI endpoint";
    } else if (endpoint.includes("openai.com")) {
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
      providerType = "Custom";
      providerInfo = "Custom endpoint";
    }

    const finalText = `Provider: ${providerType} - ${providerInfo}`;
    this.providerInfoTarget.textContent = finalText;

    // Ensure the provider info is visible
    this.providerInfoTarget.style.display = "";
  }

  blacklistChanged() {
    // Trigger form submission to save changes
    const form = this.element.closest("form");
    if (form) {
      form.requestSubmit();
    }
  }

  endpointChanged() {
    this.updateProviderInfo();
    // Refresh models when endpoint changes
    this.refreshModels();
  }
}
