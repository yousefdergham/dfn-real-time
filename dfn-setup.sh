#!/usr/bin/env bash
# DeepFilterNet end-to-end installer + PipeWire wiring (virtual sink + source)
# FIXED VERSION - Addresses multiple critical issues in the original script
#
# Usage:
#   chmod +x dfn-setup-fixed.sh
#   ./dfn-setup-fixed.sh
#
set -euo pipefail
LOG="/tmp/dfn-setup-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

echo "== DeepFilterNet Setup (Fixed) =="
echo "Log: $LOG"

#-------------------------------
# Detect package manager / distro
#-------------------------------
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
    return
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
    return
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
    return
  elif command -v zypper >/dev/null 2>&1; then
    echo zypper
    return
  else
    echo "unknown"
    return
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
apt) PW_PKGS=(pipewire pipewire-pulse wireplumber pavucontrol) ;;
dnf) PW_PKGS=(pipewire pipewire-pulseaudio wireplumber pavucontrol) ;;
pacman) PW_PKGS=(pipewire pipewire-pulse wireplumber pavucontrol) ;;
zypper) PW_PKGS=(pipewire pipewire-pulse wireplumber pavucontrol) ;;
*) PW_PKGS=(pipewire) ;;
esac

# LADSPA tools (analyseplugin) + build tools
case "$PM" in
apt) LADSPA_PKGS=(ladspa-sdk) BUILD_PKGS=(build-essential pkg-config) ;;
dnf) LADSPA_PKGS=(ladspa) BUILD_PKGS=(gcc make pkgconf) ;;
pacman) LADSPA_PKGS=(ladspa) BUILD_PKGS=(base-devel pkgconf) ;;
zypper) LADSPA_PKGS=(ladspa) BUILD_PKGS=(gcc make pkgconf) ;;
*) LADSPA_PKGS=() BUILD_PKGS=() ;;
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
# FIX 1: Check if we can write to system directories with sudo
CAN_SUDO=false
if command -v sudo >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null || sudo true; then
    CAN_SUDO=true
  fi
fi

if [ "$CAN_SUDO" = true ]; then
  echo "Installing plugin system-wide with sudo..."
  sudo mkdir -p /usr/lib/ladspa
  sudo cp -f "$PLUGIN_SRC" /usr/lib/ladspa/libdeep_filter_ladspa.so
  PLUGIN_PATH="/usr/lib/ladspa/libdeep_filter_ladspa.so"
else
  echo "Installing plugin for current user (no sudo available)..."
  mkdir -p "$HOME/.ladspa"
  cp -f "$PLUGIN_SRC" "$HOME/.ladspa/libdeep_filter_ladspa.so"
  PLUGIN_PATH="$HOME/.ladspa/libdeep_filter_ladspa.so"

  # FIX 2: Set LADSPA_PATH environment variable for user installation
  export LADSPA_PATH="$HOME/.ladspa:/usr/lib/ladspa:/usr/local/lib/ladspa"
  echo "export LADSPA_PATH=\"$LADSPA_PATH\"" >>"$HOME/.bashrc"
fi
echo "Plugin installed to: $PLUGIN_PATH"

#-------------------------------
# FIX 3: Properly analyze LADSPA plugin
#-------------------------------
if ! command -v analyseplugin >/dev/null 2>&1; then
  echo "WARNING: 'analyseplugin' not found. Using def systemctl --user restart pipewire pipewire-pulse wireplumberault values..."
  # Default values based on DeepFilterNet documentation
  LABEL_MONO="deep_filter_mono"
  LABEL_STEREO="deep_filter_stereo"
else
  echo "Analyzing plugin to determine available labels and ports..."
  ANALYSE_OUT="$(analyseplugin "$PLUGIN_PATH" 2>&1 || true)"

  # FIX 4: Check if plugin provides both mono and stereo versions
  if echo "$ANALYSE_OUT" | grep -q "deep_filter_stereo"; then
    LABEL_STEREO="deep_filter_stereo"
    echo "Found stereo label: $LABEL_STEREO"
  else
    LABEL_STEREO=""
    echo "No stereo version found"
  fi

  if echo "$ANALYSE_OUT" | grep -q "deep_filter_mono"; then
    LABEL_MONO="deep_filter_mono"
    echo "Found mono label: $LABEL_MONO"
  else
    LABEL_MONO=""
    echo "No mono version found"
  fi
fi

#-------------------------------
# Write PipeWire configs (filter-chain modules)
#-------------------------------
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"

# FIX 5: Create proper configuration based on available plugin versions
if [ -n "$LABEL_MONO" ]; then
  # Virtual Source (for microphone) - MONO version
  SOURCE_CONF="$CONF_DIR/deepfilter-source.conf"
  cat >"$SOURCE_CONF" <<EOF
