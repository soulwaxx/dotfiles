#!/usr/bin/env zsh
# ============================================================================
# AWS SSO profile switching (aws-sso-cli)
# ============================================================================

# ============================================================================
# AWS SSO (native aws-sso-cli)
# ============================================================================

# bashcompinit required for aws CLI (aws_completer) and aws-sso native completion
if (( ! $+functions[bashcompinit] )); then
    autoload -Uz bashcompinit && bashcompinit
fi

if [[ -z "$AWS_SSO_BIN" ]]; then
    AWS_SSO_BIN="$(command -v aws-sso 2>/dev/null)"
    [[ -z "$AWS_SSO_BIN" && -x /opt/homebrew/bin/aws-sso ]] && AWS_SSO_BIN="/opt/homebrew/bin/aws-sso"
fi

if [[ -n "$AWS_SSO_BIN" ]] && command -v complete &>/dev/null; then
    complete -C "$AWS_SSO_BIN" aws-sso
fi

# Unset every env var that aws-sso eval --profile sets.
# aws-sso eval -c is broken when AWS_SSO_ACCOUNT_ID has a leading zero
# (the upgraded cli rejects it as an invalid int64 before generating output).
_awssso_clear_env() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
    unset AWS_SSO_PROFILE AWS_SSO_ACCOUNT_ID AWS_SSO_ROLE_NAME AWS_SSO_ROLE_ARN \
          AWS_SSO_SESSION_EXPIRATION AWS_SSO_DEFAULT_REGION AWS_SSO
}

# fzf-based interactive profile switcher — eval is unavoidable for current-shell injection
awsp() {
    # Clear stale env vars FIRST
    _awssso_clear_env

    local profiles
    profiles=$(aws-sso list --csv Profile 2>/dev/null | \
        awk 'NR==1 && $0=="Profile" { next } $0!="" { print }')

    if [[ -z "$profiles" ]]; then
        echo "aws-sso: no cached profiles — logging in..." >&2
        aws-sso login || return 1
        profiles=$(aws-sso list --csv Profile 2>/dev/null | \
            awk 'NR==1 && $0=="Profile" { next } $0!="" { print }')
    fi

    local profile
    profile=$(printf '%s\n' "$profiles" | \
        fzf --prompt='AWS SSO > ' --height=50% --border) || return 0
    [[ -z "$profile" ]] && return 0

    # `aws-sso eval` inside command substitution cannot drive the browser
    # login flow — run login explicitly so the token is fresh before the capture.
    aws-sso login || return 1

    eval "$(aws-sso eval --profile "$profile")"
}

alias awsi='aws-sso list'
alias awscon='aws-sso console'

# Unset current-shell AWS env vars (aws-sso flush no longer exists in v2+)
awsc() {
    _awssso_clear_env
    echo "aws-sso: env vars cleared" >&2
}
