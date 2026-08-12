// Turning Docker off deletes the customer's containers, images and volumes, and re-checking the
// box brings none of it back. So the unchecked box alone must not carry the save: the form only
// submits once the customer's name has been typed, and the server refuses without it either way.
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

	form.addEventListener(
		'submit',
		(evt) => {
			if (checkbox.checked || confirmField.value === expected) {
				return; // still enabled, or already confirmed
			}
			evt.preventDefault();
			evt.stopImmediatePropagation();

			const dialog = document.createElement('dialog');
			dialog.classList.add('modal');
			dialog.innerHTML = `
				<h2 class="modal-title">Disable Docker for ${expected}?</h2>
				<p class="modal-message">
					This removes the companion account and <b>deletes every container, image and volume</b>
					of this customer. Turning Docker back on later creates an empty companion - nothing
					comes back. Their docker domains revert to normal vhosts.<br><br>
					Type <b>${expected}</b> to confirm.
				</p>
			`;
			const input = document.createElement('input');
			input.type = 'text';
			input.classList.add('form-control');
			input.setAttribute('autocomplete', 'off');
			dialog.append(input);

			const options = document.createElement('div');
			options.classList.add('modal-options');
			const ok = document.createElement('button');
			ok.type = 'button';
			ok.classList.add('button', 'button-danger');
			ok.textContent = 'Disable Docker';
			ok.disabled = true;
			const cancel = document.createElement('button');
			cancel.type = 'button';
			cancel.classList.add('button', 'button-secondary', 'u-ml5');
			cancel.textContent = 'Cancel';
			options.append(ok, cancel);
			dialog.append(options);
			document.body.append(dialog);
			dialog.showModal();
			input.focus();

			input.addEventListener('input', () => {
				ok.disabled = input.value !== expected;
			});
			ok.addEventListener('click', () => {
				confirmField.value = input.value;
				dialog.close();
				dialog.remove();
				form.submit();
			});
			cancel.addEventListener('click', () => {
				checkbox.checked = true; // leave the page in the state it was in
				dialog.close();
				dialog.remove();
			});
		},
		true, // capture: run before the form's own submit handlers
	);
}
