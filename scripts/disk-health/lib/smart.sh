#!/bin/bash
# smart.sh - SMART data retrieval and parsing functions
# Provides functions to get disk health information via smartctl

# Get list of all block devices (excluding loop, ram, etc)
get_disk_list() {
    lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' | sort
}

# Check if disk supports SMART
disk_supports_smart() {
    local device="$1"
    smartctl -i "$device" 2>/dev/null | grep -q "SMART support is: Available"
}

# Get disk type (HDD, SSD, NVMe)
get_disk_type() {
    local device="$1"
    local name=$(basename "$device")

    # Check if NVMe
    if [[ "$name" == nvme* ]]; then
        echo "NVMe"
        return
    fi

    # Check rotation rate (0 = SSD, >0 = HDD)
    local rotation=$(smartctl -i "$device" 2>/dev/null | grep "Rotation Rate" | awk -F: '{print $2}' | xargs)

    if [ -z "$rotation" ]; then
        # Try lsblk as fallback
        local rota=$(lsblk -dno ROTA "$device" 2>/dev/null)
        if [ "$rota" = "0" ]; then
            echo "SSD"
        else
            echo "HDD"
        fi
    elif [[ "$rotation" == *"Solid State"* ]] || [[ "$rotation" == "0"* ]]; then
        echo "SSD"
    else
        echo "HDD"
    fi
}

# Get disk model
get_disk_model() {
    local device="$1"
    local model=""

    # Try smartctl first
    model=$(smartctl -i "$device" 2>/dev/null | grep -E "^(Device Model|Model Number|Product):" | head -1 | awk -F: '{print $2}' | xargs)

    # Fallback to lsblk
    if [ -z "$model" ]; then
        model=$(lsblk -dno MODEL "$device" 2>/dev/null | xargs)
    fi

    echo "${model:-Unknown}"
}

# Get disk serial number
get_disk_serial() {
    local device="$1"
    local serial=""

    serial=$(smartctl -i "$device" 2>/dev/null | grep -E "^Serial Number:" | awk -F: '{print $2}' | xargs)

    if [ -z "$serial" ]; then
        serial=$(lsblk -dno SERIAL "$device" 2>/dev/null | xargs)
    fi

    echo "${serial:-Unknown}"
}

# Get disk size in bytes
get_disk_size() {
    local device="$1"
    lsblk -bdno SIZE "$device" 2>/dev/null || echo "0"
}

# Get disk firmware version
get_disk_firmware() {
    local device="$1"
    smartctl -i "$device" 2>/dev/null | grep -E "^Firmware Version:" | awk -F: '{print $2}' | xargs
}

# Get SMART health status
get_smart_health() {
    local device="$1"
    local health=$(smartctl -H "$device" 2>/dev/null | grep -E "SMART overall-health|SMART Health Status" | awk -F: '{print $2}' | xargs)
    echo "${health:-Unknown}"
}

# Get power on hours
get_power_on_hours() {
    local device="$1"
    local hours=""

    # Standard SMART attribute (ID 9)
    hours=$(smartctl -A "$device" 2>/dev/null | grep -E "Power_On_Hours|Power On Hours" | awk '{print $(NF)}')

    # NVMe format
    if [ -z "$hours" ]; then
        hours=$(smartctl -A "$device" 2>/dev/null | grep "Power On Hours" | awk -F: '{print $2}' | tr -d ',' | xargs)
    fi

    echo "${hours:-0}"
}

# Get temperature
get_disk_temperature() {
    local device="$1"
    local temp=""

    # Try SMART attributes
    temp=$(smartctl -A "$device" 2>/dev/null | grep -E "Temperature_Celsius|Airflow_Temperature|Temperature:" | head -1 | awk '{print $(NF-0)}' | grep -oE '[0-9]+' | head -1)

    # NVMe specific
    if [ -z "$temp" ]; then
        temp=$(smartctl -A "$device" 2>/dev/null | grep "Temperature:" | head -1 | awk '{print $2}' | grep -oE '[0-9]+')
    fi

    echo "${temp:-N/A}"
}

