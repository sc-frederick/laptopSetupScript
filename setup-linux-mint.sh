#!/usr/bin/env bash

set -Eeuo pipefail

BRICSCAD_DEB=""
INSTALL_BRICSCAD=1
INSTALL_FLATPAKS=1
INSTALL_BEEPER=1
INSTALL_FAILURES=()

readonly BRICSCAD_DOWNLOAD_URL="https://www.bricsys.com/bricscad-download"
readonly BEEPER_DOWNLOAD_URL="https://api.beeper.com/desktop/download/linux/x64/stable/com.automattic.beeper.desktop"
readonly BITWARDEN_APP_ID="com.bitwarden.desktop"

usage() {
  cat <<'EOF'
Usage: ./setup-linux-mint.sh [options]

Prepare a Linux Mint Cinnamon laptop with development tools and desktop apps.

Options:
  --bricscad-deb PATH  Install this BricsCAD .deb instead of searching Downloads
  --no-bricscad        Do not search for or install BricsCAD
  --no-flatpaks        Do not install Bitwarden
  --no-beeper          Do not download or install the Beeper AppImage
  -h, --help           Show this help

Without --bricscad-deb, the newest *BricsCAD*.deb in the XDG downloads
directory (normally ~/Downloads) is installed. If none exists, setup continues
and prints the BricsCAD download URL.
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

add_apt_repositories() {
  local ubuntu_codename=${UBUNTU_CODENAME:-}

  case "$ubuntu_codename" in
    noble|resolute) ;;
    *) die "This setup requires Linux Mint based on Ubuntu 24.04 or 26.04; found ${ubuntu_codename:-unknown}" ;;
  esac

  log "Adding ButterRepo, Ghostty, Dropbox, and Cloudflare WARP repositories"

  curl -fsSL https://apt.justaguy.dev/key.asc \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/butterrepo.gpg >/dev/null
  printf '%s\n' \
    'deb [arch=amd64 signed-by=/usr/share/keyrings/butterrepo.gpg] https://apt.justaguy.dev stable main' \
    | sudo tee /etc/apt/sources.list.d/butterrepo.list >/dev/null

  curl -fsSL \
    'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0721FDF5FECB88DC6920361657C8EF455CEAE491' \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/ghostty-ubuntu.gpg >/dev/null
  printf '%s\n' \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/ghostty-ubuntu.gpg] https://ppa.launchpadcontent.net/mkasberg/ghostty-ubuntu/ubuntu $ubuntu_codename main" \
    | sudo tee /etc/apt/sources.list.d/ghostty-ubuntu.list >/dev/null

  # ButterRepo's Debian build outranks the Mint-compatible PPA by version.
  printf '%s\n' \
    'Package: ghostty' \
    'Pin: origin "apt.justaguy.dev"' \
    'Pin-Priority: -1' \
    | sudo tee /etc/apt/preferences.d/ghostty >/dev/null

  # Remove the Helium-only source written by earlier versions of this script.
  if [[ -f /etc/apt/sources.list.d/helium.list ]] \
    && grep -Fq 'pkg.helium.computer' /etc/apt/sources.list.d/helium.list; then
    sudo rm -f /etc/apt/sources.list.d/helium.list /usr/share/keyrings/helium.gpg
  fi

  curl -fsSL https://linux.dropbox.com/fedora/rpm-public-key.asc \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/dropbox.gpg >/dev/null
  printf '%s\n' \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/dropbox.gpg] https://linux.dropbox.com/ubuntu $ubuntu_codename main" \
    | sudo tee /etc/apt/sources.list.d/dropbox.list >/dev/null

  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null
  printf '%s\n' \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $ubuntu_codename main" \
    | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
}

install_apt_packages() {
  local fuse_package="libfuse2"
  local package
  local -a packages=(
    build-essential
    ca-certificates
    curl
    dropbox
    flatpak
    git
    gnupg
    jq
    libssl-dev
    pkg-config
    python3-gpg
    cloudflare-warp
    xdg-utils
  )
  local -a butterrepo_packages=(helium-browser neovim)

  log "Refreshing APT metadata"
  sudo apt-get update

  if apt-cache show libfuse2t64 >/dev/null 2>&1; then
    fuse_package="libfuse2t64"
  fi
  packages+=("$fuse_package")

  log "Installing system packages and Cloudflare WARP"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"

  log "Installing Ghostty from the Ubuntu-compatible PPA"
  if ! sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --allow-downgrades ghostty; then
    warn "Ghostty could not be installed from the Ubuntu-compatible PPA"
    INSTALL_FAILURES+=("ghostty")
  fi

  for package in "${butterrepo_packages[@]}"; do
    log "Installing $package from ButterRepo"
    if ! sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"; then
      warn "ButterRepo package $package is not compatible with this Mint release"
      INSTALL_FAILURES+=("$package")
    fi
  done
}

