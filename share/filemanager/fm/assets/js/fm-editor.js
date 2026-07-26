// Minimal Prism-overlay code editor for the FM "Advanced Editor" (#218 P4,
// replaces Ace). Scope is deliberately light: syntax highlighting + line numbers,
// no preview, comfort not language-depth.
//
// A transparent <textarea> sits on top and owns the caret/selection; a
// Prism-highlighted <pre> underneath renders the colours. Because the real
// textarea holds the caret there is NO contenteditable and NO caret-restore
// math (the reason CodeJar/prism-code-editor were not needed). Only the already
// vendored prism.js (core + line-numbers plugin) is used — no extra upstream.
(function () {
	"use strict";

	function init(host) {
		var ta = host.querySelector(".fm-editor__input");
		var pre = host.querySelector(".fm-editor__pre");
		var code = pre.querySelector("code");
		if (!ta || !code) return;

		function render() {
			var text = ta.value;
			// A trailing newline needs a spare char so Prism emits the last row.
			code.textContent = text + (text.slice(-1) === "\n" ? " " : "");
			window.Prism.highlightElement(code);
		}
		function sync() {
			pre.scrollTop = ta.scrollTop;
			pre.scrollLeft = ta.scrollLeft;
		}

		ta.addEventListener("input", render);
		ta.addEventListener("scroll", sync);
		ta.addEventListener("keydown", function (e) {
			if (e.key === "Tab") {
				// Keep focus in the box; insert two spaces like the old editor.
				e.preventDefault();
				var s = ta.selectionStart, en = ta.selectionEnd;
				ta.value = ta.value.slice(0, s) + "  " + ta.value.slice(en);
				ta.selectionStart = ta.selectionEnd = s + 2;
				render();
			}
		});

		render();
		// edit_save() reads the current text through this hook.
		host.fmValue = function () { return ta.value; };
	}

	window.fmEditorInit = init;
	document.addEventListener("DOMContentLoaded", function () {
		document.querySelectorAll(".fm-editor").forEach(init);
	});
})();
