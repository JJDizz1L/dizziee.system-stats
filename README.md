# dizziee.system-stats

CPU, GPU, memory, and storage monitor for the Omarchy bar. Displays real-time usage with per-compartment toggles and configurable poll intervals.

## Requirements

- Python 3
- `lspci` (for GPU name detection)

## Installation

```sh
git clone https://github.com/JJDizz1L/dizziee.system-stats.git ~/.config/omarchy/plugins/dizziee.system-stats
```

Then enable **System Stats** in the Omarchy bar widget settings.

## Configuration

| Key | Type | Default | Description |
|---|---|---|---|
| `compartments.cpu.enabled` | boolean | true | Show CPU usage |
| `compartments.cpu.pollIntervalSec` | integer | 30 | CPU poll interval |
| `compartments.gpu.enabled` | boolean | false | Show GPU usage |
| `compartments.gpu.pollIntervalSec` | integer | 30 | GPU poll interval |
| `compartments.memory.enabled` | boolean | true | Show memory usage |
| `compartments.memory.pollIntervalSec` | integer | 30 | Memory poll interval |
| `compartments.storage.enabled` | boolean | true | Show storage usage |
| `compartments.storage.pollIntervalSec` | integer | 30 | Storage poll interval |

## License

MIT
