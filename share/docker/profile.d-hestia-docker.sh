# shellcheck shell=sh
# HestiaRE: point a Docker-enabled customer at their companion's socket (#389).
# POSIX sh so bash, zsh, dash and sh all pick it up; per-user .bashrc would be
# bash-only and is overwritable in panel-managed homes. Guarded on the socket, so it
# stays inert for everyone else. Enforcing a login shell is deliberately not done.
if [ -S "$HOME/.companion/docker.sock" ]; then
	DOCKER_HOST="unix://$HOME/.companion/docker.sock"
	export DOCKER_HOST
fi
