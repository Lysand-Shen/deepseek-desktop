import Foundation

/// Small DOM helpers. They only touch the page's own UI (clicking its buttons, focusing its
/// input); nothing here calls DeepSeek's private endpoints.
enum WebScripts {
    /// Clicks the page's own "new chat" control. Returns `true` when one was found.
    static let startNewChat = """
    (() => {
      const labels = new Set(['开启新对话', '新对话', '新建对话', 'New chat', 'New Chat']);
      const find = (selector) => {
        for (const node of document.querySelectorAll(selector)) {
          const text = (node.textContent || '').trim();
          if (text.length <= 12 && labels.has(text)) return node;
        }
        return null;
      };
      const node = find('a, button, [role="button"], [tabindex]') || find('div, span');
      if (!node) return false;
      (node.closest('a, button, [role="button"], [tabindex]') || node).click();
      return true;
    })();
    """

    /// Body of an async function for `callAsyncJavaScript` with a `text` argument: types the
    /// text into the page's chat input and sends it the way the user would, with Return,
    /// falling back to the send button. Returns `sent`, `no-input` or `not-sent`.
    static let submitPrompt = """
    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const findInput = () => document.querySelector('textarea#chat-input') || document.querySelector('textarea');
    const deadline = Date.now() + 20000;
    let input = findInput();
    while ((!input || input.disabled) && Date.now() < deadline) {
      await sleep(100);
      input = findInput();
    }
    if (!input || input.disabled) return 'no-input';

    const startURL = location.href;
    input.focus();
    // React tracks the value through the prototype's setter; assigning `value` alone is ignored.
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(input, text);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    await sleep(80);
    const enter = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    input.dispatchEvent(new KeyboardEvent('keydown', enter));
    input.dispatchEvent(new KeyboardEvent('keyup', enter));
    // Sending clears the input, or replaces it as the page moves to the new conversation.
    const isSent = () => location.href !== startURL || !input.isConnected || input.value.trim() === '';
    await sleep(800);
    if (isSent()) return 'sent';

    // Return did nothing, so the text is still there and the send button is the one enabled
    // at the end of the box around the input.
    for (let box = input.parentElement; box && box !== document.body; box = box.parentElement) {
      const buttons = [...box.querySelectorAll('button, [role="button"]')]
        .filter((button) => !button.disabled && button.getAttribute('aria-disabled') !== 'true');
      if (buttons.length === 0) continue;
      buttons[buttons.length - 1].click();
      await sleep(500);
      break;
    }
    return isSent() ? 'sent' : 'not-sent';
    """

    /// Focuses the chat input unless the user is already typing somewhere else.
    static let focusChatInput = """
    (() => {
      const active = document.activeElement;
      if (active && active !== document.body && active !== document.documentElement) return false;
      const input = document.querySelector('textarea#chat-input') || document.querySelector('textarea');
      if (!input || input.disabled) return false;
      input.focus();
      const end = input.value.length;
      try { input.setSelectionRange(end, end); } catch (e) {}
      return true;
    })();
    """
}
