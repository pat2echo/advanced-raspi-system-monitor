# Advanced Raspberry Pi System Monitor

A comprehensive bash script for detailed system metrics logging on Raspberry Pi (and Linux systems).  
This tool collects enhanced metrics including CPU/GPU stats, disk I/O performance, network statistics, power consumption, GPIO state, and extensive memory information, and logs them into a CSV file for easy analysis.

---

## Features

- CPU temperature, clock speeds (ARM and GPU)
- Memory usage details and extensive `/proc/meminfo` fields
- Primary disk device detection with I/O stats and latency calculation
- Periodic disk read/write speeds and IOPS
- Disk timing tests via `hdparm` (if installed)
- Multi-network interface monitoring (up to 3 interfaces)
- Network statistics including bytes, packets, errors, and dropped counts
- Power measurement via INA219 sensor (using external Python script)
- GPIO pin state reading
- CPU load, process count, running services, listening ports, and active network connections
- Logs output in a CSV file (`ic_advanced_metrics_log.csv`) for easy parsing and visualization

---

## Requirements

- Raspberry Pi or compatible Linux system
- `bash` shell
- `hdparm` installed (optional, for disk timing tests)
- Python3 script (`read_power.py`) for power readings (optional)
- Access to `/sys/class/gpio` for GPIO monitoring

---

## Usage

1. Clone the repository:
   ```bash
   git clone https://github.com/pat2echo/advanced-raspi-system-monitor.git
   cd advanced-raspi-system-monitor
