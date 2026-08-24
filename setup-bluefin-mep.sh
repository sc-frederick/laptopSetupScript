#!/usr/bin/env bash

set -Eeuo pipefail

BOX_NAME="${BOX_NAME:-bricscad-ubuntu}"
BRICSCAD_DEB=""
INSTALL_FLATPAKS=1
NVIDIA_MODE="auto"

readonly BOX_IMAGE="docker.io/library/ubuntu:24.04"
readonly BRICSCAD_DOWNLOAD_URL="https://www.bricsys.com/bricscad-download"
readonly DROPBOX_APP_ID="com.dropbox.Client"
readonly LIBREOFFICE_APP_ID="org.libreoffice.LibreOffice"

usage() {
  cat <<'EOF'
Usage: ./setup-bluefin-mep.sh [options]

Prepare Bluefin for BricsCAD, Dropbox, and LibreOffice.

Options:
  --bricscad-deb PATH  Install a BricsCAD .deb downloaded from Bricsys
  --box-name NAME      Distrobox name (default: bricscad-ubuntu)
  --nvidia             Force NVIDIA integration when creating the box
  --no-nvidia          Do not add NVIDIA integration when creating the box
  --no-flatpaks        Do not install Dropbox or LibreOffice on the host
  -h, --help           Show this help

Environment overrides:
  BOX_NAME             Distrobox name

Run once without --bricscad-deb to prepare the laptop. After downloading the
vendor installer, rerun with --bricscad-deb ~/Downloads/BricsCAD-*.deb.
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

box_exists() {
  distrobox list 2>/dev/null | awk -F '|' -v name="$BOX_NAME" '
    NR > 1 {
      candidate = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate)
      if (candidate == name) found = 1
    }
    END { exit !found }
  '
}

run_in_box() {
  distrobox enter --name "$BOX_NAME" -- "$@"
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

  log "Installing $label as a host Flatpak"
  flatpak install --user --noninteractive --assumeyes flathub "$app_id"
}

create_box() {
  local -a create_args
  local use_nvidia=0

  if box_exists; then
    log "Using existing distrobox: $BOX_NAME"
    return
  fi

  case "$NVIDIA_MODE" in
    yes)
      use_nvidia=1
      ;;
    auto)
      if command -v nvidia-smi >/dev/null 2>&1; then
        use_nvidia=1
      fi
      ;;
  esac

  create_args=(create --name "$BOX_NAME" --image "$BOX_IMAGE" --yes)
  if ((use_nvidia)); then
    create_args+=(--nvidia)
    log "NVIDIA driver detected; enabling Distrobox NVIDIA integration"
  fi

  log "Creating Ubuntu 24.04 distrobox: $BOX_NAME"
  distrobox "${create_args[@]}"
}

prepare_box() {
  log "Installing BricsCAD GUI prerequisites in $BOX_NAME"
  run_in_box bash -lc '
    set -Eeuo pipefail
    . /etc/os-release
    if [[ "$ID" != ubuntu ]]; then
      printf "Expected Ubuntu, found %s\n" "$ID" >&2
      exit 1
    fi
    if [[ "$VERSION_ID" != 24.04 ]]; then
      printf "Expected Ubuntu 24.04, found %s; use a different --box-name\n" \
        "$VERSION_ID" >&2
      exit 1
    fi
    sudo env DEBIAN_FRONTEND=noninteractive apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      dbus-x11 \
      desktop-file-utils \
      fontconfig \
      libglu1-mesa \
      libopengl0 \
      mesa-utils \
      x11-utils \
      xdg-utils
  '
}

export_bricscad_launcher() {
  run_in_box bash -lc '
    set -Eeuo pipefail
    package=$(dpkg-query -W -f="\${binary:Package}\n" "bricscad*" 2>/dev/null \
      | awk "/^bricscad/ { print }" | sort -V | tail -n 1)
    [[ -n "$package" ]] || exit 1
    desktop_file=$(dpkg-query -L "$package" \
      | awk "/\/applications\/.*[.]desktop$/ { print; exit }")
    [[ -n "$desktop_file" ]] || exit 2
    distrobox-export --app "$desktop_file"
  '
}

bricscad_is_installed() {
  run_in_box bash -lc '
    dpkg-query -W -f="\${db:Status-Abbrev}\n" "bricscad*" 2>/dev/null \
      | awk "\$1 ~ /^ii/ { found=1 } END { exit !found }"
  '
}

