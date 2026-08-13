import { createConfirmationDialog } from './helpers.js';

// Turning Docker off deletes the customer's containers, images and volumes, and re-checking the
// box brings none of it back. The server refuses the disable without the confirmation field
// regardless - this only makes the gesture match the consequence, and fills that field.
export default function handleDockerDisableGuard() {
	const checkbox = document.querySelector('#v_docker[data-docker-user]');
	if (!checkbox || !checkbox.checked) {
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
		evt.preventDefault();

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
