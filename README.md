# DeepFilterNet Real-Time Audio Processing

A complete setup for real-time audio noise suppression using DeepFilterNet with PipeWire integration. This project provides automated installation and configuration of DeepFilterNet as a LADSPA plugin, creating virtual audio devices for both input (microphone) and output (speakers) processing.

## 🎯 What is DeepFilterNet?

DeepFilterNet is an AI-powered audio noise suppression system that can:

- Remove background noise from microphone input in real-time
- Enhance audio quality for voice calls, recordings, and streaming
- Process audio through a neural network for superior noise reduction
- Work with any audio application through virtual audio devices

## 🚀 Features

- **Automated Setup**: One-command installation and configuration
- **Cross-Distribution Support**: Works on Ubuntu, Fedora, Arch Linux, and more
- **PipeWire Integration**: Creates virtual audio sink and source devices
- **Real-Time Processing**: Zero-latency audio processing
- **System-Wide Installation**: Installs for all users or current user only
- **Status Monitoring**: Built-in diagnostics and verification tools

## 📋 Prerequisites

- Linux distribution with PipeWire support
- Internet connection for downloading dependencies
- Sudo access (optional, will install for current user if not available)
- At least 2GB of free disk space

## 🛠️ Installation

### Quick Start

1. **Clone or download the project files:**

   ```bash
   git clone <repository-url>
   cd dfn-real-time
   ```

2. **Make the setup script executable:**

   ```bash
   chmod +x dfn-setup.sh
   ```

3. **Run the automated setup:**
   ```bash
   ./dfn-setup.sh
   ```

The setup script will:

- Detect your package manager and install dependencies
- Install Rust toolchain if needed
- Clone and build DeepFilterNet from source
- Install the LADSPA plugin system-wide or for current user
- Create PipeWire configuration for virtual audio devices
- Restart PipeWire services
- Verify the installation

### What Gets Installed

- **DeepFilterNet LADSPA Plugin**: The core audio processing engine
- **Virtual Audio Devices**:
  - `DeepFilter (Sink)`: For processing audio output (speakers, YouTube, etc.)
  - `DeepFilter (Source)`: For processing microphone input
- **Dependencies**: Rust, PipeWire, LADSPA tools, build tools

## 🎧 Usage

### After Installation

1. **Check Status**: Verify everything is working:

   ```bash
   ./dfn-status.sh
   ```

2. **Configure Audio Routing**:

   - Open your system's sound settings or `pavucontrol`
   - For **microphone noise suppression**: Select "DeepFilter (Source)" as your input device
   - For **speaker audio enhancement**: Route applications to "DeepFilter (Sink)"

3. **Test the Setup**:
   - Make a test call or recording using the DeepFilter devices
   - The AI will automatically process and enhance your audio

### Audio Routing Examples

**For Voice Calls (Discord, Zoom, etc.):**

- Set microphone to "DeepFilter (Source)"
- The AI will remove background noise in real-time

**For Audio Playback:**

- Route music players, YouTube, or system audio to "DeepFilter (Sink)"
- Audio will be processed through the neural network

**For Recording:**

- Use "DeepFilter (Source)" as input in recording software
- Get clean, noise-free recordings automatically

## 🔧 Configuration

### Manual Configuration

The setup creates configuration files in `~/.config/pipewire/pipewire.conf.d/`:

- `deepfilter-sink.conf`: Virtual audio sink configuration
- `deepfilter-source.conf`: Virtual audio source configuration
- `.deepfilter.env`: Environment variables for the plugin

### Customization

You can modify the audio processing by editing the PipeWire configuration files. The LADSPA plugin supports various parameters that can be adjusted for different use cases.

## 🐛 Troubleshooting

### Common Issues

**1. "Plugin not found" error:**

```bash
# Check if the plugin was installed correctly
./dfn-status.sh
# Re-run setup if needed
./dfn-setup.sh
```

**2. Virtual devices not appearing:**

```bash
# Restart PipeWire manually
systemctl --user restart pipewire pipewire-pulse wireplumber
# Check status
./dfn-status.sh
```

**3. Audio quality issues:**

- Ensure your system supports 48kHz audio
- Check that the correct devices are selected in your audio settings
- Verify PipeWire is running: `systemctl --user status pipewire`

**4. Build failures:**

- Ensure you have sufficient disk space (2GB+)
- Check internet connection for Rust toolchain download
- Install build dependencies manually if needed

### Diagnostic Commands

```bash
# Check plugin installation
ls -la /usr/lib/ladspa/libdeep_filter_ladspa.so
ls -la ~/.ladspa/libdeep_filter_ladspa.so

# Verify PipeWire nodes
pw-cli s | grep deepfilter

# Check PulseAudio compatibility
pactl list short sinks
pactl list short sources

# View detailed status
./dfn-status.sh
```

## 📁 Project Structure

```
dfn-real-time/
├── dfn-setup.sh      # Main installation script
├── dfn-status.sh     # Status and diagnostic script
└── README.md         # This file
```

## 🔄 Updates

To update DeepFilterNet to the latest version:

```bash
./dfn-setup.sh
```

The script will automatically fetch and build the latest version from the DeepFilterNet repository.

## 🗑️ Uninstallation

To remove DeepFilterNet:

1. **Remove the plugin:**

   ```bash
   sudo rm -f /usr/lib/ladspa/libdeep_filter_ladspa.so
   rm -f ~/.ladspa/libdeep_filter_ladspa.so
   ```

2. **Remove PipeWire configuration:**

   ```bash
   rm -f ~/.config/pipewire/pipewire.conf.d/deepfilter-*.conf
   rm -f ~/.config/pipewire/pipewire.conf.d/.deepfilter.env
   ```

3. **Restart PipeWire:**
   ```bash
   systemctl --user restart pipewire pipewire-pulse wireplumber
   ```

## 🤝 Contributing

This project is designed to make DeepFilterNet easily accessible for real-time audio processing. Contributions are welcome:

- Bug reports and feature requests
- Improvements to the setup scripts
- Additional distribution support
- Documentation enhancements

## 📄 License

This project is open source. The DeepFilterNet core is licensed under its respective license from the original repository.

## 🙏 Acknowledgments

- [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet) - The core AI audio processing engine
- [PipeWire](https://pipewire.org/) - Modern audio and video processing framework
- [LADSPA](https://www.ladspa.org/) - Linux Audio Developer's Simple Plugin API

## 📞 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Run `./dfn-status.sh` for diagnostics
3. Check the setup log at `/tmp/dfn-setup.log`
4. Ensure your system meets the prerequisites

---

**Note**: This setup provides real-time AI-powered audio enhancement. The quality of noise suppression depends on your hardware and the specific noise characteristics in your environment.
