#!/bin/bash
LOGFILE="ic_advanced_metrics_log.csv"
GPIO_PIN=17
INTERVAL=10

# Function to setup GPIO with error handling
setup_gpio() {
    if [ ! -e /sys/class/gpio/gpio$GPIO_PIN ]; then
        echo "Exporting GPIO $GPIO_PIN..."
        if echo "$GPIO_PIN" > /sys/class/gpio/export 2>/dev/null; then
            sleep 0.2  # Wait for system to create files
            if [ -e /sys/class/gpio/gpio$GPIO_PIN/direction ]; then
                echo "in" > /sys/class/gpio/gpio$GPIO_PIN/direction
                echo "GPIO $GPIO_PIN setup successfully"
            else
                echo "Warning: GPIO direction file not created"
                return 1
            fi
        else
            echo "Warning: Could not export GPIO $GPIO_PIN"
            return 1
        fi
    else
        echo "GPIO $GPIO_PIN already exported"
        echo "in" > /sys/class/gpio/gpio$GPIO_PIN/direction 2>/dev/null || true
    fi
    return 0
}

# Function to get disk device (handles multiple storage types)
get_primary_disk_device() {
    # Check for common Raspberry Pi storage devices in order of preference
    for device in "nvme0n1" "sda" "mmcblk0"; do
        if [ -e "/sys/block/$device" ]; then
            echo "$device"
            return 0
        fi
    done
    # Fallback to first available block device
    ls /sys/block/ | grep -E '^(sd|mmcblk|nvme)' | head -1
}

# Function to get all network interfaces
get_network_interfaces() {
    # Get all active network interfaces (excluding loopback)
    ls /sys/class/net/ | grep -v lo | head -3  # Limit to first 3 interfaces
}

# Setup GPIO
GPIO_AVAILABLE=0
if setup_gpio; then
    GPIO_AVAILABLE=1
fi

# Detect primary disk device
DISK_DEVICE=$(get_primary_disk_device)
if [ -z "$DISK_DEVICE" ]; then
    echo "Warning: No disk device found"
    DISK_DEVICE="mmcblk0"  # Fallback
fi
echo "Using disk device: $DISK_DEVICE"

# Get initial disk stats for primary device
read prev_rd prev_wr prev_rd_sectors prev_wr_sectors prev_rd_time prev_wr_time <<< $(awk "/$DISK_DEVICE / {print \$6, \$10, \$4, \$8, \$7, \$11}" /proc/diskstats)

# Get all available network interfaces
NET_INTERFACES=($(get_network_interfaces))
declare -A net_rx_prev net_tx_prev

# Initialize network stats for all interfaces
for interface in "${NET_INTERFACES[@]}"; do
    if [ -d "/sys/class/net/$interface" ]; then
        net_rx_prev[$interface]=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo "0")
        net_tx_prev[$interface]=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo "0")
        echo "Monitoring network interface: $interface"
    fi
done

# Enhanced memory info fields
MEMINFO_FIELDS="MemTotal MemFree MemAvailable Buffers Cached SwapCached Active Inactive Active(anon) Inactive(anon) Active(file) Inactive(file) Unevictable Mlocked SwapTotal SwapFree Zswap Zswapped Dirty Writeback AnonPages Mapped Shmem KReclaimable Slab SReclaimable SUnreclaim KernelStack PageTables SecPageTables NFS_Unstable Bounce WritebackTmp CommitLimit Committed_AS VmallocTotal VmallocUsed VmallocChunk Percpu CmaTotal CmaFree"

# Create CSV header
echo -n "Timestamp,CPU_Temp,CPU_Clock,GPU_Clock,Mem_Total,Mem_Used,Mem_Free,Swap_Used" > "$LOGFILE"

# Disk metrics (including hdparm timing tests)
echo -n ",Disk_Device,Disk_Read_KBps,Disk_Write_KBps,Disk_Usage_Percent,Disk_IOPS,Disk_Read_Latency_ms,Disk_Write_Latency_ms,Disk_Queue_Size,Disk_Free_GB,Disk_Total_GB,Cached_Read_MBps,Buffered_Read_MBps" >> "$LOGFILE"

