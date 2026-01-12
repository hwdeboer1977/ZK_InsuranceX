# ZK_InsuranceX

Private Unemployment Insurance Protocol on Aleo, inspired by the Dutch unemployment insurance system (WW - Werkloosheidswet).

## Overview

ZK_InsuranceX brings unemployment benefits on-chain with privacy-preserving design. Unlike the [EVM version](https://github.com/...), this implementation leverages Aleo's zero-knowledge architecture to keep sensitive employment data private while maintaining public transparency at the macro level.

## Privacy Model

| Data | Visibility | Rationale |
|------|------------|-----------|
| Employer registration | **Public** | Transparency — anyone can verify registered employers |
| Employee address | **Private** | Only employer + employee know the relationship |
| Salary | **Private** | Sensitive personal information |
| Start/end dates | **Private** | Employment history is confidential |
| Termination details | **Private** | Only parties involved see dispute status |
| Individual premiums | **Private** | Per-employee contributions not disclosed |
| Employer total premiums | **Public** | Macro-level transparency (like annual reports) |
| Employee count per employer | **Public** | Macro-level transparency |
| Total pool | **Public** | System solvency is transparent |
| Claim details | **Private** | Benefit amounts are confidential |

## Roles

- **Admin (UWV)** — The authority that registers employers and resolves termination disputes. Cannot see private employee data.
- **Employers** — Register employees, deposit premiums, initiate terminations.
- **Employees** — Hold private records of their employment, submit claims, withdraw benefits, can dispute terminations.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PUBLIC STATE (Mappings)                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │   employers     │  │ employee_count  │  │       employments           │  │
│  │ addr => bool    │  │ addr => u64     │  │ hash(employer,ee) => bool   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
│                                                                              │
│  ┌─────────────────────────┐  ┌─────────────────────────┐                   │
│  │  pending_terminations   │  │    premium_periods      │                   │
│  │  hash(emp,ee) => u64    │  │ hash(emp,period) => bool│                   │
│  │  (deadline block)       │  │ (paid yes/no)           │                   │
│  └─────────────────────────┘  └─────────────────────────┘                   │
│                                                                              │
│  ┌─────────────────────────┐  ┌─────────────────────────┐                   │
│  │ employer_premium_totals │  │      pool_balance       │                   │
│  │     addr => u128        │  │      0u8 => u128        │                   │
│  │  (running total)        │  │   (total USDC in pool)  │                   │
│  └─────────────────────────┘  └─────────────────────────┘                   │
│                                                                              │
│  ┌─────────────────────────┐  ┌─────────────────────────┐                   │
│  │        claims           │  │     active_claims       │                   │
│  │ hash(emp,ee,end) => bool│  │    addr => bool         │                   │
│  │  (claimed yes/no)       │  │  (has active claim)     │                   │
│  └─────────────────────────┘  └─────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         PRIVATE STATE (Records)                              │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      Employment Record                               │    │
│  │  owner: address           // employer OR employee holds copy         │    │
│  │  employer: address                                                   │    │
│  │  employee: address                                                   │    │
│  │  salary: u64              // monthly salary in USDC micro-units      │    │
│  │  start_block: u64                                                    │    │
│  │  end_block: u64           // 0 if active                             │    │
│  │  is_active: bool                                                     │    │
│  │  termination_type: u8     // 0=active, 1=mutual, 2=fired, 3=disputed │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      PremiumReceipt Record                           │    │
│  │  owner: address           // employer holds                          │    │
│  │  employer: address                                                   │    │
│  │  amount: u128             // USDC deposited (6 decimals)             │    │
│  │  period: u64              // period identifier (1, 2, 3...)          │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Claim Record                                 │    │
│  │  owner: address           // employee holds                          │    │
│  │  employee: address                                                   │    │
│  │  employer: address        // former employer (reference)             │    │
│  │  benefit_amount: u128     // 70% of salary per month                 │    │
│  │  total_months: u64        // total benefit months (3-24)             │    │
│  │  months_claimed: u64      // already withdrawn                       │    │
│  │  last_withdraw_block: u64 // for monthly tracking                    │    │
│  │  end_block: u64           // employment end (for uniqueness)         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Premium Deposit Flow

Employers deposit premiums monthly for all their employees:

```
┌─────────────────────────────────────────────────────────────────┐
│                    EMPLOYER'S HR SYSTEM (Off-chain)             │
│                                                                 │
│  Employee 1: Salary €3,000 → Premium €90 (3%)                   │
│  Employee 2: Salary €4,000 → Premium €120 (3%)                  │
│  Employee 3: Salary €5,000 → Premium €150 (3%)                  │
│  Employee 4: Salary €6,000 → Premium €180 (3%)                  │
│  ─────────────────────────────────────────────                  │
│  Total: €540                                                    │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ON-CHAIN                                │
│                                                                 │
│  1. Employer approves zk_insurancex to spend USDC               │
│     mock_usdc.aleo/approve(<program_address>, 540000000u128)    │
│                                                                 │
│  2. Employer deposits premium                                   │
│     deposit_premium(540000000u128, 1u64)                        │
│     - Pulls USDC from employer via transfer_from                │
│     - Updates employer_premium_totals                           │
│     - Updates pool_balance                                      │
│     - Marks period as paid                                      │
│     - Returns PremiumReceipt to employer                        │
└─────────────────────────────────────────────────────────────────┘
```

**Multiple employers, multiple periods:**

| Employer | Period | Amount | Pool After |
|----------|--------|--------|------------|
| Employer A | 1 | 540 USDC | 540 USDC |
| Employer B | 1 | 1,200 USDC | 1,740 USDC |
| Employer A | 2 | 540 USDC | 2,280 USDC |
| Employer C | 1 | 300 USDC | 2,580 USDC |

## Termination Flow

```
┌──────────────────┐
│ Active Employment │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────┐
│ 1. Employer calls terminate_initiate │
│    - Employer record updated     │
│    - Deadline set in mapping     │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ Employee has X blocks to respond │
│ (TERMINATION_RESPONSE_PERIOD)    │
└────────┬─────────────────────────┘
         │
    ┌────┴────┬────────────┐
    ▼         ▼            ▼
┌────────┐ ┌────────┐ ┌──────────────┐
│Confirm │ │Dispute │ │ No response  │
│        │ │        │ │              │
└───┬────┘ └───┬────┘ └──────┬───────┘
    │          │             │
    ▼          ▼             ▼
┌────────┐ ┌────────────┐ ┌──────────────────┐
│ Mutual │ │ UWV Review │ │ Anyone calls     │
│ type=1 │ │ type=3     │ │ terminate_finalize│
└───┬────┘ └─────┬──────┘ └────────┬─────────┘
    │            │                 │
    ▼            ▼                 ▼
  ✅ Can       ❌ Wait         ✅ Can
  Claim        for UWV         Claim
               Approval        (type=2)
```

## Claims & Benefits Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      SUBMIT CLAIM                               │
│                                                                 │
│  Employee calls submit_claim with terminated Employment record  │
│                                                                 │
│  Validations:                                                   │
│  - Employment must be terminated (is_active = false)            │
│  - Termination type must be 1, 2, or 4 (not disputed)           │
│  - Employee must have worked MIN_WORK_DURATION (26 weeks)       │
│  - No existing claim for this employment                        │
│                                                                 │
│  Benefit calculation:                                           │
│  - Amount: 70% of monthly salary                                │
│  - Duration: 3 + years_worked months (max 24)                   │
│                                                                 │
│  Returns: Claim record to employee                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     WITHDRAW BENEFIT                            │
│                                                                 │
│  Employee calls withdraw_benefit with Claim record              │
│                                                                 │
│  Validations:                                                   │
│  - Must wait BLOCKS_PER_MONTH since last withdrawal             │
│  - months_claimed < total_months                                │
│  - Pool must have sufficient balance                            │
│                                                                 │
│  Actions:                                                       │
│  - Transfers benefit_amount USDC from POOL to employee          │
│  - Decreases pool_balance                                       │
│  - Updates Claim record (months_claimed++)                      │
│  - If final month: sets active_claims to false                  │
│                                                                 │
│  Returns: Updated Claim record                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Benefit Duration Calculation (Dutch WW rules):**

| Work Duration | Benefit Months |
|---------------|----------------|
| < 26 weeks | NOT eligible |
| 26 weeks - 1 year | 3 months |
| 1-2 years | 4 months |
| 2-3 years | 5 months |
| 5 years | 8 months |
| 10 years | 13 months |
| 21+ years | 24 months (max) |

**Formula:** `benefit_months = 3 + years_worked` (capped at 24)

**Eligible Termination Types for Claims:**

| Type | Description | Can Claim? |
|------|-------------|------------|
| 0 | Active | ❌ No |
| 1 | Mutual | ✅ Yes |
| 2 | Employer-initiated (finalized) | ✅ Yes |
| 3 | Disputed (pending UWV) | ❌ No |
| 4 | UWV-resolved | ✅ Yes |

## Benefit Calculation

Following Dutch WW system:
- **Benefit amount:** 70% of last monthly salary
- **No link to premiums paid:** Benefits are from collective pool, not individual savings
- **Duration:** Based on work history (3-24 months)

## Development Status

- [x] Phase 1: Employer registration (admin-controlled)
- [x] Phase 2: Employee registration (private records, dual copies)
- [x] Phase 3: Employment termination
  - [x] `terminate_initiate` - Employer initiates
  - [x] `terminate_confirm` - Employee confirms (mutual)
  - [x] `terminate_dispute` - Employee disputes to UWV
  - [x] `terminate_finalize` - Auto-finalize after deadline
  - [x] `terminate_uwv_resolve` - UWV resolves dispute
- [x] Phase 4: Premium deposits
  - [x] `deposit_premium` - Employer deposits monthly premium
  - [x] USDC integration via `transfer_from`
  - [x] Pool balance tracking
  - [x] Period tracking (prevent double payment)
- [x] Phase 5: Claims & Benefits
  - [x] `submit_claim` - Employee submits unemployment claim
  - [x] Automatic eligibility validation (no manual approval)
  - [x] Benefit calculation (70% salary, 3-24 months)
  - [x] `withdraw_benefit` - Employee withdraws monthly from pool

## Getting Started

### Prerequisites

- [Leo](https://developer.aleo.org/leo/) 
- [snarkOS](https://github.com/AleoHQ/snarkOS) (for local devnet)
- Python 3 (for test scripts)
- Mock USDC token deployed

### Build

```bash
leo build
```

### Quick Start with Test Scripts

The easiest way to test the full flow is using the automated test scripts:

```bash
# Terminal 1: Start devnet
leo devnet --snarkos $(which snarkos) --snarkos-features test_network \
  --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage

# Terminal 2: Run setup and test
chmod +x setup_insurancex.sh test_insurancex.sh
./setup_insurancex.sh    # Deploy contracts, register employer/employee, deposit premium
./test_insurancex.sh     # Run full termination → claim → withdrawal flow
```

### What the Scripts Do

**`setup_insurancex.sh`** - Initial deployment and setup:
1. Waits for devnet to be ready (12+ blocks)
2. Deploys `mock_usdc.aleo`
3. Deploys `zk_insurancex_v1.aleo`
4. Mints 10,000 USDC to employer
5. Gets program address and approves USDC spending
6. Registers employer with admin
7. Registers employee (salary: 5000 USDC, start_block: 1)
8. Deposits 5000 USDC premium to pool
9. Saves employment records to `records/` directory

**`test_insurancex.sh`** - Full claims flow:
1. **Employer initiates termination** - Creates pending termination
2. **Wait 12 blocks** - Response period passes
3. **Employee confirms termination** - Employment ends (type=1 mutual)
4. **Employee submits claim** - Creates Claim record (70% × 5000 = 3500 USDC/month)
5. **Wait 105 blocks** - First month passes
6. **Employee withdraws benefit** - Receives 3500 USDC from pool
7. **Summary** - Shows pool balance, employee balance, claim status

### Manual Testing

For manual testing or custom scenarios:

```bash
# Register employer (admin only)
leo execute register_employer <employer_address> --network testnet --broadcast \
  --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Register employee (employer only)
leo execute register_employee <employee_address> <salary_u64> <start_block_u64> \
  --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Deposit premium
# Step 1: Mint USDC to employer
leo execute mock_usdc.aleo/mint_public <employer_address> 10000000000u128 \
  --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Step 2: Approve zk_insurancex program address to spend USDC
leo execute mock_usdc.aleo/approve <zk_insurancex_program_address> 10000000000u128 \
  --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Step 3: Deposit premium (5000 USDC for period 1)
leo execute deposit_premium 5000000000u128 1u64 --network testnet --broadcast \
  --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Terminate employment (employer initiates)
leo execute terminate_initiate <employment_record> <current_block_u64> \
  --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Employee confirms termination
leo execute terminate_confirm <employment_record> <end_block_u64> \
  --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Submit claim (after termination)
leo execute submit_claim <terminated_employment_record> --network testnet --broadcast \
  --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Withdraw monthly benefit
leo execute withdraw_benefit <claim_record> <current_block_u64> --network testnet --broadcast \
  --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
```

### Check State

```bash
# Check employer registration
curl http://localhost:3030/testnet/program/zk_insurancex_v1.aleo/mapping/employers/<employer_address>

# Check employee count
curl http://localhost:3030/testnet/program/zk_insurancex_v1.aleo/mapping/employee_count/<employer_address>

# Check pool balance
curl http://localhost:3030/testnet/program/zk_insurancex_v1.aleo/mapping/pool_balance/0u8

# Check employer premium total
curl http://localhost:3030/testnet/program/zk_insurancex_v1.aleo/mapping/employer_premium_totals/<employer_address>

# Check USDC balance
curl http://localhost:3030/testnet/program/mock_usdc.aleo/mapping/balances/<address>

# Check if employee has active claim
curl http://localhost:3030/testnet/program/zk_insurancex_v1.aleo/mapping/active_claims/<employee_address>
```

## Constants

| Constant | Value (Testing) | Value (Production) | Description |
|----------|-----------------|-------------------|-------------|
| `ADMIN` | configurable | configurable | UWV authority address |
| `POOL` | configurable | configurable | Pool address for premiums |
| `TERMINATION_RESPONSE_PERIOD` | 10 | 2,592,000 | Response period (~10 blocks / ~30 days) |
| `BLOCKS_PER_MONTH` | 100 | 2,592,000 | Blocks per month (~100 / ~30 days) |
| `BLOCKS_PER_YEAR` | 1,200 | 31,536,000 | Blocks per year |
| `MIN_WORK_DURATION` | 10 | 15,724,800 | Minimum work duration (~10 blocks / 26 weeks) |
| `MIN_BENEFIT_MONTHS` | 3 | 3 | Minimum benefit duration |
| `MAX_BENEFIT_MONTHS` | 24 | 24 | Maximum benefit duration |
| `BENEFIT_PERCENTAGE` | 70 | 70 | 70% of salary |

## Token

Uses mock USDC token (6 decimals) for premium payments and benefit withdrawals.

- `mock_usdc.aleo/mint_public` - Mint tokens (admin only)
- `mock_usdc.aleo/approve` - Approve spender
- `mock_usdc.aleo/transfer_from` - Transfer on behalf (used by deposit_premium and withdraw_benefit)
- `mock_usdc.aleo/transfer_public` - Direct transfer

## Project Structure

```
ZK_InsuranceX/
├── vault/
│   ├── src/
│   │   └── main.leo           # Main contract
│   ├── records/               # Generated employment records (after setup)
│   ├── program.json
│   └── .env                   # Private keys for testing
├── mock_usdc/
│   ├── src/
│   │   └── main.leo           # Mock USDC token
│   └── program.json
├── setup_insurancex.sh        # Automated setup script
├── test_insurancex.sh         # Automated test script
└── README.md
```

## Troubleshooting

**"Input record must belong to the signer"**
- Make sure you're using the correct private key for the record owner
- Employee records need employee's private key, employer records need employer's private key

**"Failed to parse input" or "Parsing requires 1 bytes/chars"**
- Record extraction failed. Check that the previous step completed successfully
- Records must be single-line format with proper nonce and version fields

**"Transaction rejected" on withdraw_benefit**
- Pool balance might be insufficient (pool needs >= benefit_amount)
- Increase premium deposit in setup script

**"assert.eq failed" on submit_claim**
- Check MIN_WORK_DURATION - employee needs to have worked long enough
- For testing, reduce MIN_WORK_DURATION to 10 blocks

## Future Enhancements

- [ ] Merkle tree for individual premium auditability
- [ ] Dual-signature model for undisputable records
- [ ] Cross-border portability
- [ ] Multiple benefit tiers
- [ ] Re-employment tracking (stop benefits when new job starts)
- [ ] Multi-sig pool management
- [ ] Partial benefit claims

## License

MIT
