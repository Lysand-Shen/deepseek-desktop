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