# Network metrics for each interface
for interface in "${NET_INTERFACES[@]}"; do
    echo -n ",${interface}_Rx_KBps,${interface}_Tx_KBps,${interface}_Rx_Packets,${interface}_Tx_Packets,${interface}_Rx_Errors,${interface}_Tx_Errors,${interface}_Rx_Dropped,${interface}_Tx_Dropped" >> "$LOGFILE"
done

# Power and other metrics
echo -n ",Voltage,Current,Power,GPIO_State,CPU_Load,Process_Count,Running_Services,Listening_Ports,Active_Connections,Unique_Remote_Ports" >> "$LOGFILE"

# Memory info fields
for field in $MEMINFO_FIELDS; do
    echo -n ",$field" >> "$LOGFILE"
done
echo "" >> "$LOGFILE"

# Function to run hdparm timing tests
run_hdparm_test() {
    local device="/dev/$1"
    local cached_read=0
    local buffered_read=0
    
    if [ -e "$device" ] && command -v hdparm >/dev/null 2>&1; then
        # Run hdparm test and parse results
        local hdparm_output=$(timeout 30s hdparm -Tt "$device" 2>/dev/null || echo "")
        
        if [ -n "$hdparm_output" ]; then
            # Extract cached reads (typically the first line with MB/sec)
            cached_read=$(echo "$hdparm_output" | grep "cached reads" | grep -oP '[0-9]+\.[0-9]+(?= MB/sec)' | head -1)
            # Extract buffered disk reads (typically the second line with MB/sec)  
            buffered_read=$(echo "$hdparm_output" | grep "buffered disk reads" | grep -oP '[0-9]+\.[0-9]+(?= MB/sec)' | head -1)
        fi
    fi
    
    echo "${cached_read:-0} ${buffered_read:-0}"
}

# Test if hdparm is available
if ! command -v hdparm >/dev/null 2>&1; then
    echo "Warning: hdparm not found. Install with: sudo apt-get install hdparm"
    echo "Disk timing tests will be disabled."
fi

echo "Starting enhanced monitoring... Press Ctrl+C to stop"
echo "Logging to: $LOGFILE"
echo "Primary disk device: $DISK_DEVICE"
echo "Network interfaces: ${NET_INTERFACES[*]}"
if command -v hdparm >/dev/null 2>&1; then
    echo "hdparm disk timing tests: enabled"
else
    echo "hdparm disk timing tests: disabled (not installed)"
