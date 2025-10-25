import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "endpoint",
    "modelSelect",
    "blacklist",
    "whitelist",
    "blacklistContainer",
    "whitelistContainer",
    "suggestionsList",
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
    // Keep a copy for re-filtering and suggestions
    this.lastModels = Array.isArray(models) ? [...models] : [];

    // Use preserved value if provided, otherwise current value
    const currentValue =
      preservedValue !== null ? preservedValue : select.value;

    // Apply whitelist/blacklist filtering
    const filteredModels = this.filterModels(models);

    // Update datalist suggestions (unfiltered for better discovery)
    this.updateSuggestions(this.lastModels);

    // Completely clear all existing options
    select.innerHTML = "";

    // Add prompt option
    const promptOption = document.createElement("option");
    promptOption.value = "";
    promptOption.textContent = "Select a model...";
    select.appendChild(promptOption);

    // Add new model options
    let selectedOptionFound = false;
    filteredModels.forEach((model) => {
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

  // Returns a new array filtered by blacklist/whitelist rules
  filterModels(models) {
    // Gather blacklist as substrings (case-insensitive)
    const blacklist = this.hasBlacklistTarget
      ? this._gatherList(this.blacklistTargets)
      : [];
    // Gather whitelist as exact model IDs (case-insensitive match)
    const whitelist = this.hasWhitelistTarget
      ? this._gatherList(this.whitelistTargets)
      : [];

    // Precompute lowercase sets for quick checks
    const whitelistSet = new Set(whitelist);

    return models.filter((model) => {
      const modelLc = model.toLowerCase();
      const isWhitelisted = whitelistSet.has(modelLc);

      // If exactly whitelisted, always include
      if (isWhitelisted) return true;

      // Otherwise, check blacklist substrings
      const isBlacklisted = blacklist.some(
        (blk) => blk && modelLc.includes(blk)
      );
      return !isBlacklisted;
    });
  }

  // Split by comma/newline, trim, lower-case, and remove empties
  _parseList(raw) {
    if (!raw) return [];
    return raw
      .split(/[\n,]/)
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0);
  }

  // Flatten values from multiple inputs into a normalized array
  _gatherList(targets) {
    const values = [];
    targets.forEach((el) => {
      const v = (el.value || "").trim();
      if (v.length > 0) values.push(v.toLowerCase());
    });
    return values;
  }

  // Populate the datalist used for suggestions
  updateSuggestions(models) {
    if (!this.hasSuggestionsListTarget) return;
    const unique = Array.from(new Set(models));
    this.suggestionsListTarget.innerHTML = unique
      .map((m) => `<option value="${m}"></option>`)
      .join("");
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

  blacklistChanged(event) {
    const value = (event?.target?.value || "").trim();
    // Only submit if non-empty; keep blank rows unsaved so users can type
    if (value.length > 0) {
      const form = this.element.closest("form");
      if (form) {
        this._markListChanged("blacklist", form);
        form.requestSubmit();
      }
    }
    if (this.lastModels) this.updateModelOptions(this.lastModels);
  }

  whitelistChanged(event) {
    const value = (event?.target?.value || "").trim();
    // Only submit if non-empty; keep blank rows unsaved so users can type
    if (value.length > 0) {
      const form = this.element.closest("form");
      if (form) {
        this._markListChanged("whitelist", form);
        form.requestSubmit();
      }
    }
    if (this.lastModels) this.updateModelOptions(this.lastModels);
  }

  endpointChanged() {
    this.updateProviderInfo();
    // Refresh models when endpoint changes
    this.refreshModels();
  }

  // UI helpers for dynamic entry management
  addBlacklistEntry(event) {
    this._addEntryRow("blacklist");
  }

  addWhitelistEntry(event) {
    this._addEntryRow("whitelist");
  }

  removeEntry(event) {
    const row = event.currentTarget.closest("[data-entry-row]");
    if (row) {
      const input = row.querySelector("input");
      const hadValue = input?.value && input.value.trim().length > 0;
      const isBlacklist = input?.name?.includes("openai_model_blacklist");
      const container = isBlacklist
        ? this.blacklistContainerTarget
        : this.whitelistContainerTarget;
      const kind = isBlacklist ? "blacklist" : "whitelist";

      // Remove the row from the DOM
      row.remove();

      // Ensure there's always at least one input present so the param key is submitted
      const nameAttr = isBlacklist
        ? "setting[openai_model_blacklist][]"
        : "setting[openai_model_whitelist][]";
      const remainingInputs = container.querySelectorAll(
        `input[name="${nameAttr}"]`
      );
      if (remainingInputs.length === 0) {
        this._addEntryRow(kind);
      }

      // If the removed row had a value, persist removal immediately
      if (hadValue) {
        const form = this.element.closest("form");
        if (form) {
          this._markListChanged(kind, form);
          form.requestSubmit();
        }
      }
      // Re-filter options
      if (this.lastModels) this.updateModelOptions(this.lastModels);
    }
  }

  // Ensure server knows which list was changed so it updates only that list
  _markListChanged(kind, form) {
    const NAME = "setting[_list_changed]";
    let hidden = form.querySelector(`input[name="${NAME}"]`);
    if (!hidden) {
      hidden = document.createElement("input");
      hidden.type = "hidden";
      hidden.name = NAME;
      form.appendChild(hidden);
    }
    hidden.value = kind === "blacklist" ? "blacklist" : "whitelist";
  }

  _addEntryRow(kind) {
    const container =
      kind === "blacklist"
        ? this.blacklistContainerTarget
        : this.whitelistContainerTarget;
    const nameAttr =
      kind === "blacklist"
        ? "setting[openai_model_blacklist][]"
        : "setting[openai_model_whitelist][]";
    const targetAttr = kind === "blacklist" ? "blacklist" : "whitelist";

    const wrapper = document.createElement("div");
    wrapper.setAttribute("data-entry-row", "");
    wrapper.className = "flex items-start gap-2 mb-2";
    wrapper.innerHTML = `
      <div class="form-field flex-1">
        <input type="text"
               name="${nameAttr}"
               list="openai-model-suggestions"
               class="form-field__input"
               data-openai-settings-target="${targetAttr}"
               data-action="change->openai-settings#${targetAttr}Changed" />
      </div>
      <button type="button"
              class="inline-flex items-center justify-center w-8 h-8 rounded-md text-primary bg-transparent hover:bg-gray-100 theme-dark:hover:bg-gray-700"
              data-action="click->openai-settings#removeEntry"
              aria-label="Remove">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-x"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
      </button>
    `;
    container.appendChild(wrapper);

    // Focus the new input
    const input = wrapper.querySelector("input");
    if (input) input.focus();
  }
}
