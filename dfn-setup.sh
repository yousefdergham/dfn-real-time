#!/usr/bin/env bash
# DeepFilterNet end-to-end installer + PipeWire wiring (virtual sink + source)
# - Builds the DeepFilterNet LADSPA plugin from source (Rust)
# - Installs it system-wide (/usr/lib/ladspa) if sudo works; else to ~/.ladspa
# - Creates PipeWire filter-chain nodes: "DeepFilter (Sink)" & "DeepFilter (Source)"
# - Restarts PipeWire and shows verification
#
# Usage:
#   chmod +x dfn-setup.sh
#   ./dfn-setup.sh
#
set -euo pipefail
LOG="/tmp/dfn-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "== DeepFilterNet Setup =="
echo "Log: $LOG"

#-------------------------------
# Detect package manager / distro
#-------------------------------
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then echo apt; return
  elif command -v dnf >/dev/null 2>&1; then echo dnf; return
  elif command -v pacman >/dev/null 2>&1; then echo pacman; return
  elif command -v zypper >/dev/null 2>&1; then echo zypper; return
  else echo "unknown"; return
  fi
}
PM="$(detect_pm)"
echo "Detected package manager: $PM"

#-------------------------------
# Install packages
#-------------------------------
install_pkgs() {
  local pkgs=("$@")
  case "$PM" in
    apt)
      sudo apt-get update -y
      DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
      ;;
    dnf)
      sudo dnf install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm --needed "${pkgs[@]}"
      ;;
    zypper)
      sudo zypper --non-interactive install -y "${pkgs[@]}"
      ;;
    *)
      echo "WARN: Unsupported package manager. Please install deps manually: ${pkgs[*]}"
      ;;
  esac
}

# Common tools
COMMON_PKGS=(git curl wget tar)

# PipeWire + GUI mixer
case "$PM" in
  apt)     PW_PKGS=(pipewire pipewire-pulse wireplumber pavucontrol) ;;
  dnf)     PW_PKGS=(pipewire pipewire-pulseaudio wireplumber pavucontrol) ;;
  pacman)  PW_PKGS=(pipewire pipewire-pulse wireplumber pavucontrol) ;;
  zypper)  PW_PKGS=(pipewire pipewire-pulse wireplumber pavucontrol) ;;
  *)       PW_PKGS=(pipewire) ;;
esac

# LADSPA tools (analyseplugin) + build tools
case "$PM" in
  apt)     LADSPA_PKGS=(ladspa-sdk)        BUILD_PKGS=(build-essential pkg-config) ;;
  dnf)     LADSPA_PKGS=(ladspa)            BUILD_PKGS=(gcc make pkgconf) ;;
  pacman)  LADSPA_PKGS=(ladspa)            BUILD_PKGS=(base-devel pkgconf) ;;
  zypper)  LADSPA_PKGS=(ladspa)            BUILD_PKGS=(gcc make pkgconf) ;;
  *)       LADSPA_PKGS=()                  BUILD_PKGS=() ;;
esac

echo "Installing prerequisites..."
install_pkgs "${COMMON_PKGS[@]}" "${PW_PKGS[@]}" "${LADSPA_PKGS[@]}" "${BUILD_PKGS[@]}"

#-------------------------------
# Ensure Rust (cargo)
#-------------------------------
if ! command -v cargo >/dev/null 2>&1; then
  echo "Installing Rust toolchain (rustup + cargo) for current user..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "Rust toolchain already present."
fi
export PATH="$HOME/.cargo/bin:$PATH"

#-------------------------------
# Clone / update DeepFilterNet
#-------------------------------
REPO_DIR="${HOME}/.cache/DeepFilterNet"
if [ -d "$REPO_DIR/.git" ]; then
  echo "Updating DeepFilterNet repo in $REPO_DIR ..."
  git -C "$REPO_DIR" fetch --depth=1 origin main || true
  git -C "$REPO_DIR" reset --hard origin/main || true
else
  echo "Cloning DeepFilterNet repo to $REPO_DIR ..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth=1 https://github.com/Rikorose/DeepFilterNet "$REPO_DIR"
fi

#-------------------------------
# Build the LADSPA plugin
#-------------------------------
echo "Building LADSPA plugin (deep-filter-ladspa)..."
cd "$REPO_DIR"
cargo build --release -p deep-filter-ladspa

PLUGIN_SRC="$REPO_DIR/target/release/libdeep_filter_ladspa.so"
if [ ! -f "$PLUGIN_SRC" ]; then
  echo "ERROR: Build finished but plugin not found at $PLUGIN_SRC"
  exit 1
fi
echo "Built plugin: $PLUGIN_SRC"

#-------------------------------
# Install plugin (.so)
#-------------------------------
PLUGIN_DST_SYS="/usr/lib/ladspa/libdeep_filter_ladspa.so"
PLUGIN_DST_USER="$HOME/.ladspa/libdeep_filter_ladspa.so"

