#!/usr/bin/env bash
# Case-insensitive comparison for explicit, non-empty consent tokens.
# Keep exact spelling otherwise: no whitespace trimming or default approval.
mu_consent_matches()
{
    local given="${1:-}" expected="${2:-}"
    [[ -n "$given" && -n "$expected" && "${given^^}" == "${expected^^}" ]]
}
