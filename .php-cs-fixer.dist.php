<?php
/**
 * The PHP format contract for HestiaRE.
 *
 * Upstream formats PHP with prettier + @prettier/plugin-php. That toolchain is deliberately absent
 * here: the Gitea runner has no node, so nothing could enforce it. php-cs-fixer is pure PHP - but
 * it does NOT read .editorconfig, and its default ruleset is PSR-12, which mandates four spaces.
 * Run without this file it therefore rewrites every file it touches.
 *
 * The style is PSR-12 with the repository's indentation: tabs, matching .editorconfig's [*] block
 * and the shell tree. Keep the two in step - .editorconfig is what editors and shfmt read, this
 * file is what php-cs-fixer reads, and they must not contradict each other.
 *
 * Usage (local only - the runner has no PHP either):
 *   php-cs-fixer fix --dry-run --diff      check
 *   php-cs-fixer fix                       apply
 */

// Third-party PHP keeps its author's formatting, or the next upstream refresh drowns in noise.
// Derived from VENDORED.json rather than listed here: a hand-kept copy silently stops covering
// the next vendored file, and this exclusion would then quietly reformat it.
$vendored = [];
$walk = function ($node) use (&$walk, &$vendored) {
	if (is_array($node)) {
		if (isset($node["path"]) && is_string($node["path"])) {
			foreach (explode("+", $node["path"]) as $part) {
				$part = trim($part);
				if (str_ends_with($part, ".php")) {
					$vendored[] = realpath(__DIR__ . "/" . $part);
				}
			}
		}
		foreach ($node as $child) {
			$walk($child);
		}
	}
};
$walk(json_decode(file_get_contents(__DIR__ . "/VENDORED.json"), true));
$vendored = array_filter($vendored);

$finder = PhpCsFixer\Finder::create()
	->in([__DIR__ . "/web", __DIR__ . "/func", __DIR__ . "/share"])
	->name("*.php")
	->name("*.inc.php")
	->filter(fn(SplFileInfo $file) => !in_array($file->getRealPath(), $vendored, true));

return (new PhpCsFixer\Config())
	->setIndent("\t")
	->setLineEnding("\n")
	->setRules([
		"@PSR12" => true,
	])
	->setFinder($finder);
