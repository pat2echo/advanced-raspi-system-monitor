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

## First Time Setup
```
sudo apt update
sudo apt install hdparm
sudo apt install python3-pip i2c-tools -y

# work-in-progress
sudo apt full-upgrade -y
sudo rpi-update
sudo reboot
```

### OPTIONAL, ENABLE I2C FEATURE ON RASPBERRY PI (work-in-progress)
This will facilitate reading power values  
`sudo raspi-config`  
Go to: Interface Options > I2C > Enable  
Reboot: `sudo reboot`

Check bus addresses  
`ls /dev/i2c*`



### OTHER DEVICES, SKIP TO HERE
1. CLONE REPO
   ```
   git clone https://github.com/pat2echo/advanced-raspi-system-monitor.git
   cd advanced-raspi-system-monitor
```

2. INSTALL DEPENDENCIES
```
sudo apt update
sudo apt install python3-venv -y
```

3. CREATE VIRTUAL PYTHON ENVIRONMENT
```
python3 -m venv ~/venv
source ~/venv/bin/activate
pip install pi-ina219

# OPTIONAL: VERIFY INSTALLATION
pip list
```

4. MAKE SCRIPT EXECUTABLE
```
chmod +x features_reader.sh
```

6. GO TO RUN LOGGER IN SUBSEQUENT USAGE SECTION
7. 


## Subsequent Usage
1. ACCESS VIRTUAL ENV
```
cd advanced-raspi-system-monitor/
source ~/venv/bin/activate
```

2. RUN LOGGER
Run in foreground
```
sudo ./features_reader.sh
```
OR

Run in background, but use sudo privileges otherwise disk read/write speed may fail due to insufficient privilege
```
nohup ./features_reader.sh &

# monitor progress aas data is written to csv file
tail -f ic_advanced_metrics_log.csv
```
