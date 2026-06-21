# Hestia R* Edition

Rethink. Rebuild. Reboot. - _pick your **R***_


_____

A leaner, modernized fork of [HestiaCP](https://github.com/hestiacp/hestiacp) for self-hosted infrastructure. HestiaRE strips the codebase down to what's actually needed, replaces legacy bundled components with standard OS packages and modern lightweight alternatives (Caddy instead of the bundled nginx panel, Sury PHP instead of compiled PHP builds, distro repos instead of custom tarball installs), and rebuilds the installer as a composable, idempotent Make-based system.

### Status: incomplete, not usable yet

HestiaRE is in active, early-stage development. Releases exist (currently v0.1.5) for development and testing purposes only — **the project is not yet usable for any real hosting environment.** Core components are still being migrated, replaced, or audited, and no install on a production system should be attempted at this stage.

Supported target systems (for testing): Debian 12 (Bookworm) and Ubuntu 24.04 (Noble).

### Development approach

HestiaRE is developed through **agentic AI-assisted development**: an AI agent (Claude) writes and iterates on code, scripts, and documentation, while every change is reviewed, tested, and merged exclusively by a human maintainer. No commit reaches `main` without human review — the agent proposes, the human decides.

### License

GPL-3.0, inherited from HestiaCP.