<?php
// Allow-list HTML sanitizer for values rendered as raw HTML in the panel (notification
// NOTICE via x-html). Default-deny: output is rebuilt from whitelisted tags/attrs only, so
// it fails by stripping, never by passing a payload. No external dep (ext-dom is standard).
// CLI: php sanitize_html.php "<html>" ['{"tags":[...],"attrs":{...}}']  (2nd arg overrides
// the allow-list for reuse). Errors silenced so a stray notice can't corrupt the stored value.

error_reporting(0);
ini_set("display_errors", "0");

// Dropped with their content. The raw-text legacy tags (xmp..textarea) are here because a
// parser may keep their content as literal text a payload could hide in; never legit here.
const DROP_WITH_CONTENT = [
	"script", "style", "iframe", "object", "embed", "svg", "math",
	"template", "noscript", "head", "title", "link", "meta", "base", "form",
	"xmp", "plaintext", "listing", "noembed", "noframes", "textarea",
];

// href/src: only http(s), relative or #fragment. Control chars stripped before the scheme
// test to defeat "java\tscript:" obfuscation.
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
	// No ASCII scheme -> relative/#frag/protocol-relative //host, allowed by design
	// (notifications link out). ASCII-only is deliberate: a confusable colon (fullwidth
	// U+FF1A) is no scheme to a browser, so it stays an inert relative link. No mailto:/tel:.
	return true;
}

// Recursion cap (fail closed) so a reuse without NOTICE's length limit can't drive deep
// nesting into a PHP stack limit. Past it the subtree is dropped.
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

	// Fail safe if ext-dom is somehow absent: escape rather than empty the value (panel ships php-xml).
	if (!class_exists("DOMDocument")) {
		return htmlspecialchars($html, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
	}

	$src = new DOMDocument();
	$prev = libxml_use_internal_errors(true);
	// NOIMPLIED/NODEFDTD: no html/body/doctype wrapper; UTF-8 prolog stops multibyte mangling.
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
