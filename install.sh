#!/usr/bin/env bash
# install.sh — EdgeFirst Profiler CLI installer for Linux and macOS.
# Copyright (c) 2026 Au-Zone Technologies Inc.
# Licensed under the EdgeFirst Profiler CLI End User License (LICENSE).

set -euo pipefail

REPO="EdgeFirstAI/profiler-cli"

# ---------- Pure helpers (no network, no filesystem writes) -----------------

detect_os() {
    case "$(uname -s)" in
        Linux*)  printf 'linux\n' ;;
        Darwin*) printf 'macos\n' ;;
        *)       printf 'unknown\n' ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   printf 'x86_64\n' ;;
        aarch64|arm64)  printf 'aarch64\n' ;;
        *)              printf 'unknown\n' ;;
    esac
}

asset_extension_for_os() {
    case "$1" in
        linux|macos) printf 'tar.gz\n' ;;
        windows)     printf 'zip\n' ;;
        *)           printf 'unknown\n' ;;
    esac
}

build_asset_name() {
    # build_asset_name <version> <os> <arch>
    local version="$1" os="$2" arch="$3"
    local ext
    ext="$(asset_extension_for_os "$os")"
    printf 'edgefirst-profiler-%s-%s-%s.%s\n' "$version" "$os" "$arch" "$ext"
}

default_prefix() {
    # Returns /usr/local/bin if root, else $HOME/.local/bin.
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        printf '/usr/local/bin\n'
    else
        printf '%s/.local/bin\n' "$HOME"
    fi
}

# ---------- Self-test -------------------------------------------------------

self_test() {
    local fail=0 actual expected

    expected="edgefirst-profiler-0.2.0-linux-x86_64.tar.gz"
    actual="$(build_asset_name 0.2.0 linux x86_64)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL build_asset_name linux x86_64: got %s\n' "$actual" >&2
        fail=1
    fi

    expected="edgefirst-profiler-0.2.0-linux-aarch64.tar.gz"
    actual="$(build_asset_name 0.2.0 linux aarch64)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL build_asset_name linux aarch64: got %s\n' "$actual" >&2
        fail=1
    fi

    expected="edgefirst-profiler-0.2.0-macos-aarch64.tar.gz"
    actual="$(build_asset_name 0.2.0 macos aarch64)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL build_asset_name macos aarch64: got %s\n' "$actual" >&2
        fail=1
    fi

    expected="edgefirst-profiler-0.2.0-windows-x86_64.zip"
    actual="$(build_asset_name 0.2.0 windows x86_64)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL build_asset_name windows x86_64: got %s\n' "$actual" >&2
        fail=1
    fi

    if [ "$(asset_extension_for_os linux)" != "tar.gz" ]; then
        printf 'FAIL asset_extension_for_os linux\n' >&2
        fail=1
    fi
    if [ "$(asset_extension_for_os windows)" != "zip" ]; then
        printf 'FAIL asset_extension_for_os windows\n' >&2
        fail=1
    fi
    if [ "$(asset_extension_for_os freebsd)" != "unknown" ]; then
        printf 'FAIL asset_extension_for_os freebsd\n' >&2
        fail=1
    fi

    # detect_os/detect_arch can't be exhaustively unit-tested without
    # mocking uname; assert they return one of the documented values.
    case "$(detect_os)" in
        linux|macos|unknown) ;;
        *) printf 'FAIL detect_os returned unexpected value\n' >&2; fail=1 ;;
    esac
    case "$(detect_arch)" in
        x86_64|aarch64|unknown) ;;
        *) printf 'FAIL detect_arch returned unexpected value\n' >&2; fail=1 ;;
    esac

    if [ $fail -eq 0 ]; then
        printf 'install.sh self-test: PASS\n'
        return 0
    fi
    printf 'install.sh self-test: FAIL\n' >&2
    return 1
}

# ---------- Side-effecting helpers -----------------------------------------

usage() {
    cat <<'EOF'
install.sh — EdgeFirst Profiler CLI installer (Linux and macOS)

Usage:
  install.sh [--version X.Y.Z] [--prefix DIR] [--no-verify-checksum]
  install.sh --self-test
  install.sh --help

Options:
  --version X.Y.Z         Install a specific version (default: latest release).
  --prefix DIR            Install into DIR (default: /usr/local/bin if root, else ~/.local/bin).
  --no-verify-checksum    Skip SHA-256 verification (NOT recommended).
  --self-test             Run internal sanity checks and exit.
  --help                  Print this help and exit.

Examples:
  curl -fsSL https://raw.githubusercontent.com/EdgeFirstAI/profiler-cli/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/EdgeFirstAI/profiler-cli/main/install.sh | bash -s -- --version 0.2.0
EOF
}

err() { printf 'error: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "required command not found: $1"
        return 1
    fi
}

# resolve_latest_version queries the GitHub Releases API for the latest tag.
# Prints the version (with leading 'v' stripped). Exits non-zero on failure.
resolve_latest_version() {
    local api="https://api.github.com/repos/${REPO}/releases/latest"
    local response tag
    if ! response="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api")"; then
        err "could not reach $api (network error or GitHub API rate limit)"
        err "hint: set GITHUB_TOKEN to authenticate, or pass --version X.Y.Z to skip this lookup"
        return 1
    fi
    # The /releases/latest endpoint returns one release object with one tag_name,
    # but defensively take the first match if anything ever produces more.
    tag="$(printf '%s' "$response" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p')"
    if [ -z "$tag" ]; then
        err "could not parse latest release tag from $api"
        return 1
    fi
    printf '%s\n' "${tag#v}"
}

