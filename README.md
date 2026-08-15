# dizziee.system-stats

CPU, GPU, memory, and storage monitor for the Omarchy bar. Displays real-time usage with per-compartment toggles and configurable poll intervals.

## Requirements

- Python 3
- `lspci` (for GPU name detection)
- `nvidia-smi` (for NVIDIA GPU stats)

## Installation

```sh
omarchy plugin add https://github.com/JJDizz1L/dizziee.system-stats.git --enable
```

### Then place it in your bar layout with 
`omarchy bar plugin add dizziee.system-stats [--section <left|center|right>]`</br>

Suggested placement: 
```
omarchy bar plugin add dizziee.system-stats --section right
```

You can validate the plugin at any time with:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/dizziee.system-stats
```

## Configuration
Configuration lives in `~/.config/omarchy/shell.json`.

| Key | Type | Default | Description |
|---|---|---|---|
| `compartments.cpu.enabled` | boolean | true | Show CPU usage in panel |
| `compartments.cpu.showInBar` | boolean | false | Show CPU stats on bar |
| `compartments.cpu.barDisplay` | string (`usage`, `temp`, `both`) | `usage` | CPU metric to show in bar |
| `compartments.cpu.pollIntervalSec` | integer | 30 | CPU poll interval |
| `compartments.gpu.enabled` | boolean | true | Show GPU usage in panel |
| `compartments.gpu.showInBar` | boolean | false | Show GPU stats on bar |
| `compartments.gpu.barDisplay` | string (`usage`, `temp`, `both`) | `usage` | GPU metric to show in bar |
| `compartments.gpu.pollIntervalSec` | integer | 30 | GPU poll interval |
| `compartments.memory.enabled` | boolean | true | Show memory usage in panel |
| `compartments.memory.showInBar` | boolean | false | Show memory stats on bar |
| `compartments.memory.pollIntervalSec` | integer | 30 | Memory poll interval |
| `compartments.storage.enabled` | boolean | true | Show storage usage in panel |
| `compartments.storage.showInBar` | boolean | false | Show storage stats on bar |
| `compartments.storage.pollIntervalSec` | integer | 30 | Storage poll interval |

## Preview

![preview](preview.png)

## Uninstall

```sh
omarchy plugin remove dizziee.system-stats
```

## License

MIT