remove_dropbox_flatpak() {
  if flatpak info --user com.dropbox.Client >/dev/null 2>&1; then
    log "Removing the user-scoped Dropbox Flatpak"
    flatpak uninstall --user --noninteractive --assumeyes com.dropbox.Client
  fi
}

ensure_flatpak() {
  local app_id="$1"
  local label="$2"

  if flatpak info "$app_id" >/dev/null 2>&1; then
    log "$label is already installed"
    return
  fi

  if ! flatpak remotes --user --columns=name 2>/dev/null | grep -Fxq flathub; then
    log "Adding Flathub for the current user"
    flatpak remote-add --user --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo
  fi

  log "Installing $label"
  flatpak install --user --noninteractive --assumeyes flathub "$app_id"
}

install_mise() {
  local mise_bin="$HOME/.local/bin/mise"
  local bashrc="$HOME/.bashrc"
  local temp_bashrc
  local command
  local -a mise_commands=(erl rebar3 go rustc gleam node tsc opencode opencode2 codex)

  if [[ ! -x "$mise_bin" ]]; then
    log "Installing mise"
    curl -fsSL https://mise.run \
      | MISE_INSTALL_PATH="$mise_bin" sh
  else
    log "mise is already installed"
  fi

  log "Enabling mise in Bash"
  touch "$bashrc"
  temp_bashrc=$(mktemp)
  awk '
    $0 == "# laptop-setup: mise begin" { managed = 1; next }
    managed && $0 == "# laptop-setup: mise end" { managed = 0; next }
    managed { next }
    $0 == "# laptop-setup: mise" { legacy = 1; next }
    legacy && $0 == "eval \"$(~/.local/bin/mise activate bash)\"" { legacy = 0; next }
    legacy { legacy = 0 }
    { print }
  ' "$bashrc" >"$temp_bashrc"
  cat "$temp_bashrc" >"$bashrc"
  rm -f "$temp_bashrc"

  # Keep shims available even if prompt-driven activation does not update PATH.
  # shellcheck disable=SC2016
  printf '%s\n%s\n%s\n%s\n' \
    '# laptop-setup: mise begin' \
    'export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"' \
    'eval "$(~/.local/bin/mise activate bash)"' \
    '# laptop-setup: mise end' >>"$bashrc"

  log "Installing developer runtimes and CLIs with mise"
  "$mise_bin" use --global \
    erlang@latest \
    rebar@latest \
    go@latest \
    rust@latest \
    gleam@latest \
    node@lts \
    npm:typescript@latest \
    opencode@latest \
    'npm:@opencode-ai/cli@beta[allow_builds=@opencode-ai/cli]' \
    codex@latest

  "$mise_bin" reshim
  for command in "${mise_commands[@]}"; do
    "$mise_bin" which "$command" >/dev/null \
      || die "mise installed the toolset but could not resolve: $command"
  done
}

find_bricscad_deb() {
  local downloads_dir
  local file
  local newest=""
  local newest_mtime=0
  local mtime

  downloads_dir=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
  [[ -n "$downloads_dir" && -d "$downloads_dir" ]] \
    || downloads_dir="$HOME/Downloads"
  [[ -d "$downloads_dir" ]] || return 1

  while IFS= read -r -d '' file; do
    mtime=$(stat -c %Y "$file")
    if ((mtime > newest_mtime)); then
      newest="$file"
      newest_mtime=$mtime
    fi
  done < <(find "$downloads_dir" -maxdepth 1 -type f -iname '*bricscad*.deb' -print0)

  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

install_bricscad() {
  local package

  [[ -f "$BRICSCAD_DEB" ]] \
    || die "BricsCAD installer not found: $BRICSCAD_DEB"
  [[ "$BRICSCAD_DEB" == *.deb ]] \
    || die "BricsCAD installer must be a .deb file"

  package=$(dpkg-deb --field "$BRICSCAD_DEB" Package)
  case "$package" in
    bricscad*) ;;
    *) die "Unexpected package in BricsCAD installer: $package" ;;
  esac

  log "Installing BricsCAD from $BRICSCAD_DEB"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$BRICSCAD_DEB"
}

