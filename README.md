# Hestia R* Edition

Rethink. Rebuild. Reboot. - _pick your **R***_


_____

A leaner, modernized fork of [HestiaCP](https://github.com/hestiacp/hestiacp) for self-hosted infrastructure. HestiaRE strips the codebase down to what's actually needed, replaces legacy bundled components with standard OS packages and modern lightweight alternatives (Caddy instead of the bundled nginx panel, Sury PHP instead of compiled PHP builds, distro repos instead of custom tarball installs), and rebuilds the installer as a composable, idempotent, pure-bash system.

It is deliberately scoped for a small, professional fleet — on the order of a few hundred domains across a couple dozen customers and servers — not for a broad community deployment.

### Status: experimental

Nearly all of it is in place, and the test fleet has been through many rounds of it: installer, panel, web, mail, backup, firewall, CrowdSec, Docker, IPv6 — every subsystem exists, and every release is measured on all four target systems before it is cut. That makes HestiaRE **usable**.

It does not make it **stable**. Interfaces still move, a point release can change behaviour, and **v1 is deliberately far away** — the version number is not a countdown. Run it if you are willing to read a changelog and re-test after an update. Don't run it if you need something that stays put while you look elsewhere.

**Target systems** — all first-class, equal priority (every feature must work on all four):
- Debian 12 (Bookworm), Debian 13 (Trixie), Ubuntu 24.04 LTS (Noble), Ubuntu 26.04 LTS

## Philosophy

**HestiaRE does not want dependent users.**

Most self-hosted panels accumulate them: people running someone else's release pipeline, someone else's apt repository, someone else's opinion about what belongs in the stack. The day that project changes direction or loses interest, its users have nowhere to go — they never had the pieces in their hands.

This one inverts that. No compiled binaries, no private package repository, no build step on the target host: source, a git tag, one tarball, a bootstrap script that extracts it. **Forking HestiaRE costs a `git clone`, not a release infrastructure.** That is the actual offer — not "use my panel", but "take this and run your own".

**It follows exactly one set of requirements: the maintainer's.** This is a personal professional tool that happens to be open source. Features that this fleet does not need do not get built — not "later", not "PRs welcome", simply not here. Bug reports against the four target systems are welcome, and so is anything that makes forking cheaper. A feature request that only makes sense for someone else's fleet will be declined, quickly and without it being personal — because the honest answer to it is better than a maybe: **fork it and build it there.** Your fork, your opinions, without inheriting a toolchain you never signed up for.

That is also why the deliberate omissions below are not a backlog.

## What makes it different

### Reduced dependencies

HestiaCP bundles and compiles a lot of its own stack. HestiaRE inverts that: **OS repositories are the default**, and every external source has to justify itself. In practice that leaves exactly two external apt repos — **Sury** (multi-version PHP) and **MariaDB** — with everything else coming from the distribution:

- The panel runs on **Caddy** (OS repo) instead of a bundled nginx build.
- PHP comes from **Sury** as isolated FPM pools instead of a custom compiled PHP.
- Web, mail, database and firewall tooling (nginx, Apache, exim/dovecot/rspamd, phpMyAdmin, fail2ban, ipset, Composer, WP-CLI, …) is installed straight from distro packages.
- Optional components (ProFTPD, ClamAV, PostgreSQL, Redis, OpenSearch, Docker proxy, file manager, …) are **individually installable and removable**, so a given host only carries what it uses.
- **IPv6 is first-class, never presupposed**: a box with both families serves both, a v6-only box installs and runs from the bootstrap onwards, and a box whose kernel has no IPv6 is a supported state rather than an accident.

The result is a smaller, more auditable surface that tracks the distributions' own security updates instead of a private package pipeline.

### A completely different build & release process

HestiaCP builds versioned Debian **`.deb` packages** (including compiled binaries) and serves them from a **custom apt repository**. HestiaRE ships **no packages and no binaries** — only source:

1. Pushing a `v*` git tag triggers CI (`.github/workflows/release.yml`).
2. CI stamps the tag into `VERSION` and packs the tree into a single versioned **`hestiare-<version>.tar.gz`** source tarball.
3. `install.sh` — the one curl-able bootstrap — fetches and extracts that tarball into `/usr/local/hestia`, then takes over.

There is no compiled artifact, no private package repo, and no build toolchain required on the target host. (Earlier iterations used `just`/Make; that dependency has been removed — the installer is now pure bash.)

### Installer, refactored

Because there are no packages doing the setup work, the installer had to be rebuilt around that source-tarball model. It is now a clean two-stage flow:

- **`install.sh` (bootstrap):** installs prerequisites, detects the OS, fetches and extracts the release, runs the interactive **manifest-driven wizard** (`include/wizard.sh`) which writes `/etc/hestia/install.conf`, and seeds `/etc/hestia` so the `h-*` commands can run.
- **`h-install-hestia` (installer):** non-interactive, reads `install.conf`, and is **component-gated and idempotent** — every subsystem is guarded by a flag, so profiles (minimal / standard) and optional add-ons (via `h-add-*` / `h-delete-*`) compose cleanly and re-runs don't fight themselves.

A post-install smoke test then verifies that the services implied by the chosen configuration actually came up.

### Deliberate omissions

Some HestiaCP subsystems are **intentionally left out** — not missing, but decided against — to shrink the attack surface and the maintenance burden for the intended scale:

- **No bundled DNS server (bind9)** — DNS is delegated to external / managed providers.
- **No REST API.**
- **No Web Terminal.**

The same reasoning removes vsftpd, SpamAssassin (rspamd is the mail-filter), and the Software Installer. These are settled decisions, not backlog items.

### Development approach

HestiaRE is developed through **agentic AI-assisted development**: an AI agent (Claude) writes and iterates on code, scripts, and documentation, while every change is reviewed, tested, and merged exclusively by a human maintainer. No commit reaches `main` without human review — the agent proposes, the human decides.

### License

GPL-3.0, inherited from HestiaCP.
