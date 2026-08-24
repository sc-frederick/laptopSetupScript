# Linux Mint Cinnamon laptop setup

This repository prepares an x86-64 Linux Mint Cinnamon laptop for development,
CAD, communication, and day-to-day desktop use. The script is safe to rerun:
APT and Flatpak leave current packages installed, `mise` reconciles its global
tool configuration, and Beeper is downloaded only when its release URL changes.

## What it installs

### Developer tools

[`mise`](https://mise.jdx.dev/) manages the user-level development tools:

- Gleam with Erlang/Rebar3, Go, Rust, and the current Node.js LTS release
- TypeScript (`tsc`)
- OpenCode 1 (`opencode`)
- The OpenCode 2 beta (`opencode2`), installed alongside OpenCode 1
- OpenAI Codex CLI (`codex`)
- Neovim from ButterRepo with the official LazyVim starter configuration
- LazyVim helpers: tree-sitter CLI, lazygit, fzf, ripgrep, and fd
- Starship with its official Nerd Font Symbols preset

The script adds mise's shim directory and `mise activate bash` to `~/.bashrc`.
The shims keep globally installed commands available even when prompt-driven
activation has not refreshed `PATH`. Project-specific `mise.toml` files can
override these global versions later.

The first LazyVim installation backs up an existing Neovim configuration and
state to timestamped `.bak.YYYYMMDDHHMMSS` paths. Reruns detect LazyVim and
leave subsequent editor customizations untouched. On first launch, Neovim
downloads the configured plugins; run `:LazyHealth` afterward.

### Fonts and prompt

- JetBrains Mono Nerd Font and Cascadia Code Nerd Font from Nerd Fonts
- JetBrains Mono Nerd Font Mono as Cinnamon's default monospace font
- JetBrains Mono Nerd Font Mono as Ghostty's configured font
- Starship's clean Nerd Font Symbols preset for Bash

Font archives are installed under `~/.local/share/fonts/NerdFonts`. Existing
Starship configuration is preserved; the preset is generated only when
`~/.config/starship.toml` does not already exist.

### Desktop software

- Helium browser and Neovim from ButterRepo
- Ghostty from the `mkasberg/ghostty-ubuntu` PPA built for Ubuntu 24.04/26.04
- Cloudflare WARP from Cloudflare's official APT repository
- Dropbox's native package and daemon-control CLI from Dropbox's APT repository
- Bitwarden from Flathub; Linux Mint's preinstalled LibreOffice is retained
- Beeper's official x86-64 AppImage, installed below `~/.local/opt`
- BricsCAD from a separately downloaded vendor `.deb`
- A Cinnamon launcher that opens Zoom's web client in Helium app mode

## Run it

Download the current 64-bit Ubuntu BricsCAD `.deb` from
[Bricsys](https://www.bricsys.com/bricscad-download) into `~/Downloads`, then
run:

```bash
chmod +x setup-linux-mint.sh
./setup-linux-mint.sh
```

The script finds the newest file matching `*BricsCAD*.deb` in the configured
XDG downloads directory. To select a package explicitly:

```bash
./setup-linux-mint.sh --bricscad-deb /path/to/BricsCAD.deb
```

Other options are available through `./setup-linux-mint.sh --help`. Run the
script as your normal desktop user; it requests `sudo` only for system package
and repository changes.

Open a new terminal after setup so the `mise` activation takes effect. The
following commands should then be available:

```bash
gleam --version
go version
rustc --version
tsc --version
nvim --version
ghostty --version
starship --version
lazygit --version
tree-sitter --version
opencode --version
opencode2 --version
codex --version
```

## Manual sign-in

The script installs software but does not automate account or VPN enrollment:

- Run `dropbox start -i` to download the signed Dropbox daemon, follow the
  printed account-link URL, then use commands such as `dropbox status`,
  `dropbox filestatus`, and `dropbox exclude`. Launch Bitwarden and sign in.
- Launch Cloudflare WARP and complete its first-run registration. For CLI-only
  setup, use `warp-cli registration new` followed by `warp-cli connect`.
- Launch Beeper and connect the desired messaging accounts.
- Launch BricsCAD and complete its vendor licensing flow.
- Use **Zoom Web** from the Cinnamon menu. It deliberately avoids Zoom's Linux
  desktop package; install that package separately if browser meetings prove
  insufficient.

## Caveats

- Cloudflare officially lists supported Ubuntu releases rather than Linux Mint.
  Mint releases based on a supported Ubuntu LTS generally use the same package,
  but this is not an explicit Cloudflare support guarantee.
- ButterRepo is an unofficial community repository whose packages are built and
  tested on Debian 13. Helium and Neovim target the same glibc 2.38/t64
  generation as Linux Mint 22, but Mint is not an upstream-tested target.
- Ghostty's PPA is also community-maintained, but publishes separate packages
  for the Ubuntu base used by Mint. An APT preference excludes only ButterRepo's
  Debian-targeted Ghostty package so it cannot outrank the compatible PPA build.
- Bitwarden's Flathub package is community-maintained. Flatpak is used here for
  straightforward desktop updates and isolation.
- The native `dropbox` CLI controls the local sync daemon and synced filesystem.
  An extension that needs complete server-side traversal or operations outside
  the local sync model should use Dropbox's HTTP API/SDK with OAuth as well.
- OpenCode 2 is beta software. Its npm package requires a reviewed post-install
  script to select the native `opencode2` binary; the `mise` declaration
  explicitly permits that package's install script only.
- Beeper requires glibc 2.32 or newer. Current Linux Mint releases satisfy this
  requirement.
- The Zoom web client may omit features available in Zoom's native client.

## Sources

- [mise installation](https://mise.jdx.dev/installing-mise.html)
- [mise npm backend](https://mise.jdx.dev/dev-tools/backends/npm.html)
- [OpenCode 1 installation](https://opencode.ai/docs/)
- [OpenCode 2 installation](https://opencode.ai/v2/docs/)
- [OpenAI Codex CLI](https://developers.openai.com/codex/cli)
- [LazyVim installation](https://www.lazyvim.org/installation)
- [Nerd Fonts releases](https://github.com/ryanoasis/nerd-fonts/releases)
- [Starship Nerd Font Symbols preset](https://starship.rs/presets/nerd-font)
- [ButterRepo](https://codeberg.org/justaguylinux/butterrepo)
- [Ghostty Ubuntu PPA](https://launchpad.net/~mkasberg/+archive/ubuntu/ghostty-ubuntu)
- [Cloudflare WARP for Linux](https://developers.cloudflare.com/warp-client/get-started/linux/)
- [Beeper downloads](https://www.beeper.com/download)
- [BricsCAD downloads](https://help.bricsys.com/en-us/document/bricscad/installation-and-licensing/installing-bricscad/downloading-bricscad?version=V26)
- [Dropbox Linux CLI](https://help.dropbox.com/installs/linux-commands)
- [Bitwarden on Flathub](https://flathub.org/apps/com.bitwarden.desktop)
