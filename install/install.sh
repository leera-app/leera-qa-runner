#!/bin/sh
# Installs the QA runner on macOS or Linux and, optionally, connects it and starts it as a service.
#
#   curl -fsSL https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.sh | sh
#   curl -fsSL …/install.sh | RUNNER_TOKEN=pm_run_… sh -s -- --url https://app.example.com --service
#
# Options:
#   --version X       Install this version (default: the latest release)
#   --prefix DIR      Linux only: install under DIR/lib and link DIR/bin (default: ~/.local)
#   --url URL         Connect to this server after installing
#   --token TOKEN     Runner token for --url (prefer the RUNNER_TOKEN environment variable)
#   --name NAME       Runner name (default: host name)
#   --service         Install and start the background service
#   --no-browsers     Do not download Chromium
#   --base-url URL    Release download base (default: GitHub releases; also QA_RUNNER_DOWNLOAD_BASE)
#
# Every download is checked against the release's SHA256SUMS.
set -eu

REPO_RELEASES="https://github.com/leera-app/leera-qa-runner/releases"
version=""
prefix=""
url=""
token="${RUNNER_TOKEN:-}"
name=""
service=0
browsers=1
base="${QA_RUNNER_DOWNLOAD_BASE:-}"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || die "--version needs a value"; version="${2#v}"; shift 2 ;;
    --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix="$2"; shift 2 ;;
    --url) [ $# -ge 2 ] || die "--url needs a value"; url="$2"; shift 2 ;;
    --token) [ $# -ge 2 ] || die "--token needs a value"; token="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || die "--name needs a value"; name="$2"; shift 2 ;;
    --service) service=1; shift ;;
    --no-browsers) browsers=0; shift ;;
    --base-url) [ $# -ge 2 ] || die "--base-url needs a value"; base="$2"; shift 2 ;;
    -h | --help) sed -n '2,20p' "$0" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) die "unsupported system $(uname -s); on Windows use install.ps1" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac

if [ "$os" = macos ]; then
  asset="leera-qa-runner-macos-$arch.pkg"
  [ -z "$prefix" ] || die "--prefix is not supported on macOS; the package installs to /usr/local"
else
  asset="leera-qa-runner-linux-$arch.tar.gz"
fi

# Where the assets live: …/download/vX/<asset>, or …/latest/download/<asset> without --version.
base="${base%/}"
if [ -n "$version" ]; then
  from="${base:-$REPO_RELEASES/download}/v$version"
elif [ -z "$base" ]; then
  from="$REPO_RELEASES/latest/download"
else
  die "--version is required with a custom download base"
fi

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "curl or wget is required"
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "sha256sum or shasum is required to verify the download"
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

say "Downloading $asset from $from"
fetch "$from/$asset" "$work/$asset" || die "could not download $from/$asset"
fetch "$from/SHA256SUMS" "$work/SHA256SUMS" || die "could not download $from/SHA256SUMS"
expected="$(awk -v a="$asset" '$2 == a || $2 == "*" a {print $1; exit}' "$work/SHA256SUMS")"
[ -n "$expected" ] || die "SHA256SUMS does not list $asset"
actual="$(sha256_of "$work/$asset")"
[ "$expected" = "$actual" ] || die "checksum mismatch for $asset (expected $expected, got $actual)"
say "Checksum verified."

runner_home="${LEERA_RUNNER_HOME:-$HOME/.leera-qa-runner}"

if [ "$os" = macos ]; then
  if [ "$(id -u)" -eq 0 ]; then
    installer -pkg "$work/$asset" -target /
  else
    say "Installing the package needs administrator rights:"
    sudo installer -pkg "$work/$asset" -target /
  fi
  bin="/usr/local/bin/leera-qa-runner"
  method=pkg
  install_prefix=/usr/local
  installed_version="$("$bin" version)"
  installed_version="${installed_version##* }"
else
  prefix="${prefix:-$HOME/.local}"
  tar -xzf "$work/$asset" -C "$work"
  bundle="$work/leera-qa-runner-linux-$arch"
  [ -d "$bundle" ] || die "the archive does not contain leera-qa-runner-linux-$arch/"
  installed_version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$bundle/build-info.json" | head -n 1)"
  [ -n "$installed_version" ] || die "could not read the version from the archive"
  target="$prefix/lib/leera-qa-runner/$installed_version"
  mkdir -p "$prefix/lib/leera-qa-runner" "$prefix/bin"
  rm -rf "$target"
  mv "$bundle" "$target"
  ln -sfn "$target/bin/leera-qa-runner" "$prefix/bin/leera-qa-runner"
  bin="$prefix/bin/leera-qa-runner"
  method=tar
  install_prefix="$prefix"
  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) say "Note: $prefix/bin is not on your PATH; add it to your shell profile." ;;
  esac
fi

# install.json tells `leera-qa-runner update` how this copy was installed.
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
mkdir -p "$runner_home"
chmod 700 "$runner_home"
printf '{"method":"%s","version":"%s","installed_at":"%s","prefix":"%s","path":"%s"}\n' \
  "$method" "$(json_escape "$installed_version")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(json_escape "$install_prefix")" "$(json_escape "$bin")" > "$runner_home/install.json"
chmod 600 "$runner_home/install.json"
say "Installed leera-qa-runner $installed_version at $bin"

if [ "$browsers" -eq 1 ]; then
  "$bin" setup browsers
fi

if [ -n "$url" ]; then
  [ -n "$token" ] || die "--url needs a token: set RUNNER_TOKEN or pass --token"
  if [ -n "$name" ]; then
    printf '%s\n' "$token" | "$bin" connect --url "$url" --name "$name" --token-stdin
  else
    printf '%s\n' "$token" | "$bin" connect --url "$url" --token-stdin
  fi
fi

if [ "$service" -eq 1 ]; then
  "$bin" service install
fi

say "Done. Run '$bin doctor' to check this machine."
