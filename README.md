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
    │      ┌─────┴─────┐           │
    │      ▼           ▼           │
    │ ┌────────┐ ┌──────────┐      │
    │ │Approved│ │ Reversed │      │
    │ │ type=4 │ │ (active) │      │
    │ └───┬────┘ └──────────┘      │
    │     │                        │
    ▼     ▼                        ▼
┌─────────────────────────────────────┐
│ Employment terminated               │
│ - employments[hash] = false         │
│ - employee_count decremented        │
│ - Can be re-hired in future         │
└─────────────────────────────────────┘
```

**Termination types:**
| Value | Status | Description |
|-------|--------|-------------|
| 0 | Active | Currently employed |
| 1 | Mutual | Both parties agreed to terminate |
| 2 | Employer-initiated | Pending employee response |
| 3 | Disputed | Employee disputed, pending UWV review |
| 4 | UWV-resolved | UWV made final decision |

## Benefit Calculation

Following Dutch WW system:
- **Benefit amount:** 70% of last monthly salary
- **No link to premiums paid:** Benefits are from collective pool, not individual savings

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
- [ ] Phase 5: Claims & Benefits
  - [ ] `submit_claim` - Employee submits unemployment claim
  - [ ] `approve_claim` - Validate eligibility
  - [ ] `withdraw_benefit` - Employee withdraws from pool

## Getting Started

### Prerequisites

- [Leo](https://developer.aleo.org/leo/) 
- [snarkOS](https://github.com/AleoHQ/snarkOS) (for local devnet)
- Mock USDC token deployed

### Build

```bash
leo build
```

### Local Devnet Setup

```bash
# 1. Start devnet
leo devnet --snarkos $(which snarkos) --snarkos-features test_network --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage

# 2. Deploy mock_usdc (in separate terminal)
cd mock_usdc
leo deploy --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# 3. Deploy zk_insurancex
cd ../vault
leo deploy --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
```

### Test Flow

```bash
# Register employer (admin only)
leo execute register_employer <employer_address> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Register employee (employer only)
leo execute register_employee <employee_address> <salary_u64> <start_block_u64> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Deposit premium
# Step 1: Mint USDC to employer
leo execute mock_usdc.aleo/mint_public <employer_address> 1000000000u128 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Step 2: Approve zk_insurancex program address to spend USDC
leo execute mock_usdc.aleo/approve <zk_insurancex_program_address> 540000000u128 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Step 3: Deposit premium (540 USDC for period 1)
leo execute deposit_premium 540000000u128 1u64 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Terminate employment (employer initiates)
leo execute terminate_initiate <employment_record> <current_block_u64> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Employee confirms termination
leo execute terminate_confirm <employment_record> <end_block_u64> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Employee disputes termination
leo execute terminate_dispute <employment_record> <current_block_u64> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# Finalize after deadline (anyone can call)
leo execute terminate_finalize <employer_address> <employee_address> <current_block_u64> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

# UWV resolves dispute (admin only)
leo execute terminate_uwv_resolve <employer_address> <employee_address> <approved_bool> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
```

### Check State

```bash
# Check employer registration
curl http://localhost:3030/testnet/program/zk_insurancex.aleo/mapping/employers/<employer_address>

# Check pool balance
curl http://localhost:3030/testnet/program/zk_insurancex.aleo/mapping/pool_balance/0u8

# Check employer premium total
curl http://localhost:3030/testnet/program/zk_insurancex.aleo/mapping/employer_premium_totals/<employer_address>
```

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `ADMIN` | configurable | UWV authority address |
| `POOL` | configurable | Pool address for premiums |
| `TERMINATION_RESPONSE_PERIOD` | 10 | ~10 blocks (testing) |
| `TERMINATION_RESPONSE_PERIOD` | 2592000 | ~30 days in blocks (production) |

## Token

Uses mock USDC token (6 decimals) for premium payments and benefit withdrawals.

- `mock_usdc.aleo/mint_public` - Mint tokens (admin only)
- `mock_usdc.aleo/approve` - Approve spender
- `mock_usdc.aleo/transfer_from` - Transfer on behalf (used by zk_insurancex)

## Future Enhancements

- [ ] Merkle tree for individual premium auditability
- [ ] Dual-signature model for undisputable records
- [ ] Cross-border portability
- [ ] Multiple benefit tiers

## License

MIT
