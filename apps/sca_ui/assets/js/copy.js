// Copying, for both consoles: `<.copy_value>` dispatches `sca:copy` at the
// element holding the value, and the blink is LiveView's own JS commands. Here
// in the design system rather than in one console's app.js, for the same reason
// the components are: two copies drift apart quietly.
window.addEventListener("sca:copy", (event) => {
  if (!navigator.clipboard) return

  navigator.clipboard.writeText(event.target.textContent.trim())
})
