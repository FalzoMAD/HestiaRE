import { createConfirmationDialog } from './helpers.js';

// Two irreversible gestures on the web-domain form: unticking WordPress detaches it (the site
// keeps running, but the panel lets go and the docroot guard blocks a re-enable), and the delete
// button removes files and database. Both get a dialog before the request leaves.
//
// Capture phase on document, not listeners on the forms: a capture listener on an ancestor runs
// before every listener attached to the target, whatever order the modules were imported in -
// and formSubmit.js ends in mainForm.submit(), which bypasses the submit event entirely.
export default function handleWordpressGuards() {
	const checkbox = document.querySelector('#v_wordpress[data-wp-installed="yes"]');
	const mainForm = checkbox ? checkbox.form : null;
	const actionForm = document.querySelector('#wp-action-form');
	if (!mainForm && !actionForm) {
		return;
	}

	document.addEventListener(
		'submit',
		(evt) => {
			let dialog = null;

			if (mainForm && evt.target === mainForm) {
				// Not checkbox.checked at load time: Alpine drives the box via x-model and the
				// server state is in the data attribute. Confirmed detaches carry the marker.
				if (checkbox.checked || checkbox.dataset.wpConfirmed === 'yes') {
					return;
				}
				dialog = {
					title: checkbox.dataset.confirmTitle,
					message: checkbox.dataset.confirmMessage,
					confirmLabel: checkbox.dataset.confirmLabel,
					onConfirm: () => {
						checkbox.dataset.wpConfirmed = 'yes';
						mainForm.requestSubmit();
					},
					onCancel: () => {
						checkbox.checked = true;
						checkbox.dispatchEvent(new Event('change', { bubbles: true }));
					},
				};
			} else if (actionForm && evt.target === actionForm) {
				const button = evt.submitter;
				if (!button || button.value !== 'delete' || button.dataset.wpConfirmed === 'yes') {
					return;
				}
				dialog = {
					title: button.dataset.confirmTitle,
					message: button.dataset.confirmMessage,
					confirmWord: button.dataset.confirmWord,
					confirmLabel: button.dataset.confirmLabel,
					onConfirm: () => {
						button.dataset.wpConfirmed = 'yes';
						// requestSubmit(button), not submit(): the submitter carries wp_action,
						// and submit() would drop both it and every other guard on the form
						actionForm.requestSubmit(button);
					},
				};
			}

			if (!dialog) {
				return;
			}
			evt.preventDefault();
			evt.stopPropagation();
			createConfirmationDialog(dialog);
		},
		true,
	);
}
