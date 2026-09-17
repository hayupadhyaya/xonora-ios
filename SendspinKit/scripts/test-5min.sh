#!/bin/bash
# ABOUTME: 5-minute PCM stream test for Swift ResonateKit client
# ABOUTME: Runs CLI player and captures telemetry logs for analysis

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_DURATION_SECONDS=300  # 5 minutes
SERVER_URL="${1:-ws://localhost:8927}"
CLIENT_NAME="${2:-Test Client}"
LOG_DIR="./test-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/5min-test_${TIMESTAMP}.log"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  ResonateKit 5-Minute PCM Stream Test  ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Server URL:    ${GREEN}${SERVER_URL}${NC}"
echo -e "Client Name:   ${GREEN}${CLIENT_NAME}${NC}"
echo -e "Duration:      ${GREEN}${TEST_DURATION_SECONDS}s (5 minutes)${NC}"
echo -e "Log File:      ${GREEN}${LOG_FILE}${NC}"
echo ""

# Create log directory
mkdir -p "${LOG_DIR}"

# Check if CLI player is built
CLI_PLAYER="./Examples/CLIPlayer/.build/release/CLIPlayer"
if [ ! -f "${CLI_PLAYER}" ]; then
    echo -e "${YELLOW}⚠️  CLI Player not found, building...${NC}"
    cd Examples/CLIPlayer
    swift build -c release
    cd ../..
    echo -e "${GREEN}✅ Build complete${NC}"
fi

# Start the test
echo -e "${BLUE}🎵 Starting test at $(date)${NC}"
echo -e "${YELLOW}   Press Ctrl+C to stop early${NC}"
echo ""

# Run the CLI player with timeout
timeout "${TEST_DURATION_SECONDS}s" "${CLI_PLAYER}" "${SERVER_URL}" "${CLIENT_NAME}" 2>&1 | tee "${LOG_FILE}" || {
    exit_code=$?
    if [ ${exit_code} -eq 124 ]; then
        echo ""
        echo -e "${GREEN}✅ Test completed successfully (${TEST_DURATION_SECONDS}s)${NC}"
    else
        echo ""
        echo -e "${RED}❌ Test failed with exit code ${exit_code}${NC}"
        exit ${exit_code}
    fi
}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Test Results & Analysis                ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Extract telemetry data
TELEMETRY_FILE="${LOG_DIR}/telemetry_${TIMESTAMP}.txt"
grep "\[TELEMETRY\]" "${LOG_FILE}" > "${TELEMETRY_FILE}" || true

# Count telemetry lines
TELEMETRY_COUNT=$(wc -l < "${TELEMETRY_FILE}" | tr -d ' ')
echo -e "Telemetry samples: ${GREEN}${TELEMETRY_COUNT}${NC} (expect ~${TEST_DURATION_SECONDS})"

if [ "${TELEMETRY_COUNT}" -eq 0 ]; then
    echo -e "${RED}❌ No telemetry data found${NC}"
    echo -e "   Check that audio stream started"
    exit 1
fi

# Calculate statistics
echo ""
echo -e "${BLUE}Calculating statistics...${NC}"

# Parse telemetry and calculate totals
awk -F'[=,]' '
BEGIN {
    total_scheduled = 0
    total_played = 0
    total_dropped_late = 0
    total_dropped_other = 0
    count = 0
    sum_buffer = 0
    sum_offset = 0
    sum_rtt = 0
}
{
    # Extract values (format: framesScheduled=X, framesPlayed=Y, ...)
    for (i = 1; i <= NF; i++) {
        if ($i ~ /framesScheduled/) total_scheduled += $(i+1)
        if ($i ~ /framesPlayed/) total_played += $(i+1)
        if ($i ~ /framesDroppedLate/) total_dropped_late += $(i+1)
        if ($i ~ /framesDroppedOther/) total_dropped_other += $(i+1)
        if ($i ~ /bufferFillMs/) { sum_buffer += $(i+1); count++ }
        if ($i ~ /clockOffsetMs/) sum_offset += $(i+1)
        if ($i ~ /rttMs/) sum_rtt += $(i+1)
    }
}
END {
    print "TOTAL_SCHEDULED=" total_scheduled
    print "TOTAL_PLAYED=" total_played
    print "TOTAL_DROPPED_LATE=" total_dropped_late
    print "TOTAL_DROPPED_OTHER=" total_dropped_other
    print "AVG_BUFFER=" (count > 0 ? sum_buffer / count : 0)
    print "AVG_OFFSET=" (count > 0 ? sum_offset / count : 0)
    print "AVG_RTT=" (count > 0 ? sum_rtt / count : 0)
}
' "${TELEMETRY_FILE}" > "${LOG_DIR}/stats_${TIMESTAMP}.txt"