# Get reallocated sector count (HDD/SSD)
get_reallocated_sectors() {
    local device="$1"
    smartctl -A "$device" 2>/dev/null | grep "Reallocated_Sector_Ct" | awk '{print $NF}'
}

# Get pending sector count
get_pending_sectors() {
    local device="$1"
    smartctl -A "$device" 2>/dev/null | grep "Current_Pending_Sector" | awk '{print $NF}'
}

# Get uncorrectable sector count
get_uncorrectable_sectors() {
    local device="$1"
    smartctl -A "$device" 2>/dev/null | grep "Offline_Uncorrectable" | awk '{print $NF}'
}

# Get SSD wear level / life remaining
get_ssd_life_remaining() {
    local device="$1"
    local life=""

    # Try various SMART attributes for SSD wear
    # Wear_Leveling_Count (common Samsung)
    life=$(smartctl -A "$device" 2>/dev/null | grep "Wear_Leveling_Count" | awk '{print $4}')

    # Media_Wearout_Indicator (Intel)
    if [ -z "$life" ]; then
        life=$(smartctl -A "$device" 2>/dev/null | grep "Media_Wearout_Indicator" | awk '{print $4}')
    fi

    # SSD_Life_Left
    if [ -z "$life" ]; then
        life=$(smartctl -A "$device" 2>/dev/null | grep "SSD_Life_Left" | awk '{print $4}')
    fi

    # Percent_Lifetime_Remain
    if [ -z "$life" ]; then
        life=$(smartctl -A "$device" 2>/dev/null | grep "Percent_Lifetime_Remain" | awk '{print $4}')
    fi

    # NVMe Percentage Used (inverse)
    if [ -z "$life" ]; then
        local used=$(smartctl -A "$device" 2>/dev/null | grep "Percentage Used:" | awk '{print $3}' | tr -d '%')
        if [ -n "$used" ]; then
            life=$((100 - used))
        fi
    fi

    echo "${life:-N/A}"
}

