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

	// Capture phase on document, not a listener on the form: a capture listener on an ancestor runs
	// before every listener attached to the target, whatever order the modules were imported in.
	// Registering on the form and calling stopImmediatePropagation would only stop handlers added
	// AFTER this one - true today, silently false the day someone reorders the imports in index.js.
	document.addEventListener(
		'submit',
		(evt) => {
			if (evt.target !== form) {
				return;
			}
			// Still enabled, or already confirmed: let the submit run, including every other handler
			// on this form. requestSubmit() below comes back through here for exactly that reason.
			if (checkbox.checked || confirmField.value === expected) {
				return;
			}
			// handleFormSubmit ends in mainForm.submit(), which bypasses the submit event entirely,
			// so preventing the default alone left this dialog on screen only until that handler
			// navigated away - what the user saw was the server's refusal. stopPropagation keeps the
			// event from reaching the form's own listeners at all.
			evt.preventDefault();
			evt.stopPropagation();

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
		},
		true,
	);
}
