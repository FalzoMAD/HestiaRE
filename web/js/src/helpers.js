import { randomString, randomInt } from './lib/randomString.js';

// Generates a random password that always passes password requirements.
// Character sets are chosen to be typeable on any keyboard layout (no AltGr,
// no dead keys) and free of easily-confused glyphs (no I/l/1/O/0, no
// pipe/braces), so the result survives being typed by hand — e.g. over VNC.
export function randomPassword(length = 16) {
	const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I, O
	const lowercase = 'abcdefghijkmnopqrstuvwxyz'; // no l
	const numbers = '23456789'; // no 0, 1
	const symbols = '!%+-=_'; // reachable without AltGr/dead keys, not confusable
	const alphanumeric = uppercase + lowercase + numbers;

	// Only 1-3 symbols per password (never more than a quarter of the length),
	// the rest alphanumeric — keeps it strong but easy to type.
	const maxSymbols = Math.min(3, Math.max(1, Math.floor(length / 4)));
	const symbolCount = 1 + randomInt(maxSymbols);

	let password;
	do {
		// Build the alphanumeric base, then splice the symbols in at random spots
		const chars = randomString(alphanumeric, length - symbolCount).split('');
		for (let i = 0; i < symbolCount; i++) {
			chars.splice(randomInt(chars.length + 1), 0, symbols[randomInt(symbols.length)]);
		}
		password = chars.join('');
		// Must contain at least one uppercase letter, one lowercase letter, and one number
	} while (!(/[a-z]/.test(password) && /[A-Z]/.test(password) && /\d/.test(password)));

	return password;
}

// Debounces a function to avoid excessive calls
export function debounce(func, wait = 100) {
	let timeout;
	return function (...args) {
		clearTimeout(timeout);
		timeout = setTimeout(() => func.apply(this, args), wait);
	};
}

// Shows the loading spinner overlay
export function showSpinner() {
	document.querySelector('.js-spinner').classList.add('active');
}

// Parses and sorts IP lists from HTML
export function parseAndSortIpLists(ipListsData) {
	const ipLists = JSON.parse(ipListsData || '[]');
	return ipLists.sort((a, b) => a.name.localeCompare(b.name));
}

// Determines if the current browser is Desktop Safari
export function isDesktopSafari() {
	const userAgent = window.navigator.userAgent;
	const isSafari = /^((?!chrome|android).)*safari/i.test(userAgent);
	const isMac = /Macintosh|MacIntel/i.test(window.navigator.platform);
	return isSafari && isMac;
}

// Waits for the given number of milliseconds
export function delay(milliseconds) {
	return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

// Creates a confirmation <dialog> on the fly
export function createConfirmationDialog({
	title,
	message = 'Are you sure?',
	targetUrl,
	spinner = false,
}) {
	// Create the dialog
	const dialog = document.createElement('dialog');
	dialog.classList.add('modal');

	// Create and insert the title
	if (title) {
		const titleElement = document.createElement('h2');
		titleElement.innerHTML = title;
		titleElement.classList.add('modal-title');
		dialog.append(titleElement);
	}

	// Create and insert the message
	const messageElement = document.createElement('p');
	messageElement.innerHTML = message;
	messageElement.classList.add('modal-message');
	dialog.append(messageElement);

	// Create and insert the options
	const optionsElement = document.createElement('div');
	optionsElement.classList.add('modal-options');

	const confirmButton = document.createElement('button');
	confirmButton.type = 'submit';
	confirmButton.classList.add('button');
	confirmButton.textContent = 'OK';
	optionsElement.append(confirmButton);

	const cancelButton = document.createElement('button');
	cancelButton.type = 'button';
	cancelButton.classList.add('button', 'button-secondary', 'u-ml5');
	cancelButton.textContent = 'Cancel';
	if (targetUrl) {
		optionsElement.append(cancelButton);
	}

	dialog.append(optionsElement);

	// Define named functions to handle the event listeners
	const handleConfirm = () => {
		if (targetUrl) {
			if (spinner) {
				showSpinner();
			}
			window.location.href = targetUrl;
		}

		handleClose();
	};

	const handleCancel = () => handleClose();
	const handleClose = () => {
		confirmButton.removeEventListener('click', handleConfirm);
		cancelButton.removeEventListener('click', handleCancel);
		dialog.removeEventListener('close', handleClose);
		dialog.remove();
	};

	// Add event listeners
	confirmButton.addEventListener('click', handleConfirm);
	cancelButton.addEventListener('click', handleCancel);
	dialog.addEventListener('close', handleClose);

	// Add to DOM and show
	document.body.append(dialog);
	dialog.showModal();
}