fi

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Temps and Clocks
    CPU_TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[0-9.]+' || echo "0")
    CPU_CLOCK=$(vcgencmd measure_clock arm 2>/dev/null | awk -F"=" '{printf "%.0f", $2/1000000}' || echo "0")
    GPU_CLOCK=$(vcgencmd measure_clock core 2>/dev/null | awk -F"=" '{printf "%.0f", $2/1000000}' || echo "0")
    
    # Memory
    read mem_total mem_used mem_free <<< $(free -m | awk '/^Mem:/ {print $2, $3, $4}')
    swap_used=$(free -m | awk '/Swap:/ {print $3}')
    
    # Enhanced Disk Metrics
    DISK_USAGE=$(df / | awk 'END {print $5}' | tr -d '%')
    DISK_FREE_GB=$(df -BG / | awk 'END {print $4}' | tr -d 'G')
    DISK_TOTAL_GB=$(df -BG / | awk 'END {print $2}' | tr -d 'G')
    
    # Advanced disk I/O metrics
    read new_rd new_wr new_rd_sectors new_wr_sectors new_rd_time new_wr_time queue_size <<< $(awk "/$DISK_DEVICE / {print \$6, \$10, \$4, \$8, \$7, \$11, \$9}" /proc/diskstats)
    
    # Calculate disk metrics
    RD_KBPS=$(( (new_rd - prev_rd) * 512 / 1024 / $INTERVAL ))
    WR_KBPS=$(( (new_wr - prev_wr) * 512 / 1024 / $INTERVAL ))
    DISK_IOPS=$(( ( (new_rd - prev_rd) + (new_wr - prev_wr) ) / $INTERVAL ))
    
    # Calculate latency (ms) - average time per I/O operation
    rd_ops=$((new_rd - prev_rd))
    wr_ops=$((new_wr - prev_wr))
    
    if [ $rd_ops -gt 0 ]; then
        RD_LATENCY=$(( (new_rd_time - prev_rd_time) / rd_ops ))
    else
        RD_LATENCY=0
    fi
    
    if [ $wr_ops -gt 0 ]; then
        WR_LATENCY=$(( (new_wr_time - prev_wr_time) / wr_ops ))
    else
        WR_LATENCY=0
    fi
    
    # Update previous values
    prev_rd=$new_rd
    prev_wr=$new_wr
    prev_rd_sectors=$new_rd_sectors
    prev_wr_sectors=$new_wr_sectors
    prev_rd_time=$new_rd_time
    prev_wr_time=$new_wr_time
    
    # hdparm timing tests (run every few cycles to avoid excessive I/O)
    # Only run timing tests every 6th iteration (every minute if INTERVAL=10)
    CYCLE_COUNT=${CYCLE_COUNT:-0}
    CYCLE_COUNT=$((CYCLE_COUNT + 1))
    
    if [ $((CYCLE_COUNT % 6)) -eq 1 ] && command -v hdparm >/dev/null 2>&1; then
        echo "Running hdparm timing test on /dev/$DISK_DEVICE..."
        read CACHED_READ BUFFERED_READ <<< $(run_hdparm_test "$DISK_DEVICE")
        # Store results for next few cycles
        LAST_CACHED_READ=$CACHED_READ
        LAST_BUFFERED_READ=$BUFFERED_READ
    else
        # Use last measured values
        CACHED_READ=${LAST_CACHED_READ:-0}
        BUFFERED_READ=${LAST_BUFFERED_READ:-0}
    fi
    
    # Enhanced Network Metrics for all interfaces
    declare -A net_stats
    for interface in "${NET_INTERFACES[@]}"; do
        if [ -d "/sys/class/net/$interface" ]; then
            # Get current stats
            rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo "0")
            tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo "0")
            rx_packets=$(cat /sys/class/net/$interface/statistics/rx_packets 2>/dev/null || echo "0")
            tx_packets=$(cat /sys/class/net/$interface/statistics/tx_packets 2>/dev/null || echo "0")
            rx_errors=$(cat /sys/class/net/$interface/statistics/rx_errors 2>/dev/null || echo "0")
            tx_errors=$(cat /sys/class/net/$interface/statistics/tx_errors 2>/dev/null || echo "0")
            rx_dropped=$(cat /sys/class/net/$interface/statistics/rx_dropped 2>/dev/null || echo "0")
            tx_dropped=$(cat /sys/class/net/$interface/statistics/tx_dropped 2>/dev/null || echo "0")
            
            # Calculate rates
            rx_kbps=$(( (rx_bytes - ${net_rx_prev[$interface]:-0}) / 1024 / $INTERVAL ))
            tx_kbps=$(( (tx_bytes - ${net_tx_prev[$interface]:-0}) / 1024 / $INTERVAL ))
            
            # Store current values for next iteration
            net_rx_prev[$interface]=$rx_bytes
            net_tx_prev[$interface]=$tx_bytes
            
            # Store all stats for this interface
            net_stats[${interface}_rx_kbps]=$rx_kbps
            net_stats[${interface}_tx_kbps]=$tx_kbps
            net_stats[${interface}_rx_packets]=$rx_packets
            net_stats[${interface}_tx_packets]=$tx_packets
            net_stats[${interface}_rx_errors]=$rx_errors
            net_stats[${interface}_tx_errors]=$tx_errors
            net_stats[${interface}_rx_dropped]=$rx_dropped
            net_stats[${interface}_tx_dropped]=$tx_dropped
        else
            # Interface not available, set zeros
            net_stats[${interface}_rx_kbps]=0
            net_stats[${interface}_tx_kbps]=0
            net_stats[${interface}_rx_packets]=0
            net_stats[${interface}_tx_packets]=0
            net_stats[${interface}_rx_errors]=0
            net_stats[${interface}_tx_errors]=0
            net_stats[${interface}_rx_dropped]=0
            net_stats[${interface}_tx_dropped]=0
        fi
    done
    
    # Power from INA219 (with error handling)
    POWER_DATA=$(python3 read_power.py 2>/dev/null || echo "0.000,0.000,0.000")
    
    # GPIO
    if [ $GPIO_AVAILABLE -eq 1 ] && [ -e /sys/class/gpio/gpio$GPIO_PIN/value ]; then
        GPIO_STATE=$(cat /sys/class/gpio/gpio$GPIO_PIN/value 2>/dev/null || echo "0")
    else
        GPIO_STATE="0"
    fi
    
    # CPU load
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' || echo "0")
    
    # Process and system metrics
    PROCESS_COUNT=$(ps -e --no-headers | wc -l)
    
    # Service and network connection metrics
    RUNNING_SERVICES=$(systemctl list-units --type=service --state=running 2>/dev/null | grep '.service' | wc -l || echo "0")
    LISTENING_PORTS=$(ss -tuln 2>/dev/null | grep -v "State" | wc -l || echo "0")
    ACTIVE_CONNECTIONS=$(ss -tun 2>/dev/null | grep -v "State" | wc -l || echo "0")
    UNIQUE_REMOTE_PORTS=$(ss -tun 2>/dev/null | awk '{print $5}' | grep -oE '[0-9]+$' | sort -n | uniq | wc -l || echo "0")
    
    # Read /proc/meminfo values
    declare -A meminfo
    while IFS=":" read -r key value; do
        key=$(echo "$key" | xargs)  # Trim whitespace
        meminfo["$key"]=$(echo "$value" | awk '{print $1}')
        if [[ "$key" == "CmaFree" ]]; then
            break
        fi
    done < /proc/meminfo
    
    # Write data to CSV
    echo -n "$TIMESTAMP,$CPU_TEMP,$CPU_CLOCK,$GPU_CLOCK,$mem_total,$mem_used,$mem_free,$swap_used" >> "$LOGFILE"
    
    # Disk metrics (including hdparm results)
    echo -n ",$DISK_DEVICE,$RD_KBPS,$WR_KBPS,$DISK_USAGE,$DISK_IOPS,$RD_LATENCY,$WR_LATENCY,$queue_size,$DISK_FREE_GB,$DISK_TOTAL_GB,$CACHED_READ,$BUFFERED_READ" >> "$LOGFILE"
    
    # Network metrics for each interface
    for interface in "${NET_INTERFACES[@]}"; do
        echo -n ",${net_stats[${interface}_rx_kbps]},${net_stats[${interface}_tx_kbps]},${net_stats[${interface}_rx_packets]},${net_stats[${interface}_tx_packets]},${net_stats[${interface}_rx_errors]},${net_stats[${interface}_tx_errors]},${net_stats[${interface}_rx_dropped]},${net_stats[${interface}_tx_dropped]}" >> "$LOGFILE"
    done
    
    # Power and system metrics
    echo -n ",$POWER_DATA,$GPIO_STATE,$CPU_LOAD,$PROCESS_COUNT,$RUNNING_SERVICES,$LISTENING_PORTS,$ACTIVE_CONNECTIONS,$UNIQUE_REMOTE_PORTS" >> "$LOGFILE"
    
    # Memory info fields
    for field in $MEMINFO_FIELDS; do
        echo -n ",${meminfo[$field]:-0}" >> "$LOGFILE"
    done
    echo "" >> "$LOGFILE"
    
    echo "[$(date '+%H:%M:%S')] Logged: CPU=${CPU_TEMP}°C, Processes: ${PROCESS_COUNT}, Services: ${RUNNING_SERVICES}, Connections: ${ACTIVE_CONNECTIONS}, Disk I/O: ${RD_KBPS}R/${WR_KBPS}W KB/s, Cached: ${CACHED_READ} MB/s, Net: ${net_stats[${NET_INTERFACES[0]:-eth0}_rx_kbps]:-0}R/${net_stats[${NET_INTERFACES[0]:-eth0}_tx_kbps]:-0}T KB/s"
    
    sleep $INTERVAL
done
