# Helmsman

A native macOS GUI for managing [Supervisor](http://supervisord.org) processes. Built with SwiftUI and Swift Concurrency.

![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![Xcode 26](https://img.shields.io/badge/Xcode-26.5-lightgrey)

## Features

- **Multiple connection methods**: Local, SSH, Docker, XML-RPC, Auto-detect
- **Service management**: Start, stop, restart services with real-time status updates
- **Auto-refresh**: Configurable polling interval with automatic status refresh
- **Safe Mode**: Optional confirmation dialogs before destructive actions
- **Error handling**: Retry logic with exponential backoff and auto-reconnect
- **Search & filter**: Quickly find services by name or group
- **Context menus**: Right-click for quick actions on any service
- **Config file support**: Specify custom `supervisord.conf` paths via `-c` flag

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 26.5 or later
- Swift 6

## Building

```bash
git clone https://github.com/your-username/Helmsman.git
cd Helmsman
open Helmsman.xcodeproj
# Build and run (Cmd+R)
```

## Usage

1. Launch Helmsman
2. Click **+** to create a new connection
3. Choose your connection method:
   - **Local**: Runs `supervisorctl` directly on your Mac
   - **SSH**: Connects to a remote server via SSH
   - **Docker**: Runs `supervisorctl` inside a Docker container
   - **XML-RPC**: Connects to Supervisor's XML-RPC API
   - **Auto**: Tries XML-RPC first, falls back to SSH
4. Click **Connect** to load your services
5. Use the play/stop/restart buttons to manage services

## Connection Settings

| Setting | Description |
|---------|-------------|
| **supervisorctl Path** | Path to `supervisorctl` binary. Auto-detected from common locations. |
| **Config Path** | Optional path to `supervisord.conf` (passed via `-c` flag) |
| **Polling Interval** | How often to refresh service status (default: 5 seconds) |
| **Safe Mode** | Show confirmation dialogs before start/stop/restart actions |
| **Auto-reconnect** | Automatically reconnect on connection loss |

## Architecture

```
Helmsman/
├── Models/              # Data models (Connection, Service, ProviderConfiguration)
├── Protocols/           # ServiceManagerProvider protocol
├── Managers/            # ConnectionManager, ServiceManager, PollingEngine
├── Providers/
│   └── Supervisor/      # Provider implementations (Local, SSH, Docker, XML-RPC)
├── ViewModels/          # ConnectionWindowViewModel, MainWindowViewModel
├── Views/               # SwiftUI views (MainWindow, ServiceListView, etc.)
└── Utilities/           # KeychainManager, SupervisorctlFinder, Color+Hex
```

### Provider Pattern

All connection methods implement the `ServiceManagerProvider` protocol:

```swift
protocol ServiceManagerProvider {
    func getAllProcesses() async throws -> [SupervisorProcess]
    func startProcess(_ name: String) async throws
    func stopProcess(_ name: String) async throws
    func restartProcess(_ name: String) async throws
}
```

The UI is completely provider-agnostic — switching between Local, SSH, Docker, or XML-RPC requires zero UI changes.

## Security

- Passwords are stored in the macOS Keychain (not UserDefaults or files)
- SSH connections use the system SSH binary (`/usr/bin/ssh`)
- App Sandbox is **disabled** (required for `Process()` execution of `supervisorctl`)

## Known Limitations

- **App Sandbox**: This app cannot be distributed via the Mac App Store because it requires spawning external processes (`supervisorctl`, `ssh`, `docker`), which is incompatible with App Sandbox. Distribution is limited to direct download or Homebrew.
- **macOS 15+ only**: Uses modern Swift features (Observation framework, Swift Concurrency) that require macOS 15 Sequoia.
- **SSH host key verification**: Currently disabled (`StrictHostKeyChecking=no`) for simplicity. This may be flagged during security review.

## License

MIT