install_beeper() {
  local install_dir="$HOME/.local/opt/beeper"
  local beeper_bin="$install_dir/Beeper.AppImage"
  local source_file="$install_dir/source-url"
  local applications_dir="$HOME/.local/share/applications"
  local latest_url
  local temp_file

  latest_url=$(curl -fsSIL -o /dev/null -w '%{url_effective}' \
    "$BEEPER_DOWNLOAD_URL") \
    || die "Could not resolve the latest Beeper download"

  mkdir -p "$install_dir" "$applications_dir"
  if [[ ! -x "$beeper_bin" ]] \
    || [[ ! -f "$source_file" ]] \
    || [[ $(<"$source_file") != "$latest_url" ]]; then
    log "Downloading the latest Beeper AppImage"
    temp_file=$(mktemp "$install_dir/.Beeper.AppImage.XXXXXX")
    curl -fL --retry 3 -o "$temp_file" "$BEEPER_DOWNLOAD_URL"
    chmod 0755 "$temp_file"
    mv -f "$temp_file" "$beeper_bin"
    printf '%s\n' "$latest_url" >"$source_file"
  else
    log "Beeper is already up to date"
  fi

  cat >"$applications_dir/beeper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Beeper
Comment=Universal messaging app
Exec="$beeper_bin" %U
Icon=internet-chat
Terminal=false
Categories=Network;InstantMessaging;Chat;
StartupNotify=true
EOF
}

install_zoom_web_launcher() {
  local applications_dir="$HOME/.local/share/applications"
  local helium_bin

  helium_bin=$(command -v helium || command -v helium-browser || true)
  if [[ -z "$helium_bin" ]]; then
    warn "Skipping the Zoom web launcher because Helium is unavailable"
    return
  fi

  mkdir -p "$applications_dir"
  log "Installing the Zoom web-app launcher"
  cat >"$applications_dir/zoom-web.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Zoom Web
Comment=Join Zoom meetings in Helium
Exec="$helium_bin" --app=https://app.zoom.us/wc/home
TryExec=$helium_bin
Icon=video-display
Terminal=false
Categories=Network;VideoConference;
StartupNotify=true
EOF
}

while (($#)); do
  case "$1" in
    --bricscad-deb)
      (($# >= 2)) || die "--bricscad-deb requires a path"
      BRICSCAD_DEB="$2"
      shift 2
      ;;
    --no-bricscad)
      INSTALL_BRICSCAD=0
      shift
      ;;
    --no-flatpaks)
      INSTALL_FLATPAKS=0
      shift
      ;;
    --no-beeper)
      INSTALL_BEEPER=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ $EUID -ne 0 ]] || die "Run this script as your normal user, not with sudo"

[[ -r /etc/os-release ]] || die "Cannot identify this operating system"
# shellcheck source=/dev/null
. /etc/os-release
[[ ${ID:-} == linuxmint ]] \
  || die "This script is intended for Linux Mint; found ${PRETTY_NAME:-unknown}"
[[ $(uname -m) == x86_64 ]] \
  || die "BricsCAD and this Beeper setup require an x86-64 machine"

require_command sudo
require_command curl
require_command gpg
sudo -v

add_apt_repositories
install_apt_packages
remove_dropbox_flatpak

if ((INSTALL_FLATPAKS)); then
  ensure_flatpak "$BITWARDEN_APP_ID" "Bitwarden"
fi

install_mise
install_zoom_web_launcher

if ((INSTALL_BEEPER)); then
  install_beeper
fi

if ((INSTALL_BRICSCAD)); then
  if [[ -z "$BRICSCAD_DEB" ]]; then
    BRICSCAD_DEB=$(find_bricscad_deb || true)
  fi
  if [[ -n "$BRICSCAD_DEB" ]]; then
    install_bricscad
  else
    warn "No BricsCAD .deb was found in the downloads directory"
    printf 'Download the Ubuntu installer after signing in at:\n  %s\n' \
      "$BRICSCAD_DOWNLOAD_URL"
    printf 'Then rerun with: %q --bricscad-deb /path/to/BricsCAD.deb\n' "$0"
  fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

log "Setup complete"
printf '%s\n' \
  'Open a new terminal before using gleam, go, rustc, tsc, opencode, opencode2, or codex.' \
  'Run dropbox start -i, follow the account link, and launch Bitwarden to sign in.' \
  'Launch Cloudflare WARP from Cinnamon and complete its first-run registration.' \
  'Launch Zoom Web and Beeper from the Cinnamon application menu.'

if ((${#INSTALL_FAILURES[@]})); then
  printf 'Setup could not install: %s\n' "${INSTALL_FAILURES[*]}" >&2
  exit 1
fi
