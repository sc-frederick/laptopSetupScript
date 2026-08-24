# Bluefin MEP laptop setup

This repository prepares a [Bluefin](https://projectbluefin.io/) laptop for
BricsCAD, Dropbox, and LibreOffice without changing Bluefin's image-managed
base operating system.

## Why the software is split up

Bluefin is a Fedora-based atomic desktop. Its `/usr` tree comes from a signed,
bootable image and updates as a unit. That is why this setup does not use
`dnf`, `rpm-ostree install`, or Ubuntu packages on the host.

Bluefin's Homebrew installation is intended for host command-line tools. None
of these three desktop applications needs a Homebrew package, so this script
does not modify Homebrew.

- BricsCAD runs in an Ubuntu 24.04 Distrobox, where its vendor `.deb` is
  supported and isolated from host package updates.
- LibreOffice runs as the Flathub Flatpak on the host. The script leaves an
  existing installation alone.
- Dropbox runs as the Flathub Flatpak on the host so login startup, tray
  integration, and file syncing are not tied to a container lifecycle.

Distrobox shares your home directory, X11/Wayland sockets, audio, and devices
with the host. It is integration tooling, not a security sandbox. BricsCAD
will therefore see the same home files as host applications.

## Run it

Run the initial setup from a terminal in your graphical Bluefin session:

```bash
chmod +x setup-bluefin-mep.sh
./setup-bluefin-mep.sh
```

Bricsys requires an account login and does not publish a stable unattended
download URL. Download the current 64-bit Ubuntu `.deb` from the URL printed
by the script, then install it with:

```bash
./setup-bluefin-mep.sh --bricscad-deb /path/to/downloaded/BricsCAD.deb
```

The script installs the `.deb` with `apt`, exports BricsCAD into Bluefin's app
launcher, and checks X11 and OpenGL from inside the container. It is safe to
rerun for interrupted installs or a newer BricsCAD package.

Launch Dropbox from the application menu after installation, sign in, choose
the folders to sync, and enable **Start Dropbox on system startup** in its
preferences. This account-linking step cannot be automated by the script.

The script detects a proprietary NVIDIA driver through `nvidia-smi` when it
first creates the box. Use `--nvidia` to force this or `--no-nvidia` to disable
it. These flags cannot change an already-created container; remove and recreate
the box manually if its GPU integration was initially configured incorrectly.

## Important caveats

- The Dropbox Flatpak is community-maintained and not officially supported by
  Dropbox, although it packages Dropbox's official daemon. Its app ID is
  `com.dropbox.Client`.
- BricsCAD V26 supports Ubuntu 22.04 and newer supported Ubuntu releases, but
  24.04 LTS is used here as the conservative target.
- Distrobox passes the host's Xwayland display through automatically. Some
  BricsCAD, GPU, and Wayland combinations can still have 3D stability issues.
  The script validates connectivity but cannot guarantee vendor support for a
  particular GPU or host display session.
- Bricsys states that Linux 3D hardware acceleration is unsupported on Intel
  GPUs and dual-graphics laptops. Check this before choosing laptop hardware.

## Sources

- [Bluefin introduction](https://docs.projectbluefin.io/introduction)
- [Bluefin package and container guidance](https://docs.projectbluefin.io/FAQ/)
- [Distrobox](https://distrobox.it/)
- [Distrobox application export](https://distrobox.it/usage/distrobox-export/)
- [BricsCAD system requirements](https://help.bricsys.com/en-us/document/bricscad/installation-and-licensing/bricscad-system-requirements?version=V26)
- [BricsCAD download instructions](https://help.bricsys.com/en-us/document/bricscad/installation-and-licensing/installing-bricscad/downloading-bricscad?version=V26)
- [LibreOffice Flatpak](https://www.libreoffice.org/download/flatpak/)
- [Dropbox Linux requirements](https://help.dropbox.com/installs/system-requirements)
- [Dropbox on Flathub](https://flathub.org/apps/com.dropbox.Client)
