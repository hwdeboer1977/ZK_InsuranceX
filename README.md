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
┌─────────────────────────────────────────────────────────────────────────┐
│                           PUBLIC STATE (Mappings)                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │   employers     │  │ employee_count  │  │     employments         │  │
│  │ addr => bool    │  │ addr => u64     │  │ hash(emp,ee) => bool    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘  │
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐                               │
│  │ employer_totals │  │   pool_total    │  (future)                     │
│  │ addr => u64     │  │     u64         │                               │
│  └─────────────────┘  └─────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         PRIVATE STATE (Records)                          │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                      Employment Record                           │    │
│  │  owner: address           // employer OR employee holds copy     │    │
│  │  employer: address                                               │    │
│  │  employee: address                                               │    │
│  │  salary: u64              // monthly salary in USDC micro-units  │    │
│  │  start_block: u64                                                │    │
│  │  end_block: u64           // 0 if active                         │    │
│  │  is_active: bool                                                 │    │
│  │  termination_type: u8     // 0=active, 1=mutual, 2=fired, 3=UWV  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    PremiumReceipt Record (future)                │    │
│  │  owner: address           // employer holds                      │    │
│  │  employer: address                                               │    │
│  │  total_amount: u64                                               │    │
│  │  employee_count: u64                                             │    │
│  │  block_height: u64                                               │    │
│  │  merkle_root: field       // commitment to individual breakdown  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Termination Flow

**Mutual consent:** Both employer and employee present records → both updated → clean termination

**Employer fires:** Employer updates their record → employee can dispute to UWV → UWV resolves

```
termination_type values:
  0 = active (employed)
  1 = mutual (both agreed)
  2 = employer-initiated (may be disputed)
  3 = UWV-resolved
```

## Premium Payments (Batch Model)

To scale for large employers (10,000+ employees), premiums use a batch receipt model:

- **On-chain:** One `PremiumReceipt` per employer per month with merkle root
- **Off-chain:** Employer stores individual employee breakdown
- **Audit:** Merkle proofs verify individual payments when needed

This keeps individual premium data private while maintaining auditability.

## Benefit Calculation

Following Dutch WW system:
- **Benefit amount:** 70% of last monthly salary
- **No link to premiums paid:** Benefits are from collective pool, not individual savings

## Development Status

- [x] Employer registration (admin-controlled)
- [x] Employee registration (private records, dual copies)
- [ ] Premium deposits (batch receipts, USDC integration)
- [ ] Employment termination (mutual + disputed paths)
- [ ] Claim submission
- [ ] Claim approval / UWV dispute resolution
- [ ] Benefit withdrawals

## Getting Started

### Prerequisites

- [Leo](https://developer.aleo.org/leo/) 
- [snarkOS](https://github.com/AleoHQ/snarkOS) (for local devnet)

### Build

```bash
leo build
```

### Test locally

```bash
# Register employer (admin only)
leo run register_employer <employer_address>

# Register employee (employer only)
leo run register_employee <employee_address> <salary_u64> <start_block_u64>
```

### Deploy to devnet

```bash
leo deploy --network testnet --broadcast
```

## Token

Uses mock USDC token for premium payments and benefit withdrawals (deployed separately).

## License

MIT