# Get total bytes written (SSD/NVMe)
get_total_bytes_written() {
    local device="$1"
    local written=""

    # NVMe format (in 512-byte units, need to convert)
    written=$(smartctl -A "$device" 2>/dev/null | grep "Data Units Written:" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
    if [ -n "$written" ] && [ "$written" != "0" ]; then
        # Convert from 512KB units to bytes
        written=$((written * 512000))
        echo "$written"
        return
    fi

    # SATA SSD format (Total_LBAs_Written)
    written=$(smartctl -A "$device" 2>/dev/null | grep "Total_LBAs_Written" | awk '{print $NF}')
    if [ -n "$written" ] && [ "$written" != "0" ]; then
        # Convert from LBAs (512 bytes each) to bytes
        written=$((written * 512))
        echo "$written"
        return
    fi

    echo "0"
}

# Get SMART error count
get_smart_error_count() {
    local device="$1"
    local errors=$(smartctl -l error "$device" 2>/dev/null | grep -E "ATA Error Count:|No Errors Logged" | head -1)

    if [[ "$errors" == *"No Errors Logged"* ]]; then
        echo "0"
    elif [[ "$errors" == *"ATA Error Count:"* ]]; then
        echo "$errors" | awk -F: '{print $2}' | xargs
    else
        # NVMe
        errors=$(smartctl -l error "$device" 2>/dev/null | grep "Error Information" | wc -l)
        echo "${errors:-0}"
    fi
}

# Get disk health score (0-100)
# Based on critical SMART attributes
calculate_health_score() {
    local device="$1"
    local score=100
    local disk_type=$(get_disk_type "$device")

    # Check SMART health status
    local health=$(get_smart_health "$device")
    if [[ "$health" != "PASSED" ]] && [[ "$health" != "OK" ]]; then
        score=$((score - 50))
    fi

    # Check reallocated sectors (critical for HDD/SSD)
    local reallocated=$(get_reallocated_sectors "$device")
    if [ -n "$reallocated" ] && [ "$reallocated" != "0" ]; then
        if [ "$reallocated" -gt 100 ]; then
            score=$((score - 30))
        elif [ "$reallocated" -gt 10 ]; then
            score=$((score - 15))
        else
            score=$((score - 5))
        fi
    fi

    # Check pending sectors
    local pending=$(get_pending_sectors "$device")
    if [ -n "$pending" ] && [ "$pending" != "0" ]; then
        score=$((score - 10))
    fi

    # Check uncorrectable sectors
    local uncorrectable=$(get_uncorrectable_sectors "$device")
    if [ -n "$uncorrectable" ] && [ "$uncorrectable" != "0" ]; then
        score=$((score - 15))
    fi

    # Check SMART errors
    local errors=$(get_smart_error_count "$device")
    if [ -n "$errors" ] && [ "$errors" != "0" ]; then
        if [ "$errors" -gt 10 ]; then
            score=$((score - 20))
        else
            score=$((score - 5))
        fi
    fi

    # For SSDs, check life remaining
    if [ "$disk_type" = "SSD" ] || [ "$disk_type" = "NVMe" ]; then
        local life=$(get_ssd_life_remaining "$device")
        if [ "$life" != "N/A" ] && [ -n "$life" ]; then
            if [ "$life" -lt 10 ]; then
                score=$((score - 30))
            elif [ "$life" -lt 30 ]; then
                score=$((score - 15))
            elif [ "$life" -lt 50 ]; then
                score=$((score - 5))
            fi
        fi
    fi

    # Check temperature
    local temp=$(get_disk_temperature "$device")
    if [ "$temp" != "N/A" ] && [ -n "$temp" ]; then
        if [ "$temp" -gt 60 ]; then
            score=$((score - 15))
        elif [ "$temp" -gt 50 ]; then
            score=$((score - 5))
        fi
    fi

    # Ensure score is between 0 and 100
    [ "$score" -lt 0 ] && score=0
    [ "$score" -gt 100 ] && score=100

    echo "$score"
}

# Get health status text based on score
get_health_status() {
    local score="$1"

    if [ "$score" -ge 90 ]; then
        echo "Excellent"
    elif [ "$score" -ge 70 ]; then
        echo "Good"
    elif [ "$score" -ge 50 ]; then
        echo "Fair"
    elif [ "$score" -ge 30 ]; then
        echo "Poor"
    else
        echo "Critical"
    fi
}

# Get all SMART attributes for a disk (raw output)
get_smart_attributes() {
    local device="$1"
    smartctl -A "$device" 2>/dev/null
}

# Get SMART self-test results
get_smart_selftest() {
    local device="$1"
    smartctl -l selftest "$device" 2>/dev/null | tail -n +6 | head -5
}

# Check if disk has any critical warnings
has_critical_warnings() {
    local device="$1"
    local health=$(get_smart_health "$device")
    local reallocated=$(get_reallocated_sectors "$device")
    local pending=$(get_pending_sectors "$device")
    local uncorrectable=$(get_uncorrectable_sectors "$device")

    # Check SMART health
    if [[ "$health" != "PASSED" ]] && [[ "$health" != "OK" ]] && [[ "$health" != "Unknown" ]]; then
        return 0
    fi

    # Check critical sectors
    if [ -n "$reallocated" ] && [ "$reallocated" -gt 100 ]; then
        return 0
    fi

    if [ -n "$pending" ] && [ "$pending" -gt 0 ]; then
        return 0
    fi

    if [ -n "$uncorrectable" ] && [ "$uncorrectable" -gt 0 ]; then
        return 0
    fi

    # Check SSD life
    local life=$(get_ssd_life_remaining "$device")
    if [ "$life" != "N/A" ] && [ -n "$life" ] && [ "$life" -lt 10 ]; then
        return 0
    fi

    return 1
}