install_plugin_system() {
  sudo mkdir -p /usr/lib/ladspa
  sudo cp -f "$PLUGIN_SRC" "$PLUGIN_DST_SYS"
  echo "$PLUGIN_DST_SYS"
}
install_plugin_user() {
  mkdir -p "$HOME/.ladspa"
  cp -f "$PLUGIN_SRC" "$PLUGIN_DST_USER"
  echo "$PLUGIN_DST_USER"
}

if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  echo "Installing plugin system-wide with sudo..."
  PLUGIN_PATH="$(install_plugin_system)"
else
  echo "Installing plugin for current user (no passwordless sudo)..."
  PLUGIN_PATH="$(install_plugin_user)"
fi
echo "Plugin installed to: $PLUGIN_PATH"

#-------------------------------
# Analyse LADSPA plugin to find label and ports
#-------------------------------
if ! command -v analyseplugin >/dev/null 2>&1; then
  echo "ERROR: 'analyseplugin' not found. Install ladspa-sdk/ladspa tools and re-run."
  exit 1
fi
ANALYSE_OUT="$(analyseplugin "$PLUGIN_PATH")"
LABEL="$(echo "$ANALYSE_OUT" | awk -F': *' '/^[[:space:]]*Label:/{print $2; exit}')"
IN_PORT="$(echo "$ANALYSE_OUT"  | awk '/Ports:/{f=1;next}/Properties:/{f=0}f && /Input, audio/{print $1; exit}')"
OUT_PORT="$(echo "$ANALYSE_OUT" | awk '/Ports:/{f=1;next}/Properties:/{f=0}f && /Output, audio/{print $1; exit}')"
LABEL="${LABEL:-deep_filter_stereo}"
IN_PORT="${IN_PORT:-In}"
OUT_PORT="${OUT_PORT:-Out}"
echo "Detected Label: $LABEL"
echo "Using ports -> In: '$IN_PORT'  Out: '$OUT_PORT'"

#-------------------------------
# Write PipeWire configs (filter-chain modules)
#-------------------------------
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"

ENV_FILE="$CONF_DIR/.deepfilter.env"
cat > "$ENV_FILE" <<EOF
PLUGIN_PATH="$PLUGIN_PATH"
LABEL="$LABEL"
IN_PORT="$IN_PORT"
OUT_PORT="$OUT_PORT"
EOF
echo "Wrote $ENV_FILE"

# Virtual Sink (for playback / YouTube / system audio)
SINK_CONF="$CONF_DIR/deepfilter-sink.conf"
cat > "$SINK_CONF" <<EOF
# Auto-generated by dfn-setup.sh
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "DeepFilter (Sink)"
      node.name        = "deepfilter.sink"
      media.class      = "Audio/Sink"

      audio.rate       = 48000
      audio.channels   = 2
      audio.position   = [ FL FR ]

      filter.graph = {
        nodes = [
          {
            type   = ladspa
            name   = dfn
            plugin = "$PLUGIN_PATH"
            label  = "$LABEL"
          }
        ]
        links = [
          { output = "input"             input  = "dfn:$IN_PORT"  }
          { output = "dfn:$OUT_PORT"     input  = "output"        }
        ]
      }

      capture.props  = { node.name = "deepfilter.sink.capture"  }
      playback.props = { node.name = "deepfilter.sink.playback" }
    }
  }
]
EOF

# Virtual Source (for microphone)
SOURCE_CONF="$CONF_DIR/deepfilter-source.conf"
cat > "$SOURCE_CONF" <<EOF
# Auto-generated by dfn-setup.sh
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "DeepFilter (Source)"
      node.name        = "deepfilter.source"
      media.class      = "Audio/Source"

      audio.rate       = 48000
      audio.channels   = 2
      audio.position   = [ FL FR ]

      filter.graph = {
        nodes = [
          {
            type   = ladspa
            name   = dfn
            plugin = "$PLUGIN_PATH"
            label  = "$LABEL"
          }
        ]
        links = [
          { output = "input"             input  = "dfn:$IN_PORT"  }
          { output = "dfn:$OUT_PORT"     input  = "output"        }
        ]
      }

      capture.props  = { node.name = "deepfilter.source.capture"  }
      playback.props = { node.name = "deepfilter.source.playback" }
    }
  }
]
EOF

echo "Wrote PipeWire configs:"
echo "  - $SINK_CONF"
echo "  - $SOURCE_CONF"

#-------------------------------
# Restart PipeWire & verify
#-------------------------------
echo "Restarting PipeWire for current user..."
systemctl --user daemon-reload || true
systemctl --user restart pipewire pipewire-pulse wireplumber || true
sleep 2

echo "Verifying nodes exist:"
pw-cli s | grep -E "deepfilter\\.(sink|source)" -n || true

echo
echo "=== SUCCESS ==="
echo "Devices should now appear as 'DeepFilter (Sink)' and 'DeepFilter (Source)' in your sound settings."
echo " - Route YouTube or any app OUTPUT to DeepFilter (Sink)."
echo " - Select DeepFilter (Source) as your microphone in apps."
echo
echo "If you don't see them, open 'pavucontrol' and check the Playback/Input tabs."
echo "Run './dfn-status.sh' for a detailed status."
