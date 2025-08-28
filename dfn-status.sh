#!/usr/bin/env bash
# DeepFilterNet status script
# Shows:
#  - Installed plugin path and info (label, ports)
#  - PipeWire nodes for DeepFilter sink/source
#  - PulseAudio-compat sinks/sources
#  - Basic diagnostics
set -euo pipefail

echo "== DeepFilterNet Status =="
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
ENV_FILE="$CONF_DIR/.deepfilter.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# Locate plugin if not in env
if [ -z "${PLUGIN_PATH:-}" ]; then
  for p in "/usr/lib/ladspa/libdeep_filter_ladspa.so" "$HOME/.ladspa/libdeep_filter_ladspa.so"; do
    if [ -f "$p" ]; then PLUGIN_PATH="$p"; break; fi
  done
fi

echo "Plugin path: ${PLUGIN_PATH:-<not found>}"
if [ -n "${PLUGIN_PATH:-}" ] && command -v analyseplugin >/dev/null 2>&1; then
  echo "---- LADSPA analyseplugin (first ~80 lines) ----"
  analyseplugin "$PLUGIN_PATH" | sed -n '1,80p'
  echo "-----------------------------------------------"
fi

echo
echo "PipeWire processes:"
systemctl --user status pipewire --no-pager -l | sed -n '1,12p' || true
systemctl --user status wireplumber --no-pager -l | sed -n '1,12p' || true
systemctl --user status pipewire-pulse --no-pager -l | sed -n '1,12p' || true

echo
echo "PipeWire nodes containing 'deepfilter':"
pw-cli s | grep -i "deepfilter" || echo "(none)"

echo
echo "Pulse (PipeWire) sinks:"
pactl list short sinks 2>/dev/null || echo "(pactl not available)"
echo
echo "Pulse (PipeWire) sources:"
pactl list short sources 2>/dev/null || echo "(pactl not available)"

echo
echo "Tip: In 'pavucontrol' → Playback/Input, route apps to 'DeepFilter (Sink)' and select 'DeepFilter (Source)' as mic."
