#!/bin/bash
set -e

# ZK_InsuranceX Test Script - Termination, Claim & Withdrawal
#
# RUN AFTER setup_insurancex.sh completes!
#
# chmod +x test_insurancex.sh
# ./test_insurancex.sh

ENDPOINT="http://localhost:3030"
CONSENSUS="--consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11"
NETWORK="--network testnet --broadcast"

# Program name (update if different)
PROGRAM="zk_insurancex_v1.aleo"

# Addresses - Using same wallet for both employer and employee for testing
ADMIN="aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px"
EMPLOYER="aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px"
EMPLOYEE="aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px"

# Private key (same for all since using one wallet)
PRIVATE_KEY="APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH"

# Project paths
VAULT_DIR=~/ZK_InsuranceX/vault

# Employment details (from setup)
SALARY=5000000000
START_BLOCK=1

cd $VAULT_DIR

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     ZK_InsuranceX Test: Termination, Claim & Withdrawal       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Program: $PROGRAM"

# Get current block
get_block() {
    curl -s "$ENDPOINT/testnet/block/height/latest"
}

# Check if records exist
if [ ! -f "$VAULT_DIR/records/employer_employment.txt" ]; then
    echo "ERROR: Records not found. Run setup_insurancex.sh first!"
    exit 1
fi

# Read records from files (created by setup script)
EMPLOYER_RECORD=$(cat $VAULT_DIR/records/employer_employment.txt)
EMPLOYEE_RECORD=$(cat $VAULT_DIR/records/employee_employment.txt)

echo "Employer record loaded from file"
echo "Employee record loaded from file"

current_block=$(get_block)
echo "Current block: $current_block"

# ═══════════════════════════════════════════════════════════
# STEP 1: Employer initiates termination
# ═══════════════════════════════════════════════════════════

echo ""
echo "=== STEP 1: Employer initiates termination ==="

current_block=$(get_block)
echo "Current block: $current_block"

echo "Using employer record from file..."
echo "Initiating termination..."
leo execute terminate_initiate "$EMPLOYER_RECORD" ${current_block}u64 $NETWORK $CONSENSUS --yes 2>&1 | tee /tmp/terminate_initiate_output.txt
sleep 3

# ═══════════════════════════════════════════════════════════
# STEP 2: Wait for response period
# ═══════════════════════════════════════════════════════════

echo ""
echo "=== STEP 2: Waiting for termination response period (10 blocks) ==="

target_block=$((current_block + 12))
echo "Waiting until block $target_block..."

while [ $(get_block) -lt $target_block ]; do
    echo "  Block $(get_block) / $target_block"
    sleep 2
done

echo "Response period passed!"

# ═══════════════════════════════════════════════════════════
# STEP 3: Employee confirms termination
# ═══════════════════════════════════════════════════════════

echo ""
echo "=== STEP 3: Employee confirms termination ==="

end_block=$(get_block)
echo "End block: $end_block"

echo "Using employee record from file..."
echo "Confirming termination..."
leo execute terminate_confirm "$EMPLOYEE_RECORD" ${end_block}u64 $NETWORK $CONSENSUS --yes 2>&1 | tee /tmp/terminate_confirm_output.txt
sleep 3

# Check employee count decreased
echo ""
echo "Checking employee count..."
curl -s "$ENDPOINT/testnet/program/$PROGRAM/mapping/employee_count/$EMPLOYER"
echo ""

# ═══════════════════════════════════════════════════════════
# STEP 4: Employee submits claim
# ═══════════════════════════════════════════════════════════

echo ""
echo "=== STEP 4: Employee submits claim ==="

# Extract terminated record from terminate_confirm output using Python
echo "Extracting terminated record from previous output..."
TERMINATED_RECORD=$(python3 << 'PYEOF'
import re
with open('/tmp/terminate_confirm_output.txt', 'r') as f:
    content = f.read()

# Find records more carefully - match { ... } but stop at first }
# Split by '•' to get individual output items
parts = content.split('•')
for part in parts:
    # Look for Employment record pattern
    if 'salary:' in part and 'is_active:' in part and 'termination_type:' in part:
        # Extract just the { ... } part
        match = re.search(r'\{[^}]+\}', part)
        if match:
            record = match.group(0).replace('\n', ' ').replace('  ', ' ')
            print(record)
            break
PYEOF
)

echo "Submitting claim..."
leo execute submit_claim "$TERMINATED_RECORD" $NETWORK $CONSENSUS --yes 2>&1 | tee /tmp/submit_claim_output.txt
sleep 3

# Check active claims
echo ""
echo "Checking active claims..."
curl -s "$ENDPOINT/testnet/program/$PROGRAM/mapping/active_claims/$EMPLOYEE"
echo ""

# ═══════════════════════════════════════════════════════════
# STEP 5: Wait for first withdrawal period
# ═══════════════════════════════════════════════════════════

echo ""
echo "=== STEP 5: Waiting for withdrawal period (100 blocks) ==="

# Need to wait BLOCKS_PER_MONTH (15) from end_block
target_block=$((end_block + 15))
echo "Waiting until block $target_block..."

while [ $(get_block) -lt $target_block ]; do
    current=$(get_block)
    remaining=$((target_block - current))
    echo "  Block $current / $target_block ($remaining blocks remaining)"
    sleep 5
done

echo "Withdrawal period reached!"

# ═══════════════════════════════════════════════════════════
# STEP 6: Employee withdraws first benefit
# ═══════════════════════════════════════════════════════════

echo ""
echo "=== STEP 6: Employee withdraws first benefit ==="

current_block=$(get_block)

# Extract claim record from submit_claim output using Python
echo "Extracting claim record from previous output..."
CLAIM_RECORD=$(python3 << 'PYEOF'
import re
with open('/tmp/submit_claim_output.txt', 'r') as f:
    content = f.read()

# Split by '•' to get individual output items
parts = content.split('•')
for part in parts:
    # Look for Claim record pattern (has benefit_amount and total_months)
    if 'benefit_amount:' in part and 'total_months:' in part:
        # Extract just the { ... } part
        match = re.search(r'\{[^}]+\}', part)
        if match:
            record = match.group(0).replace('\n', ' ').replace('  ', ' ')
            print(record)
            break
PYEOF
)

echo "Withdrawing benefit..."
leo execute withdraw_benefit "$CLAIM_RECORD" ${current_block}u64 $NETWORK $CONSENSUS --yes 2>&1 | tee /tmp/withdraw_benefit_output.txt
sleep 3

# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                         Summary                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Pool balance:"
curl -s "$ENDPOINT/testnet/program/$PROGRAM/mapping/pool_balance/0u8"
echo ""
echo ""
echo "Employee USDC balance:"
curl -s "$ENDPOINT/testnet/program/mock_usdc.aleo/mapping/balances/$EMPLOYEE"
echo ""
echo ""
echo "Active claims:"
curl -s "$ENDPOINT/testnet/program/$PROGRAM/mapping/active_claims/$EMPLOYEE"
echo ""
echo ""
echo "Test complete!"
echo ""
echo "Expected results:"
echo "  - Pool balance decreased by 3,500,000,000 (3500 USDC)"
echo "  - Employee received 3500 USDC"
echo "  - Active claim still true (23 months remaining)"
