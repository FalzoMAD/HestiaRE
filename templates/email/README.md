# Notification email templates

The panel sends a few notification mails (new mail account, new database, FTP credentials, password
reset, account ready). Each has a built-in default text compiled into the panel; you do not need
any file here for mail to be sent.

To **override** one, copy its sample from `examples/` up into this directory and edit it (run from
`templates/email/`):

```
cp examples/email_credentials.html email_credentials.html
```

## Language

Each override can be global or per language. For a mail sent to a user whose panel language is
`<lang>`, the panel looks in this order and takes the first that exists:

1. `templates/email/<lang>/<name>.html`  — this language only
2. `templates/email/<name>.html`         — all languages
3. the built-in default

So a global override goes straight in `templates/email/`; a language-specific one goes in a
subdirectory named after the language code, e.g.:

```
templates/email/email_credentials.html        # everyone
templates/email/de/email_credentials.html      # German panel users only
templates/email/fr/email_credentials.html      # French panel users only
```

The code is the two-letter panel locale (`de`, `fr`, `es`, `it`, `nl`, `pl`, `ru`, `ja`, `zh`, …);
it matches the directory names under `web/locale/`. A per-language file wins over the global one,
and the global one wins over the built-in default. The files under `examples/` are never read - they
are only samples to copy from.

`{{placeholder}}` tokens are substituted at send time; each example lists the ones it supports. An
optional `<subject>…</subject>` line at the top sets the subject; without it the panel builds one.

Overrides live in `templates/`, which an update never deletes - only overwrites files it ships. A
file you add here (a name the release does not carry) survives updates.