install_bricscad() {
  local cache_dir="$HOME/.cache/bluefin-mep-setup"
  local cached_deb

  [[ -f "$BRICSCAD_DEB" ]] || die "BricsCAD installer not found: $BRICSCAD_DEB"
  [[ "$BRICSCAD_DEB" == *.deb ]] || die "BricsCAD installer must be a .deb file"

  mkdir -p "$cache_dir"
  cached_deb="$cache_dir/bricscad-installer.deb"
  if [[ "$BRICSCAD_DEB" != "$cached_deb" ]]; then
    cp -- "$BRICSCAD_DEB" "$cached_deb"
  fi

  log "Installing the BricsCAD vendor package in $BOX_NAME"
  run_in_box bash -lc '
    set -Eeuo pipefail
    deb=$1
    package=$(dpkg-deb --field "$deb" Package)
    case "$package" in
      bricscad*) ;;
      *)
        printf "Unexpected package in installer: %s\n" "$package" >&2
        exit 1
        ;;
    esac
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb"
    desktop_file=$(dpkg-query -L "$package" \
      | awk "/\/applications\/.*[.]desktop$/ { print; exit }")
    if [[ -z "$desktop_file" ]]; then
      printf "No desktop launcher found in package %s\n" "$package" >&2
      exit 1
    fi
    distrobox-export --app "$desktop_file"
  ' bash "$cached_deb"

  log "Exported BricsCAD to the Bluefin application launcher"
}

check_graphics() {
  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY is not set; run this script from your graphical login to test X11"
    return
  fi

  log "Checking X11 access from $BOX_NAME"
  if ! run_in_box xdpyinfo >/dev/null 2>&1; then
    warn "The box cannot reach X11 display $DISPLAY; BricsCAD GUI will not start yet"
    return
  fi

  printf 'X11 display %s is reachable from the distrobox.\n' "$DISPLAY"
  log "OpenGL renderer visible inside the distrobox"
  if ! run_in_box glxinfo -B; then
    warn "X11 works, but OpenGL validation failed; check the host GPU driver"
  fi
}

while (($#)); do
  case "$1" in
    --bricscad-deb)
      (($# >= 2)) || die "--bricscad-deb requires a path"
      BRICSCAD_DEB="$2"
      shift 2
      ;;
    --box-name)
      (($# >= 2)) || die "--box-name requires a name"
      BOX_NAME="$2"
      shift 2
      ;;
    --nvidia)
      NVIDIA_MODE="yes"
      shift
      ;;
    --no-nvidia)
      NVIDIA_MODE="no"
      shift
      ;;
    --no-flatpaks)
      INSTALL_FLATPAKS=0
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
[[ "$BOX_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] \
  || die "Invalid distrobox name: $BOX_NAME"

if ! grep -Eiq 'bluefin|ublue' /etc/os-release; then
  warn "This host does not identify itself as Bluefin; continuing without host OS changes"
fi

require_command distrobox
if [[ $(uname -m) != x86_64 ]]; then
  die "BricsCAD for Linux requires an x86-64 machine"
fi

if ((INSTALL_FLATPAKS)); then
  require_command flatpak
  ensure_flatpak "$LIBREOFFICE_APP_ID" "LibreOffice"
  ensure_flatpak "$DROPBOX_APP_ID" "Dropbox"
fi

create_box
prepare_box

if [[ -n "$BRICSCAD_DEB" ]]; then
  install_bricscad
elif bricscad_is_installed; then
  export_bricscad_launcher \
    || die "BricsCAD is installed, but its application launcher could not be exported"
  log "BricsCAD is already installed; refreshed its application launcher"
else
  log "BricsCAD container is ready"
  printf 'Download the Ubuntu .deb after signing in at:\n  %s\n' "$BRICSCAD_DOWNLOAD_URL"
  printf 'Then rerun with the actual downloaded filename:\n'
  printf '  %q --bricscad-deb ~/Downloads/BricsCAD-installer.deb\n' "$0"
fi

check_graphics

log "Setup complete"
if ((INSTALL_FLATPAKS)); then
  printf 'Dropbox and LibreOffice run on the host; BricsCAD runs in distrobox %q.\n' "$BOX_NAME"
else
  printf 'BricsCAD runs in distrobox %q; host Flatpaks were skipped.\n' "$BOX_NAME"
fi
