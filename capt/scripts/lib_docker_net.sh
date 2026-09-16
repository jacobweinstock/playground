#!/usr/bin/env bash

# Package installs and iptables-backend selection shared by the NAT64 scripts.
#
# Meant to be sourced, not run.

# Debian rather than Alpine for the runtime image: alpine only carries tayga in
# edge/testing, which cannot be pinned alongside a stable base tag.
declare -r NET_PKGS="export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends tayga iptables iproute2 >/dev/null 2>&1"

# The bridge-address repair needs iproute2 and nothing else.
declare -r NET_PKGS_IPROUTE="export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends iproute2 >/dev/null 2>&1"

# Teardown needs no tayga, so it can skip Debian entirely -- `apt-get update`
# alone costs ~9s against ~1.4s for the apk equivalent, on every delete.
# Alpine still carries iptables-legacy, so IPT_PICK behaves identically.
declare -r CLEANUP_PKGS="apk add --no-cache iproute2-minimal iptables iptables-legacy >/dev/null 2>&1"

# The masquerade rule has to land in the same backend docker uses, or it is
# written to a table the kernel never consults on this traffic. Debian defaults
# to nft, which matches modern docker; fall back to legacy only if that is
# where the DOCKER chains actually are.
declare -r IPT_PICK='IPT=iptables; iptables-legacy -t nat -S 2>/dev/null | grep -q DOCKER && IPT=iptables-legacy'