# Auto-generated by dfn-setup-fixed.sh
# DeepFilter Noise Canceling Source (Microphone)
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "DeepFilter Noise Canceling Source"
      node.name        = "deepfilter-source"
      media.name       = "DeepFilter Noise Canceling Source"
      
      filter.graph = {
        nodes = [
          {
            type   = ladspa
            name   = dfn
            plugin = "$PLUGIN_PATH"
            label  = "$LABEL_MONO"
            control = {
              "Attenuation Limit (dB)" = 30
            }
          }
        ]
      }
      
      # FIX 6: Proper audio configuration for mono
      audio.rate     = 48000
      audio.channels = 1
      audio.position = [ MONO ]
      
      capture.props = {
        node.name    = "deepfilter.source.capture"
        node.passive = true
      }
      
      playback.props = {
        node.name    = "deepfilter.source.playback"
        media.class  = "Audio/Source"
      }
    }
  }
]
EOF
  echo "Created mono source config: $SOURCE_CONF"
fi

if [ -n "$LABEL_STEREO" ]; then
  # Virtual Sink (for playback / YouTube / system audio) - STEREO version
  SINK_CONF="$CONF_DIR/deepfilter-sink.conf"
  cat >"$SINK_CONF" <<EOF
# Auto-generated by dfn-setup-fixed.sh
# DeepFilter Sink for System Audio
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "DeepFilter Sink"
      node.name        = "deepfilter-sink"
      media.name       = "DeepFilter Sink"
      
      filter.graph = {
        nodes = [
          {
            type   = ladspa
            name   = dfn
            plugin = "$PLUGIN_PATH"
            label  = "$LABEL_STEREO"
            control = {
              "Attenuation Limit (dB)" = 100
            }
          }
        ]
      }
      
      # FIX 7: Proper audio configuration for stereo
      audio.rate     = 48000
      audio.channels = 2
      audio.position = [ FL FR ]
      
      capture.props = {
        node.name    = "deepfilter.sink.capture"
        media.class  = "Audio/Sink"
      }
      
      playback.props = {
        node.name    = "deepfilter.sink.playback"
        node.passive = true
      }
    }
  }
]
EOF
  echo "Created stereo sink config: $SINK_CONF"
elif [ -n "$LABEL_MONO" ]; then
  # FIX 8: If only mono is available, create stereo sink using two mono instances
  SINK_CONF="$CONF_DIR/deepfilter-sink.conf"
  cat >"$SINK_CONF" <<EOF
# Auto-generated by dfn-setup-fixed.sh
# DeepFilter Sink (using dual mono for stereo)
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "DeepFilter Sink"
      node.name        = "deepfilter-sink"
      media.name       = "DeepFilter Sink"
      
      filter.graph = {
        nodes = [
          {
            type   = ladspa
            name   = dfn_left
            plugin = "$PLUGIN_PATH"
            label  = "$LABEL_MONO"
            control = {
              "Attenuation Limit (dB)" = 100
            }
          }
          {
            type   = ladspa
            name   = dfn_right
            plugin = "$PLUGIN_PATH"
            label  = "$LABEL_MONO"
            control = {
              "Attenuation Limit (dB)" = 100
            }
          }
        ]
        links = [
          { output = "capture:FL"      input = "dfn_left:In" }
          { output = "dfn_left:Out"    input = "playback:FL" }
          { output = "capture:FR"      input = "dfn_right:In" }
          { output = "dfn_right:Out"   input = "playback:FR" }
        ]
      }
      
      audio.rate     = 48000
      audio.channels = 2
      audio.position = [ FL FR ]
      
      capture.props = {
        node.name    = "deepfilter.sink.capture"
        media.class  = "Audio/Sink"
      }
      
      playback.props = {
        node.name    = "deepfilter.sink.playback"
        node.passive = true
      }
    }
  }
]
EOF
  echo "Created stereo sink config using dual mono: $SINK_CONF"
fi

#-------------------------------
# FIX 9: Set up environment for logging control
#-------------------------------
ENV_FILE="$CONF_DIR/deepfilter.env"
cat >"$ENV_FILE" <<EOF
# DeepFilterNet environment configuration
export RUST_LOG=ERROR
export LADSPA_PATH="$HOME/.ladspa:/usr/lib/ladspa:/usr/local/lib/ladspa"
EOF
echo "Created environment file: $ENV_FILE"

#-------------------------------
# FIX 10: Create systemd user service for automatic startup
#-------------------------------
SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

if [ -n "$LABEL_MONO" ]; then
  cat >"$SYSTEMD_DIR/deepfilter-source.service" <<EOF
[Unit]
Description=DeepFilterNet Source
After=pipewire.service
Requires=pipewire.service

[Service]
Type=simple
Environment="RUST_LOG=ERROR"
Environment="LADSPA_PATH=$HOME/.ladspa:/usr/lib/ladspa:/usr/local/lib/ladspa"
ExecStart=/usr/bin/pipewire -c $SOURCE_CONF
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
fi

