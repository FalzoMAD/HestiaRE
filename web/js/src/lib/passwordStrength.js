// Eigenbau: password strength rating for the <meter> indicator. Mirrors the
// default rule model of check-password-strength (deanilvincent) so existing
// call sites keep their semantics: the rating is the highest level whose
// minimum length and character-class diversity are both met.
// Replaces the check-password-strength package (see VENDORED.json).
const LEVELS = [
	{ id: 0, minDiversity: 0, minLength: 0 }, // too weak
	{ id: 1, minDiversity: 2, minLength: 6 }, // weak
	{ id: 2, minDiversity: 4, minLength: 8 }, // medium
	{ id: 3, minDiversity: 4, minLength: 10 }, // strong
];

const CHARACTER_CLASSES = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^a-zA-Z0-9]/];

export function passwordStrength(password) {
	const value = password || '';
	const diversity = CHARACTER_CLASSES.filter((characterClass) =>
		characterClass.test(value),
	).length;

	const met = LEVELS.filter(
		(level) => diversity >= level.minDiversity && value.length >= level.minLength,
	);

	return { id: met[met.length - 1].id };
}
