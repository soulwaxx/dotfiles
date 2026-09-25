#!/usr/bin/env bash
# Keep the legacy hook path valid while the activated Home Manager generation
# still exposes an out-of-store symlink to it. The semantic scanner supersedes
# this hook but includes all established git-bypass checks.

exec bash "$(dirname -- "${BASH_SOURCE[0]}")/semantic-command-scanner.sh"
