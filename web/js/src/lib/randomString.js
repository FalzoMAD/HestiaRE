// Eigenbau: unbiased random string from a custom alphabet, built on
// crypto.getRandomValues with rejection sampling to avoid modulo bias.
// Replaces nanoid/customAlphabet (see VENDORED.json, inspiration: ai/nanoid).
export function randomString(alphabet, size) {
	if (alphabet.length < 2 || alphabet.length > 255) {
		throw new Error('alphabet must contain 2-255 characters');
	}

	// Reject bytes above the largest multiple of the alphabet length so every
	// character keeps an equal probability
	const limit = 256 - (256 % alphabet.length);
	let result = '';

	while (result.length < size) {
		const bytes = crypto.getRandomValues(new Uint8Array(size - result.length));
		for (const byte of bytes) {
			if (byte < limit) {
				result += alphabet[byte % alphabet.length];
				if (result.length === size) {
					break;
				}
			}
		}
	}

	return result;
}

// Unbiased random integer in [0, max) via rejection sampling on a single byte.
export function randomInt(max) {
	if (max < 1 || max > 256) {
		throw new Error('max must be 1-256');
	}
	const limit = 256 - (256 % max);
	// eslint-disable-next-line no-constant-condition
	while (true) {
		const byte = crypto.getRandomValues(new Uint8Array(1))[0];
		if (byte < limit) {
			return byte % max;
		}
	}
}
