import { createConfirmationDialog } from './helpers.js';

// Turning Docker off deletes the customer's containers, images and volumes, and re-checking the
// box brings none of it back. The server refuses the disable without the confirmation field
// regardless - this only makes the gesture match the consequence, and fills that field.
export default function handleDockerDisableGuard() {
	const checkbox = document.querySelector('#v_docker[data-docker-user]');
	// Not checkbox.checked: the box is driven by Alpine's x-model and carries no `checked`
	// attribute, and this module runs before Alpine does - so the live state reads false here no
	// matter what the server stored, and the guard used to unhook itself exactly when Docker was
	// on. The server's own state is passed in instead; the live state is read at submit, by which
	// time Alpine has long since run.
	if (!checkbox || checkbox.dataset.dockerEnabled !== 'yes') {
		return; // docker is off already - nothing destructive can happen here
	}

	const form = checkbox.form;
	const confirmField = form?.querySelector('#v_docker_confirm');
	if (!form || !confirmField) {
		return;
	}
	const expected = checkbox.dataset.dockerUser;

	form.addEventListener('submit', (evt) => {
		// Still enabled, or already confirmed: let the submit run, including every other handler
		// on this form. requestSubmit() below comes back through here for exactly that reason.
		if (checkbox.checked || confirmField.value === expected) {
			return;
		}
		// stopImmediatePropagation, not just preventDefault: handleFormSubmit listens on the same
		// event, and it ends in mainForm.submit() - which bypasses the submit event entirely. So
		// preventing the default alone left this dialog on screen for exactly as long as it took
		// that handler to navigate away, and what the user got was the server's refusal instead.
		evt.preventDefault();
		evt.stopImmediatePropagation();

		createConfirmationDialog({
			title: checkbox.dataset.confirmTitle,
			message: checkbox.dataset.confirmMessage,
			confirmWord: expected,
			confirmLabel: checkbox.dataset.confirmLabel,
			onConfirm: () => {
				confirmField.value = expected;
				// requestSubmit, not submit: submit() skips the submit event entirely, so every
				// other guard and validator on this form would be silently switched off by a
				// confirmation that is about one checkbox.
				form.requestSubmit();
			},
			onCancel: () => {
				// covers Escape as well - the dialog's close event is the single exit path
				checkbox.checked = true;
			},
		});
	});
}
