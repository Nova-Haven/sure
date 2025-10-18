import { Controller } from "@hotwired/stimulus";

// Handles the chat error display and removal
export default class extends Controller {
  static targets = ["errorMessage"];

  connect() {
    console.log("Chat error controller connected");

    // Monitor for assistant messages - when a new one appears, hide errors
    this.setupErrorClearingOnNewMessages();
  }

  disconnect() {
    if (this.messagesObserver) {
      this.messagesObserver.disconnect();
    }
  }

  setupErrorClearingOnNewMessages() {
    // Find the messages container
    const messagesContainer = document.getElementById("messages");

    if (!messagesContainer) {
      console.warn("Messages container not found");
      return;
    }

    // Create a mutation observer to watch for new assistant messages
    this.messagesObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === "childList" && mutation.addedNodes.length > 0) {
          // Check if any of the added nodes contains an assistant message
          mutation.addedNodes.forEach((node) => {
            if (
              node.nodeType === 1 &&
              node.classList &&
              (node.classList.contains("assistant_message") ||
                node.querySelector(".assistant_message"))
            ) {
              // If we found an assistant message, remove the error
              this.removeError();
            }
          });
        }
      });
    });

    // Start observing
    this.messagesObserver.observe(messagesContainer, {
      childList: true,
      subtree: true,
    });
  }

  removeError() {
    console.log("Removing error message");
    const errorElement = document.getElementById("chat-error");
    if (errorElement) {
      errorElement.remove();
    }
  }
}
