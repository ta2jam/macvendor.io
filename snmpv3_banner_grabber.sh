#!/usr/bin/env bash

# -----------------------------------------
# SNMPv3 Banner Grabber with Packet Capture
# Uses tcpdump to capture packets while sending probes.
#
# This script sends snmp v3 discovery probes to a target IP
# and captures the raw UDP packets on port 161 for analysis.
#
# Usage:
#   ./core.sh <target-ip> [interface]
#
# Requirements:
#   - net-snmp (for snmpget)
#   - tcpdump
#   - bash
#
# Output:
#  SNMP:
#   Versions:
#     3
#   Engineid Format: mac
#   Engine Boots: 1
#   Engineid Data: 10:56:ca:69:8a:dd
#   Enterprise: 8072
#   Engine Time: 12 days, 14:12:2
#
# Saved to <target-ip>_snmp_capture.pcap
# ----------------------------------------

set -euo pipefail

# Default values
TARGET="${1:-}"
COMMUNITY="${COMMUNITY:-public}"
PCAP_FILE="${TARGET}_snmp_capture.pcap"
TIMEOUT=5  # seconds to capture
# Detect the interface for the target
if [[ -n "$2" ]]; then
    INTERFACE="$2"
else
    INTERFACE=$(route get "$TARGET" 2>/dev/null | awk '/interface/ {print $2}')
    if [[ -z "$INTERFACE" ]]; then
        INTERFACE="en0"  # fallback
    fi
fi

TCP_COMMAND="sudo tcpdump -i $INTERFACE udp port 161 and host $TARGET -w $PCAP_FILE"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <target-ip> [interface]"
    echo "Example: $0 192.168.1.100 en0"
    exit 1
fi

