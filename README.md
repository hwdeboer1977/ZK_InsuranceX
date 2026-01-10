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
| Individual premiums | **Private** | Per-employee contributions not disclosed |
| Employer total premiums | **Public** | Macro-level transparency (like annual reports) |
| Total pool | **Public** | System solvency is transparent |

## Roles

- **Admin (UWV)** — The authority that registers employers. Cannot see private employee data.
- **Employers** — Register employees, deposit premiums, confirm terminations.
- **Employees** — Hold private records of their employment, submit claims, withdraw benefits.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PUBLIC STATE                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   employers     │  │ employer_totals │  │   pool_total    │  │
│  │ addr => bool    │  │ addr => u64     │  │     u64         │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       PRIVATE STATE                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   Employee Record                        │    │
│  │  owner: address (employee)                               │    │
│  │  employer: address                                       │    │
│  │  salary: u64                                             │    │
│  │  start_date: u64                                         │    │
│  │  end_date: u64                                           │    │
│  │  premiums_paid: u64                                      │    │
│  │  is_active: bool                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Flow

1. **Admin registers employer** → `register_employer(employer_address)`
2. **Employer registers employee** → Employee receives private record
3. **Employer deposits premium** → Private record updated, public totals increase
4. **Employer terminates employment** → Private record updated (end_date set)
5. **Employee submits claim** → Claim created with pending status
6. **Claim approved** → Via employer confirmation or auto-approval
7. **Employee withdraws benefits** → Monthly withdrawals from pool

## Development Status

- [x] Employer registration (admin-controlled)
- [ ] Employee registration (private records)
- [ ] Premium deposits (USDC integration)
- [ ] Employment termination
- [ ] Claim submission
- [ ] Claim approval
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
leo run register_employer <employer_address>
```

### Deploy to devnet

```bash
leo deploy --network testnet --broadcast
```

## Token

Uses mock USDC token for premium payments and benefit withdrawals (deployed separately).

## License

MIT
