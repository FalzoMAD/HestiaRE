# Hooks

Optional scripts the panel runs at defined points. A hook is picked up only when the file exists
here in `/etc/hestia/hooks/` **and is executable** (`chmod +x`); otherwise nothing happens. These
files are yours - an update never touches this directory.

## Let's Encrypt (#4925)

Run around a certificate request by `h-add-letsencrypt-domain`:

| File | When | Arguments |
|---|---|---|
| `le_pre.sh` | before the request, always reached | `$user $domain $aliases $mail` |
| `le_post.sh` | after a **successful** issue (skipped on failure) | `$user $domain $aliases $mail` |

`$mail` is `yes` when the certificate is for the mail domain, empty otherwise. Example - reload a
service that pins the certificate, only for one domain:

```bash
#!/bin/bash
# /etc/hestia/hooks/le_post.sh
[ "$2" = "mail.example.com" ] && systemctl reload some-service
exit 0
```

Keep hooks fast and exit 0: `le_pre.sh` runs inline before issuance, so a slow or failing hook
delays or disrupts the certificate. The panel does not check a hook's exit code, but a hook that
hangs holds up the request.