# Source the stats
source "${LOG_DIR}/stats_${TIMESTAMP}.txt"

# Display results
echo ""
echo -e "${BLUE}📊 Audio Frame Statistics:${NC}"
echo -e "   Total Scheduled:    ${GREEN}${TOTAL_SCHEDULED}${NC}"
echo -e "   Total Played:       ${GREEN}${TOTAL_PLAYED}${NC}"
echo -e "   Dropped (Late):     ${YELLOW}${TOTAL_DROPPED_LATE}${NC}"
echo -e "   Dropped (Other):    ${YELLOW}${TOTAL_DROPPED_OTHER}${NC}"

# Calculate drop rate
if [ "${TOTAL_SCHEDULED}" -gt 0 ]; then
    DROP_RATE=$(awk "BEGIN {printf \"%.2f\", (${TOTAL_DROPPED_LATE} / ${TOTAL_SCHEDULED} * 100)}")
    echo -e "   Late Drop Rate:     ${DROP_RATE}%"

    # Check acceptance criteria
    if (( $(echo "${DROP_RATE} <= 1.0" | bc -l) )); then
        echo -e "                       ${GREEN}✅ PASS (≤1%)${NC}"
    else
        echo -e "                       ${RED}❌ FAIL (>1%)${NC}"
    fi
fi

echo ""
echo -e "${BLUE}⏱️  Clock Synchronization:${NC}"
echo -e "   Avg Clock Offset:   ${AVG_OFFSET} ms"
echo -e "   Avg RTT:            ${AVG_RTT} ms"

if (( $(echo "${AVG_RTT} < 50.0" | bc -l) )); then
    echo -e "                       ${GREEN}✅ Good RTT (<50ms)${NC}"
elif (( $(echo "${AVG_RTT} < 100.0" | bc -l) )); then
    echo -e "                       ${YELLOW}⚠️  Degraded RTT (<100ms)${NC}"
else
    echo -e "                       ${RED}❌ Poor RTT (>100ms)${NC}"
fi

echo ""
echo -e "${BLUE}📦 Buffer Management:${NC}"
echo -e "   Avg Buffer Fill:    ${AVG_BUFFER} ms"

if (( $(echo "${AVG_BUFFER} >= 120.0 && ${AVG_BUFFER} <= 200.0" | bc -l) )); then
    echo -e "                       ${GREEN}✅ Optimal (120-200ms)${NC}"
elif (( $(echo "${AVG_BUFFER} > 0" | bc -l) )); then
    echo -e "                       ${YELLOW}⚠️  Outside target range${NC}"
else
    echo -e "                       ${RED}❌ Buffer empty${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Acceptance Criteria Check             ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PASS_COUNT=0
TOTAL_CRITERIA=3

# Criterion 1: Drop rate ≤ 1%
if (( $(echo "${DROP_RATE} <= 1.0" | bc -l) )); then
    echo -e "✅ Late-frame drop rate ≤ 1%"
    ((PASS_COUNT++))
else
    echo -e "❌ Late-frame drop rate > 1%"
fi

# Criterion 2: RTT < 50ms (good quality)
if (( $(echo "${AVG_RTT} < 50.0" | bc -l) )); then
    echo -e "✅ Average RTT < 50ms (good sync quality)"
    ((PASS_COUNT++))
else
    echo -e "⚠️  Average RTT ≥ 50ms (consider network improvement)"
fi

# Criterion 3: Duration ≥ 5 minutes
if [ "${TELEMETRY_COUNT}" -ge 290 ]; then
    echo -e "✅ Test duration ≥ 5 minutes (${TELEMETRY_COUNT}s)"
    ((PASS_COUNT++))
else
    echo -e "❌ Test duration < 5 minutes (${TELEMETRY_COUNT}s)"
fi

echo ""
if [ "${PASS_COUNT}" -eq "${TOTAL_CRITERIA}" ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ ALL ACCEPTANCE CRITERIA PASSED     ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ⚠️  ${PASS_COUNT}/${TOTAL_CRITERIA} CRITERIA PASSED${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

echo ""
echo -e "Full logs:      ${LOG_FILE}"
echo -e "Telemetry data: ${TELEMETRY_FILE}"
echo -e "Statistics:     ${LOG_DIR}/stats_${TIMESTAMP}.txt"
echo ""