if [ -f "$SINK_CONF" ]; then
  cat >"$SYSTEMD_DIR/deepfilter-sink.service" <<EOF
[Unit]
Description=DeepFilterNet Sink
After=pipewire.service
Requires=pipewire.service

[Service]
Type=simple
Environment="RUST_LOG=ERROR"
Environment="LADSPA_PATH=$HOME/.ladspa:/usr/lib/ladspa:/usr/local/lib/ladspa"
ExecStart=/usr/bin/pipewire -c $SINK_CONF
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
fi

#-------------------------------
# Restart PipeWire & verify
#-------------------------------
echo "Restarting PipeWire services..."

# FIX 11: Proper PipeWire restart sequence
systemctl --user daemon-reload
systemctl --user restart pipewire.socket
systemctl --user restart pipewire.service
sleep 1
systemctl --user restart pipewire-pulse.socket
systemctl --user restart pipewire-pulse.service
sleep 1
systemctl --user restart wireplumber.service
sleep 3

#-------------------------------
# FIX 12: Verification with better error handling
#-------------------------------
echo "Verifying DeepFilterNet nodes..."
echo "----------------------------------------"

# Check if pw-cli is available
if command -v pw-cli >/dev/null 2>&1; then
  echo "Checking for DeepFilterNet nodes with pw-cli:"
  pw-cli ls Node | grep -i deepfilter || echo "No DeepFilterNet nodes found via pw-cli"
else
  echo "pw-cli not found, skipping node verification"
fi

# Check with pactl if available
if command -v pactl >/dev/null 2>&1; then
  echo ""
  echo "Checking sinks with pactl:"
  pactl list short sinks | grep -i deepfilter || echo "No DeepFilterNet sinks found"
  echo ""
  echo "Checking sources with pactl:"
  pactl list short sources | grep -i deepfilter || echo "No DeepFilterNet sources found"
fi

#-------------------------------
# Create status check script
#-------------------------------
STATUS_SCRIPT="$HOME/dfn-status.sh"
cat >"$STATUS_SCRIPT" <<'EOF'
#!/bin/bash
echo "=== DeepFilterNet Status Check ==="
echo ""
echo "LADSPA Plugin:"
if [ -f /usr/lib/ladspa/libdeep_filter_ladspa.so ]; then
  echo "  ✓ System-wide installation found"
elif [ -f "$HOME/.ladspa/libdeep_filter_ladspa.so" ]; then
  echo "  ✓ User installation found"
else
  echo "  ✗ Plugin not found"
fi

echo ""
echo "PipeWire Nodes:"
if command -v pw-cli >/dev/null 2>&1; then
  pw-cli ls Node | grep -i deepfilter || echo "  No nodes found"
fi

echo ""
echo "Audio Sinks/Sources (via pactl):"
if command -v pactl >/dev/null 2>&1; then
  echo "  Sinks:"
  pactl list short sinks | grep -i deepfilter || echo "    None"
  echo "  Sources:"
  pactl list short sources | grep -i deepfilter || echo "    None"
fi

echo ""
echo "Systemd Services:"
systemctl --user status deepfilter-source.service 2>/dev/null | head -3 || echo "  Source service not found"
systemctl --user status deepfilter-sink.service 2>/dev/null | head -3 || echo "  Sink service not found"

echo ""
echo "Environment:"
echo "  RUST_LOG=$RUST_LOG"
echo "  LADSPA_PATH=$LADSPA_PATH"
EOF
chmod +x "$STATUS_SCRIPT"

echo ""
echo "=== SETUP COMPLETE ==="
echo ""
echo "IMPORTANT NOTES:"
echo "1. The DeepFilterNet plugin has been installed and configured"
echo "2. Configuration files created in: $CONF_DIR"
echo "3. Status check script created: $STATUS_SCRIPT"
echo ""
echo "TO USE:"
echo "- For microphone: Select 'DeepFilter Noise Canceling Source' in your app"
echo "- For system audio: Route output to 'DeepFilter Sink'"
echo ""
echo "TO ENABLE AUTOMATIC STARTUP (optional):"
if [ -n "$LABEL_MONO" ]; then
  echo "  systemctl --user enable deepfilter-source.service"
fi
if [ -f "$SINK_CONF" ]; then
  echo "  systemctl --user enable deepfilter-sink.service"
fi
echo ""
echo "TO CHECK STATUS:"
echo "  ./dfn-status.sh"
echo ""
echo "TO VIEW LOGS:"
echo "  journalctl --user -u deepfilter-source -u deepfilter-sink -f"
echo ""
echo "If nodes don't appear, try:"
echo "1. Open pavucontrol and check Configuration/Input/Output tabs"
echo "2. Restart PipeWire: systemctl --user restart pipewire pipewire-pulse wireplumber"
echo "3. Check the log file: $LOG"

