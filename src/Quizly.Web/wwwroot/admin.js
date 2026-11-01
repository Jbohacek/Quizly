// Small helpers for the Blazor admin dashboard.
window.quizly = {
  /** Copies text; returns false when the browser refuses (the caller shows a hint to copy by hand). */
  copy: async function (text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      return false;
    }
  },

  /** Downloads text as a UTF-8 file. */
  download: function (fileName, text, mime) {
    const blob = new Blob([text], { type: (mime || "text/plain") + ";charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  },

  /** Inserts text at the caret of a textarea/input and returns the new value. */
  insertAtCaret: function (element, text) {
    const start = element.selectionStart ?? element.value.length;
    const end = element.selectionEnd ?? element.value.length;
    element.value = element.value.slice(0, start) + text + element.value.slice(end);
    element.focus();
    element.setSelectionRange(start + text.length, start + text.length);
    return element.value;
  },
};
