#!/usr/bin/env zsh
# ============================================================================
# Work-specific general utility functions
# ============================================================================

# ============================================================================
# GENERAL UTILITY FUNCTIONS
# ============================================================================

# Extract various archive formats
_require_cmd() {
    command -v "$1" >/dev/null 2>&1
}

extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   _require_cmd tar || { echo "Missing 'tar'"; return 1; }; tar xjf "$1"     ;;
            *.tar.gz)    _require_cmd tar || { echo "Missing 'tar'"; return 1; }; tar xzf "$1"     ;;
            *.bz2)       _require_cmd bunzip2 || { echo "Missing 'bunzip2'"; return 1; }; bunzip2 "$1" ;;
            *.rar)       _require_cmd unrar || { echo "Missing 'unrar'"; return 1; }; unrar x "$1"  ;;
            *.gz)        _require_cmd gunzip || { echo "Missing 'gunzip'"; return 1; }; gunzip "$1" ;;
            *.tar)       _require_cmd tar || { echo "Missing 'tar'"; return 1; }; tar xf "$1"      ;;
            *.tbz2)      _require_cmd tar || { echo "Missing 'tar'"; return 1; }; tar xjf "$1"     ;;
            *.tgz)       _require_cmd tar || { echo "Missing 'tar'"; return 1; }; tar xzf "$1"     ;;
            *.zip)       _require_cmd unzip || { echo "Missing 'unzip'"; return 1; }; unzip "$1"   ;;
            *.Z)         _require_cmd uncompress || { echo "Missing 'uncompress'"; return 1; }; uncompress "$1" ;;
            *.7z)        _require_cmd 7z  || { echo "Missing '7z'";  return 1; }; 7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Zip a folder and create foldername.zip
zipf() {
    if [ -z "$1" ]; then
        echo "Usage: zipf <folder>"
        return 1
    fi

    if [ ! -d "$1" ]; then
        echo "Error: '$1' is not a directory"
        return 1
    fi

    # Remove trailing slash if present
    local folder="${1%/}"
    local zipname="${folder}.zip"

    zip -r "$zipname" "$folder"
    echo "Created: $zipname"
}

# Quick weather check
weather() {
    curl -fsS "wttr.in/${1:-}"
}

terraform-clear() {
    local include_locks=0 reply
    case "${1:-}" in
        --locks|--lock-files)
            include_locks=1
            ;;
        -h|--help)
            echo "Usage: terraform-clear [--locks]"
            echo "  Default: delete .terraform directories only"
            echo "  --locks: also delete .terraform.lock.hcl files after confirmation"
            return 0
            ;;
        "") ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: terraform-clear [--locks]"
            return 1
            ;;
    esac

    echo "Searching for Terraform files to clean..."
    echo ""

    # Find and display what will be deleted
    local terraform_dirs=$(find . -type d -name ".terraform" 2>/dev/null)
    local lock_files=""
    if (( include_locks )); then
        lock_files=$(find . -type f -name ".terraform.lock.hcl" 2>/dev/null)
    fi

    if [[ -z "$terraform_dirs" && -z "$lock_files" ]]; then
        echo "No Terraform files found to clean"
        if (( ! include_locks )); then
            echo "Lock files are preserved by default; use 'terraform-clear --locks' to include them."
        fi
        return 0
    fi

    # Show what will be deleted
    if [[ -n "$terraform_dirs" ]]; then
        echo ".terraform directories found:"
        echo "$terraform_dirs"
        echo ""
    fi

    if [[ -n "$lock_files" ]]; then
        echo "Lock files found:"
        echo "$lock_files"
        echo ""
    elif (( ! include_locks )); then
        echo "Lock files are preserved by default; use 'terraform-clear --locks' to include them."
        echo ""
    fi

    # Ask for confirmation
    echo -n "Delete these files? (y/N): "
    read reply

    if [[ $reply =~ ^[Yy]$ ]]; then
        # Delete .terraform directories
        find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null
        if (( include_locks )); then
            find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null
        fi
        echo "Cleanup complete!"
    else
        echo "Cleanup cancelled"
    fi
}
