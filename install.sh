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

# ---------- Entry point -----------------------------------------------------

main() {
    case "${1:-}" in
        --self-test) self_test ;;
        *)
            printf 'install.sh: not yet implemented (Task 6 adds main body)\n' >&2
            return 1
            ;;
    esac
}

main "$@"