# release_asset_url <version> <asset_name>
release_asset_url() {
    local version="$1" asset="$2"
    printf 'https://github.com/%s/releases/download/v%s/%s\n' "$REPO" "$version" "$asset"
}

verify_sha256() {
    # verify_sha256 <archive_path> <sha256_path>
    local archive="$1" sums="$2"
    local expected actual
    expected="$(awk '{print $1; exit}' "$sums")"
    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$archive" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
    else
        err "no sha256sum or shasum available; cannot verify checksum"
        return 1
    fi
    if [ "$expected" != "$actual" ]; then
        err "checksum mismatch: expected $expected, got $actual"
        return 1
    fi
}

extract_archive() {
    # extract_archive <archive_path> <dest_dir>
    local archive="$1" dest="$2"
    case "$archive" in
        *.tar.gz) tar -xzf "$archive" -C "$dest" ;;
        *)        err "unsupported archive type: $archive"; return 1 ;;
    esac
}

# ---------- Entry point -----------------------------------------------------

main() {
    local version="" prefix="" no_verify=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --version)
                shift
                if [ $# -eq 0 ]; then err "--version requires an argument"; return 2; fi
                version="$1"
                ;;
            --prefix)
                shift
                if [ $# -eq 0 ]; then err "--prefix requires an argument"; return 2; fi
                prefix="$1"
                ;;
            --no-verify-checksum) no_verify=1 ;;
            --self-test) self_test; return $? ;;
            --help|-h) usage; return 0 ;;
            *) err "unknown argument: $1"; usage >&2; return 2 ;;
        esac
        shift
    done

    require_cmd curl
    require_cmd tar
    require_cmd uname

    local os arch
    os="$(detect_os)"
    arch="$(detect_arch)"
    if [ "$os" = "unknown" ] || [ "$arch" = "unknown" ]; then
        err "unsupported platform: os=$os arch=$arch"
        err "supported: linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64"
        return 1
    fi

    if [ -z "$version" ]; then
        info "Resolving latest version from github.com/${REPO}..."
        version="$(resolve_latest_version)"
    fi
    info "Installing edgefirst-profiler v${version} for ${os}-${arch}"

    [ -z "$prefix" ] && prefix="$(default_prefix)"

    local asset url archive sums
    asset="$(build_asset_name "$version" "$os" "$arch")"
    url="$(release_asset_url "$version" "$asset")"
    # tmpdir is intentionally NOT declared `local` so the EXIT trap can
    # still see it after the function returns. The previous version
    # used `local tmpdir` + `trap 'rm -rf "$tmpdir"' EXIT`; that printed
    # `tmpdir: unbound variable` on every run (and leaked the temp dir)
    # because the local went out of scope before EXIT fired.
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir:-}"' EXIT
    archive="$tmpdir/$asset"
    sums="$tmpdir/${asset}.sha256"

    info "Downloading $asset..."
    if ! curl -fsSL --output "$archive" "$url"; then
        err "could not download $url"
        err "if you pinned --version, confirm it exists at https://github.com/${REPO}/releases"
        return 1
    fi

    if [ "$no_verify" -eq 0 ]; then
        info "Verifying SHA-256..."
        if ! curl -fsSL --output "$sums" "${url}.sha256"; then
            err "could not download checksum file ${url}.sha256"
            return 1
        fi
        if ! verify_sha256 "$archive" "$sums"; then
            rm -f "$archive"
            return 1
        fi
    else
        info "WARNING: --no-verify-checksum was specified; skipping integrity check."
    fi

    info "Extracting..."
    extract_archive "$archive" "$tmpdir"

    if [ ! -d "$prefix" ]; then
        if ! mkdir -p "$prefix" 2>/dev/null; then
            err "could not create install directory: $prefix"
            err "try a writable --prefix DIR or run with sudo"
            return 1
        fi
    fi
    if [ ! -w "$prefix" ]; then
        err "install directory is not writable: $prefix"
        err "try a writable --prefix DIR or run with sudo"
        return 1
    fi

    local bin_src="$tmpdir/edgefirst-profiler"
    if [ ! -f "$bin_src" ]; then
        # Some archives unpack into a versioned subdirectory; locate the binary.
        bin_src="$(find "$tmpdir" -maxdepth 3 -type f -name 'edgefirst-profiler' -print -quit)"
    fi
    if [ -z "$bin_src" ] || [ ! -f "$bin_src" ]; then
        err "edgefirst-profiler binary not found in archive"
        return 1
    fi

    install -m 0755 "$bin_src" "$prefix/edgefirst-profiler"
    info "Installed to $prefix/edgefirst-profiler"

    case ":$PATH:" in
        *:"$prefix":*) : ;;
        *)
            info ""
            info "Note: $prefix is not on your PATH."
            info "Add it for this shell:    export PATH=\"$prefix:\$PATH\""
            info "Or persist in your shell profile (~/.bashrc, ~/.zshrc, etc.)."
            ;;
    esac

    info ""
    info "Verifying install..."
    local installed_output
    if ! installed_output="$("$prefix/edgefirst-profiler" --version 2>&1)"; then
        err "post-install --version check failed"
        printf '%s\n' "$installed_output" >&2
        return 1
    fi
    printf '%s\n' "$installed_output"
    if ! printf '%s' "$installed_output" | grep -qF "$version"; then
        err "version mismatch: --version output does not contain '$version'"
        err "this could indicate a corrupt download or a wrong asset"
        return 1
    fi
}

main "$@"