# Validate target IP format (basic check)
if ! [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format: $TARGET"
    exit 1
fi

echo "[*] Target: $TARGET"
echo "[*] Interface: $INTERFACE"
echo "[*] Community: $COMMUNITY"
echo "[*] Capturing to: $PCAP_FILE"
echo "[*] Timeout: ${TIMEOUT}s"
echo

# ----------------------------------------
# FUNCTION: run tcpdump in background
# ----------------------------------------
start_capture() {
    echo "[*] Starting packet capture..."
    $TCP_COMMAND &
    TCPDUMP_PID=$!
    echo "[*] tcpdump PID: $TCPDUMP_PID"
}

stop_capture() {
    echo "[*] Stopping packet capture..."
    kill "$TCPDUMP_PID" 2>/dev/null || true
    wait "$TCPDUMP_PID" 2>/dev/null || true
    echo "[*] Capture saved to $PCAP_FILE"
}

# ----------------------------------------
# FUNCTION: send SNMPv3 discovery packet
# (bogus user triggers REPORT if allowed)
# ----------------------------------------
snmp_v3_discovery() {
    echo "[*] Sending SNMPv3 discovery (bogus user triggers REPORT)"
    echo "Running: snmpget -v3 -l noAuthNoPriv -u fakeuser -t 3 -r 1 $TARGET 1.3.6.1.2.1.1.1.0"
    snmpget -v3 \
        -l noAuthNoPriv \
        -u fakeuser \
        -t 3 -r 1 \
        "$TARGET" \
        1.3.6.1.2.1.1.1.0 2>/dev/null || echo "[!] SNMPv3 discovery failed or timed out"
}

# ----------------------------------------
# FUNCTION: basic analysis of packets
# ----------------------------------------
analyze_capture() {
    echo "[*] Decoding captured payloads..."

    if [[ ! -f "$PCAP_FILE" ]]; then
        echo "[!] Capture file not found; skipping analysis."
        return
    fi

    if command -v tshark >/dev/null 2>&1; then
        echo "[*] Extracting printable bytes from packets..."
        tshark -r "$PCAP_FILE" -T fields -e data 2>/dev/null |
            awk 'NF {gsub(":",""); print}' |
            python3 -c 'import sys

def printable(raw: bytes) -> str:
    return "".join(chr(b) if 32 <= b < 127 else "." for b in raw)

for idx, line in enumerate(sys.stdin, 1):
    hex_line = line.strip()
    if not hex_line:
        continue
    try:
        data = bytes.fromhex(hex_line)
    except ValueError:
        continue
    text = printable(data)
    if text.replace(".", ""):
        print(f"[packet {idx}] {text}")'
        return
    fi

    echo "[*] tshark not found; showing tcpdump ASCII view..."
    tcpdump -nn -X -r "$PCAP_FILE" 2>/dev/null || echo "[!] tcpdump failed to read capture"
}

# ----------------------------------------
# MAIN SCRIPT LOGIC
# ----------------------------------------

# Clean up any existing capture file
rm -f "$PCAP_FILE"

# Start capture
start_capture

# Send probes
snmp_v3_discovery

# Wait a bit for any delayed responses
echo "[*] Waiting for responses..."
sleep "$TIMEOUT"

# Stop capture
stop_capture

# Optional analysis
analyze_capture

# Print MAC addresses
echo "[*] Extracting unique MAC addresses from capture..."
if command -v tshark >/dev/null 2>&1; then
    tshark -r "$PCAP_FILE" -T fields -e eth.src -e eth.dst 2>/dev/null | sort | uniq | while read -r src dst; do
        echo "  Source MAC: $src | Destination MAC: $dst"
    done
else
    echo "[!] tshark not found; cannot extract MAC addresses."
fi

# Print detailed SNMPv3 information
echo "[*] Extracting detailed SNMPv3 information from responses..."
if command -v tshark >/dev/null 2>&1; then
    # Get unique combinations of engine ID, boots, time
    tshark -r "$PCAP_FILE" -d udp.port=161,snmp -T fields -e snmp.msgAuthoritativeEngineID -e snmp.msgAuthoritativeEngineBoots -e snmp.msgAuthoritativeEngineTime 2>/dev/null | grep -v '<MISSING>' | sort | uniq | while read -r engine_id boots time; do
        if [[ -n "$engine_id" && "$engine_id" != "<MISSING>" ]]; then
            # Parse engine ID: remove underscores and convert to hex array
            hex=$(echo "$engine_id" | tr -d '_')
            # First byte: format
            format_byte=$(echo "$hex" | cut -c1-2)
            if [[ "$format_byte" == "80" ]]; then
                format="mac"
                # Next 2 bytes: enterprise (big endian)
                ent_hex=$(echo "$hex" | cut -c5-8)
                enterprise=$((16#$ent_hex))
                # Next 6 bytes: MAC
                mac_hex=$(echo "$hex" | cut -c11-22)
                mac=$(echo "$mac_hex" | sed 's/../&:/g' | sed 's/:$//')
            else
                format="unknown ($format_byte)"
                enterprise="N/A"
                mac="N/A"
                ent_name="N/A"
            fi
            # Calculate engine time in days, hours, etc.
            if [[ -n "$time" ]]; then
                days=$((time / 86400))
                hours=$(( (time % 86400) / 3600 ))
                mins=$(( (time % 3600) / 60 ))
                secs=$((time % 60))
                engine_time="${days} days, ${hours}:${mins}:${secs}"
            else
                engine_time="N/A"
            fi
            echo "SNMP:"
            echo "  Versions:"
            echo "    3"
            echo "  Engineid Format: $format"
            echo "  Engine Boots: $boots"
            echo "  Engineid Data: $mac"
            echo "  Enterprise: $enterprise"
            echo "  Engine Time: $engine_time"
            # echo "  Vendor Name: $vend_name"
            # echo "  Enterprise Name: $ent_name"
            # enterprise=8072 is Net-SNMP
            # https://www.iana.org/assignments/enterprise-numbers/?q=8072
            # https://www.iana.org/assignments/enterprise-numbers/?q=${enterprise}
            echo
        fi
    done
else
    echo "[!] tshark not found; cannot extract SNMPv3 details."
fi
