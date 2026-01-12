#!/bin/bash
set -e

# ZK_InsuranceX Setup Script for Local Devnet
#
# HOW TO RUN?
#
# Terminal 1: Start devnet
# leo devnet --snarkos $(which snarkos) --snarkos-features test_network --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage 
#
# Terminal 2: Run setup
# chmod +x setup_insurancex.sh
# ./setup_insurancex.sh

ENDPOINT="http://localhost:3030"
CONSENSUS="--consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11"
NETWORK="--network testnet --broadcast"

# Program name (update if different)
PROGRAM="zk_insurancex_v1.aleo"

# Addresses - Using same wallet for both employer and employee for testing
ADMIN="aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px"
EMPLOYER="aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px"
EMPLOYEE="aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px"

# Project paths - UPDATE THESE TO YOUR PATHS
MOCK_USDC_DIR=~/ZK_InsuranceX/mock_usdc
VAULT_DIR=~/ZK_InsuranceX/vault

echo "Waiting for devnet..."
until curl -s "$ENDPOINT/testnet/block/height/latest" 2>/dev/null | grep -qE '^[0-9]+$'; do
    sleep 2
    echo "  Waiting for devnet to start..."
done

height=$(curl -s "$ENDPOINT/testnet/block/height/latest")
while [ "$height" -lt 12 ]; do
    echo "  Block height: $height (waiting for 12)"
    sleep 2
    height=$(curl -s "$ENDPOINT/testnet/block/height/latest")
done
echo "Devnet ready! Height: $height"

echo ""
echo "=== 1. Deploying mock_usdc ==="
cd $MOCK_USDC_DIR
leo deploy $NETWORK $CONSENSUS --yes
sleep 3

echo ""
echo "=== 2. Deploying zk_insurancex ==="
cd $VAULT_DIR
leo deploy $NETWORK $CONSENSUS --yes
sleep 3

echo ""
echo "=== 3. Minting USDC to employer ==="
cd $MOCK_USDC_DIR
leo execute mint_public $EMPLOYER 10000000000u128 $NETWORK $CONSENSUS --yes
sleep 3

echo ""
echo "=== 4. Getting program address ==="
cd $VAULT_DIR
# Run dry-run to get program address from transfer_from call
PROGRAM_ADDR=$(leo run deposit_premium 1u128 1u64 2>&1 | grep -oP 'aleo1[a-z0-9]{58}' | head -4 | tail -1)
echo "Program address: $PROGRAM_ADDR"

echo ""
echo "=== 5. Approving zk_insurancex to spend USDC ==="
cd $MOCK_USDC_DIR
# Approve enough for deposits AND withdrawals (POOL needs to approve program for withdraw_benefit)
leo execute approve $PROGRAM_ADDR 10000000000u128 $NETWORK $CONSENSUS --yes
sleep 3

echo ""
echo "=== 6. Registering employer ==="
cd $VAULT_DIR
leo execute register_employer $EMPLOYER $NETWORK $CONSENSUS --yes
sleep 3

echo ""
echo "=== 7. Registering employee ==="
# Use start_block = 1 (employee started at block 1)
# This ensures work duration is always positive and large enough for eligibility
height=$(curl -s "$ENDPOINT/testnet/block/height/latest")
start_block=1
salary=5000000000  # 5000 USDC

echo "Current block: $height"
echo "Start block: $start_block (block 1 - long employment history)"
echo "Salary: $salary"

# Save output to extract records
leo execute register_employee $EMPLOYEE ${salary}u64 ${start_block}u64 $NETWORK $CONSENSUS --yes 2>&1 | tee /tmp/register_employee_output.txt

# Extract and save the actual records from output
echo ""
echo "Extracting records from output..."

# Create records directory
mkdir -p $VAULT_DIR/records

# Use Python to extract records reliably
python3 << 'PYEOF'
import re

with open('/tmp/register_employee_output.txt', 'r') as f:
    content = f.read()

# Find all records (text between { and })
# Records look like: { owner: ..., _version: 1u8.public }
pattern = r'\{[^{}]+\}'
matches = re.findall(pattern, content, re.DOTALL)

# Filter for Employment records (have owner, employer, employee fields)
employment_records = [m for m in matches if 'employer:' in m and 'employee:' in m and 'salary:' in m]

if len(employment_records) >= 2:
    # First is employer record, second is employee record
    employer_record = employment_records[0].replace('\n', ' ').replace('  ', ' ')
    employee_record = employment_records[1].replace('\n', ' ').replace('  ', ' ')
    
    with open('records/employer_employment.txt', 'w') as f:
        f.write(employer_record)
    
    with open('records/employee_employment.txt', 'w') as f:
        f.write(employee_record)
    
    print(f"Extracted {len(employment_records)} records")
else:
    print(f"WARNING: Found only {len(employment_records)} employment records")
    print("Available matches:", matches[:3] if matches else "none")
PYEOF

echo ""
echo "Employer record:"
cat $VAULT_DIR/records/employer_employment.txt
echo ""
echo ""
echo "Employee record:"
cat $VAULT_DIR/records/employee_employment.txt
echo ""
sleep 3

echo ""
echo "=== 8. Depositing premium (period 1) ==="
# Deposit enough to cover benefit withdrawals (at least 3500 USDC per month × 3 months = 10500 USDC)
leo execute deposit_premium 5000000000u128 1u64 $NETWORK $CONSENSUS --yes
sleep 3

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Check state:"
echo "  curl $ENDPOINT/testnet/program/$PROGRAM/mapping/employers/$EMPLOYER"
echo "  curl $ENDPOINT/testnet/program/$PROGRAM/mapping/employee_count/$EMPLOYER"
echo "  curl $ENDPOINT/testnet/program/$PROGRAM/mapping/pool_balance/0u8"
echo "  curl $ENDPOINT/testnet/program/mock_usdc.aleo/mapping/balances/$EMPLOYER"
echo ""
echo "Next: Run ./test_insurancex.sh"
