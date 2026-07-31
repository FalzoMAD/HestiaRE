<?php
// Allow-list HTML sanitizer for values that are rendered as raw HTML in the panel
// (e.g. notification NOTICE via Alpine x-html). Default-deny: the output is REBUILT from
// only whitelisted tags/attributes, so the failure mode is "strips too much", never
// "payload passes". No external dependency (ext-dom is standard PHP).
//
// CLI:  php sanitize_html.php "<html>" ['{"tags":[...],"attrs":{"a":["href"]}}']
// The optional 2nd arg (JSON) overrides the allow-list, so this helper is reusable for
// any future user-HTML surface. Errors are silenced and only the sanitized string is
// emitted, so a stray PHP notice can never corrupt the value the caller stores.

error_reporting(0);
ini_set("display_errors", "0");

// Tags whose content is dropped entirely (never rendered, not even as text). Includes the
// raw-text / escapable-raw-text legacy tags (xmp, plaintext, listing, noembed, noframes,
// textarea): some HTML parsers treat their content as literal text up to the close tag, so
// a nested payload could survive an unwrap - none are ever legitimate in a notification, so
// dropping them outright removes the ambiguity instead of relying on the parser's behavior.
const DROP_WITH_CONTENT = [
	"script", "style", "iframe", "object", "embed", "svg", "math",
	"template", "noscript", "head", "title", "link", "meta", "base", "form",
	"xmp", "plaintext", "listing", "noembed", "noframes", "textarea",
];

// href/src values: allow only http(s), root-relative, or fragment/anchor. Anything with a
// non-http(s) scheme (javascript:, data:, vbscript:, ...) is rejected. Whitespace/control
// chars are stripped before the scheme test to defeat "java\tscript:" style obfuscation.
function url_is_safe($url)
{
	$probe = preg_replace('/[\x00-\x20\x7f]+/', "", (string) $url);
	if ($probe === "") {
		return false;
	}
	if (preg_match('/^[a-z][a-z0-9+.-]*:/i', $probe, $m)) {
		$scheme = strtolower(rtrim($m[0], ":"));
		return $scheme === "http" || $scheme === "https";
	}
	// No ASCII scheme -> relative path, #fragment, or protocol-relative //host. All are
	// allowed as LINK targets by design: notifications legitimately link out (e.g. release
	// notes), and an external destination is a link, not a code-execution vector. Scheme
	// detection is ASCII-only on purpose - a confusable/non-ASCII colon (e.g. fullwidth
	// U+FF1A) is not a scheme separator to any browser, so such a value stays an inert
	// relative link. mailto:/tel: are intentionally NOT allowed (not used by notifications).
	return true;
}

// Hard recursion-depth cap. Legit notifications are shallow; this delivers the "reusable for
// any user-HTML surface" promise so a future caller without NOTICE's length limit cannot
// drive deeply nested markup into a PHP stack/nesting limit. Past the cap the subtree is
// dropped (fail closed, "strips too much").
const MAX_DEPTH = 100;

// Recursively copy only allow-listed nodes from $src into $dstParent (owned by $dst).
function copy_allowed(DOMNode $src, DOMDocument $dst, DOMNode $dstParent, array $tags, array $attrs, int $depth = 0)
{
	if ($depth > MAX_DEPTH) {
		return;
	}
	foreach ($src->childNodes as $node) {
		if ($node->nodeType === XML_TEXT_NODE) {
			$dstParent->appendChild($dst->createTextNode($node->nodeValue));
			continue;
		}
		if ($node->nodeType !== XML_ELEMENT_NODE) {
			continue; // comments, PIs, CDATA: drop
		}
		$tag = strtolower($node->nodeName);
		if (in_array($tag, $tags, true)) {
			$el = $dst->createElement($tag);
			foreach ($attrs[$tag] ?? [] as $attr) {
				if (!$node->hasAttribute($attr)) {
					continue;
				}
				$val = $node->getAttribute($attr);
				if ($attr === "href" || $attr === "src") {
					if (!url_is_safe($val)) {
						continue;
					}
					$el->setAttribute($attr, $val);
					if ($tag === "a") {
						$el->setAttribute("rel", "noopener");
					}
				} else {
					$el->setAttribute($attr, $val);
				}
			}
			copy_allowed($node, $dst, $el, $tags, $attrs, $depth + 1);
			$dstParent->appendChild($el);
		} elseif (in_array($tag, DROP_WITH_CONTENT, true)) {
			continue; // drop tag AND its content
		} else {
			// Unknown formatting tag: drop the tag, keep sanitized children (its text).
			copy_allowed($node, $dst, $dstParent, $tags, $attrs, $depth + 1);
		}
	}
}

function sanitize_html($html, array $tags, array $attrs)
{
	if ($html === "" || $html === null) {
		return "";
	}

	// Fail safe if ext-dom is ever absent: escape (safe, shown as text, no data loss)
	// rather than silently emptying the value. The panel pool ships php-xml, so this is a
	// belt-and-suspenders guard, not the expected path.
	if (!class_exists("DOMDocument")) {
		return htmlspecialchars($html, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
	}

	$src = new DOMDocument();
	$prev = libxml_use_internal_errors(true);
	// NOIMPLIED/NODEFDTD keep DOMDocument from wrapping the fragment in html/body/doctype;
	// the explicit UTF-8 prolog stops loadHTML from mangling multibyte input (IDN domains).
	$src->loadHTML(
		'<?xml encoding="UTF-8"><div id="hst-root">' . $html . "</div>",
		LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD,
	);
	libxml_clear_errors();
	libxml_use_internal_errors($prev);

	$root = $src->documentElement;
	if (!$root) {
		return "";
	}

	$dst = new DOMDocument("1.0", "UTF-8");
	$dstRoot = $dst->createElement("div");
	$dst->appendChild($dstRoot);
	copy_allowed($root, $dst, $dstRoot, $tags, $attrs);

	$out = "";
	foreach ($dstRoot->childNodes as $child) {
		$out .= $dst->saveHTML($child);
	}
	return $out;
}

if (!isset($argv[1])) {
	return;
}

// Default allow-list: what Hestia notifications actually use.
$tags = ["p", "span", "code", "a", "strong", "br"];
$attrs = ["p" => ["class"], "span" => ["class"], "a" => ["href"]];

if (isset($argv[2])) {
	$override = json_decode($argv[2], true);
	if (is_array($override)) {
		if (isset($override["tags"]) && is_array($override["tags"])) {
			$tags = array_map("strtolower", $override["tags"]);
		}
		if (isset($override["attrs"]) && is_array($override["attrs"])) {
			$attrs = $override["attrs"];
		}
	}
}

echo sanitize_html($argv[1], $tags, $attrs);
