// ZK_InsuranceX - Private Unemployment Insurance Protocol
// Phase 1: Employer Registration
// Phase 2: Employee Registration
// Phase 3: Employment Termination
// Phase 4: Premium Deposits

// TESTNET
// 1. leo build
// 2. leo deploy --network testnet --broadcast


// DEVNET alternative 1
// 1. leo build
// 2. leo devnet --snarkos $(which snarkos) --snarkos-features test_network --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage
// 3. Deploy mock_usdc first, then zk_insurancex
// 4. leo execute register_employer aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 5. CHECK: curl http://localhost:3030/testnet/program/zk_insurancex.aleo/mapping/employers/aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px
// 6. leo execute register_employee aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px 5000000000u64 1000u64 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 7. leo execute terminate_initiate <EMP> <BLOCK> --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
//
// PREMIUM DEPOSIT FLOW:
// 1. Mint USDC: leo execute mock_usdc.aleo/mint_public <employer> 1000000000u128 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 2. Approve: leo execute mock_usdc.aleo/approve zk_insurancex.aleo <program address> 500000000u128 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 3. Deposit: leo execute deposit_premium 540000000u128 1u64 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11

import mock_usdc.aleo;

program zk_insurancex.aleo {

    // The constructor is configured to prevent upgrades.
    @noupgrade
    async constructor() {}

    // The admin address (UWV authority)
    // const ADMIN: address = aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0; // Testnet
    const ADMIN: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px; // Devnet

    // Pool address - where premiums are collected
    // In production, this could be a multi-sig or the program itself
    const POOL: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px; // Same as admin for testing

    // Termination response period in blocks (~10 blocks for testing)
    const TERMINATION_RESPONSE_PERIOD: u64 = 10u64;
    // const TERMINATION_RESPONSE_PERIOD: u64 = 86400u64;    // ~1 day
    // const TERMINATION_RESPONSE_PERIOD: u64 = 2592000u64;  // ~30 days (production)
    
    // Termination types
    // 0 = active (employed)
    // 1 = mutual (both agreed)
    // 2 = employer-initiated (pending employee response)
    // 3 = disputed (pending UWV review)
    // 4 = UWV-resolved

    // ============================================
    // STRUCTS
    // ============================================

    // Simple struct for hashing employer-employee pairs
    // Used to create unique keys for mappings
    struct EmploymentKey {
        employer: address,
        employee: address,
    }

    // Struct for hashing employer-period pairs (premium tracking)
    struct PremiumKey {
        employer: address,
        period: u64,
    }

    // ============================================
    // RECORDS
    // ============================================
    
    // Private employment record - held by both employer and employee
    record Employment {
        owner: address,           // Who holds this record (employer or employee)
        employer: address,        // The employer
        employee: address,        // The employee
        salary: u64,              // Monthly salary in USDC micro-units
        start_block: u64,         // Block height when registered
        end_block: u64,           // 0 if active, block height if terminated
        is_active: bool,          // Currently employed?
        termination_type: u8,     // 0 = active, 1 = mutual, 2 = employer-initiated, 3 = UWV-resolved
    }

    // Premium receipt - proof of payment for employer
    record PremiumReceipt {
        owner: address,           // Employer
        employer: address,        // Same as owner
        amount: u128,             // USDC amount deposited
        period: u64,              // Period identifier (1, 2, 3...)
    }

    // ============================================
    // MAPPINGS
    // ============================================
    
    // MAPPING is PUBLIC - visible to everyone on-chain
    // Aleo model: private computation in transitions, public state changes in finalize.
    // Tracks registered employers: employer_address => is_registered
    mapping employers: address => bool;
    
    // Tracks active employments: hash(employer, employee) => is_active
    mapping employments: field => bool;  // true = active, false = not active (can re-hire)
    
    // Tracks employee count per employer: employer_address => count
    mapping employee_count: address => u64;
    
    // Tracks pending terminations: hash(employer, employee) => deadline_block
    mapping pending_terminations: field => u64;

    // Premium tracking
    // Total premiums deposited per employer (running total)
    mapping employer_premium_totals: address => u128;
    
    // Track which periods have been paid: hash(employer, period) => paid
    mapping premium_periods: field => bool;
    
    // Total pool balance
    mapping pool_balance: u8 => u128;  // 0u8 => total USDC in pool

    // ============================================
    // TRANSITIONS
    // ============================================
    
    // Register an employer (admin only)
    // Only the UWV authority can register employers
    async transition register_employer(employer: address) -> Future {
        // Only admin can register employers
        assert_eq(self.caller, ADMIN);
        
        return finalize_register_employer(employer);
    }
    
    async function finalize_register_employer(employer: address) {
        // Check if already registered
        let already_registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(!already_registered); // Cannot register twice
        
        // Register the employer
        Mapping::set(employers, employer, true);
    }
    
    // Register an employee (employer only)
    // Creates two Employment records: one for employer, one for employee
    async transition register_employee(
        employee: address,
        salary: u64,
        start_block: u64
    ) -> (Employment, Employment, Future) {
        let employer: address = self.caller;
        
        // Create employment record for employer
        let employer_record: Employment = Employment {
            owner: employer,
            employer: employer,
            employee: employee,
            salary: salary,
            start_block: start_block,
            end_block: 0u64,           
            is_active: true,
            termination_type: 0u8,     
        };
        
        // Create employment record for employee
        let employee_record: Employment = Employment {
            owner: employee,
            employer: employer,
            employee: employee,
            salary: salary,
            start_block: start_block,
            end_block: 0u64,           
            is_active: true,
            termination_type: 0u8,    
        };
        
        // Compute hash using EmploymentKey struct
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: employer,
            employee: employee,
        });
        
        return (employer_record, employee_record, finalize_register_employee(employer, employment_hash));
    }
    
    async function finalize_register_employee(employer: address, employment_hash: field) {
        // Check employer is registered
        let employer_registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(employer_registered);
        
        // Check employment doesn't already exist (no duplicates)
        let already_exists: bool = Mapping::get_or_use(employments, employment_hash, false);
        assert(!already_exists);
        
        // Register the employment
        Mapping::set(employments, employment_hash, true);
        
        // Increment employee count for this employer
        let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
        Mapping::set(employee_count, employer, current_count + 1u64);
    }

    // ============================================
    // TERMINATION TRANSITIONS
    // ============================================
    
    // Employer initiates termination
    // Consumes employer's record, outputs updated record with termination pending
    // Employee has TERMINATION_RESPONSE_PERIOD blocks to confirm or dispute
    async transition terminate_initiate(
        emp: Employment,
        current_block: u64
    ) -> (Employment, Future) {
        // Only employer can initiate
        assert_eq(self.caller, emp.employer);
        assert_eq(emp.owner, emp.employer);
        assert(emp.is_active);
        
        // Create updated employer record
        let updated_record: Employment = Employment {
            owner: emp.employer,
            employer: emp.employer,
            employee: emp.employee,
            salary: emp.salary,
            start_block: emp.start_block,
            end_block: current_block,
            is_active: false,
            termination_type: 2u8,  // employer-initiated
        };
        
        // Compute employment hash using EmploymentKey struct
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: emp.employer,
            employee: emp.employee,
        });
        
        let deadline: u64 = current_block + TERMINATION_RESPONSE_PERIOD;
        
        return (updated_record, finalize_terminate_initiate(employment_hash, deadline));
    }
    
    async function finalize_terminate_initiate(employment_hash: field, deadline: u64) {
        // Check employment exists and is active
        let is_active: bool = Mapping::get_or_use(employments, employment_hash, false);
        assert(is_active);
        
        // Check no pending termination already exists
        let existing_deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert_eq(existing_deadline, 0u64);
        
        // Set pending termination with deadline
        Mapping::set(pending_terminations, employment_hash, deadline);
    }

    // Employee confirms termination (mutual agreement)
    // Consumes employee's record, outputs updated record
    // Finalizes the termination: sets employment to inactive, decrements count
    async transition terminate_confirm(
        emp: Employment,
        end_block: u64
    ) -> (Employment, Future) {
        // Only employee can confirm
        assert_eq(self.caller, emp.employee);
        assert_eq(emp.owner, emp.employee);
        assert(emp.is_active);  // Employee's record still shows active
        
        // Create updated employee record
        let updated_record: Employment = Employment {
            owner: emp.employee,
            employer: emp.employer,
            employee: emp.employee,
            salary: emp.salary,
            start_block: emp.start_block,
            end_block: end_block,
            is_active: false,
            termination_type: 1u8,  // mutual agreement
        };
        
        // Compute employment hash using EmploymentKey struct
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: emp.employer,
            employee: emp.employee,
        });
        
        return (updated_record, finalize_terminate_confirm(employment_hash, emp.employer));
    }
    
    async function finalize_terminate_confirm(employment_hash: field, employer: address) {
        // Check pending termination exists
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);  // Must have pending termination
        
        // Set employment to inactive
        Mapping::set(employments, employment_hash, false);
        
        // Clear pending termination
        Mapping::set(pending_terminations, employment_hash, 0u64);
        
        // Decrement employee count
        let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
        Mapping::set(employee_count, employer, current_count - 1u64);
    }
    
    // Employee disputes termination (escalates to UWV)
    // Consumes employee's record, outputs updated record with disputed status
    async transition terminate_dispute(
        emp: Employment,
        current_block: u64
    ) -> (Employment, Future) {
        // Only employee can dispute
        assert_eq(self.caller, emp.employee);
        assert_eq(emp.owner, emp.employee);
        assert(emp.is_active);  // Employee's record still shows active
        
        // Create updated employee record with disputed status
        let updated_record: Employment = Employment {
            owner: emp.employee,
            employer: emp.employer,
            employee: emp.employee,
            salary: emp.salary,
            start_block: emp.start_block,
            end_block: current_block,
            is_active: false,
            termination_type: 3u8,  // disputed, pending UWV
        };
        
        // Compute employment hash using EmploymentKey struct
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: emp.employer,
            employee: emp.employee,
        });
        
        return (updated_record, finalize_terminate_dispute(employment_hash));
    }
    
    async function finalize_terminate_dispute(employment_hash: field) {
        // Check pending termination exists
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);  // Must have pending termination
        
        // Keep employment active until UWV resolves
        // Keep pending_terminations entry to indicate dispute in progress
        // UWV will resolve via terminate_uwv_resolve
    }
    
    // Anyone can finalize termination after deadline passes (no employee response)
    // This completes the termination if employee didn't confirm or dispute in time
    async transition terminate_finalize(
        employer: address,
        employee: address,
        current_block: u64
    ) -> Future {
        // Compute employment hash using EmploymentKey struct
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: employer,
            employee: employee,
        });
        
        return finalize_terminate_finalize(employment_hash, employer, current_block);
    }
    
    async function finalize_terminate_finalize(employment_hash: field, employer: address, current_block: u64) {
        // Check pending termination exists
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);  // Must have pending termination
        
        // Check deadline has passed
        assert(current_block >= deadline);
        
        // Set employment to inactive
        Mapping::set(employments, employment_hash, false);
        
        // Clear pending termination
        Mapping::set(pending_terminations, employment_hash, 0u64);
        
        // Decrement employee count
        let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
        Mapping::set(employee_count, employer, current_count - 1u64);
    }
    
    // UWV resolves a disputed termination
    // Admin only - decides if termination stands or is reversed
    async transition terminate_uwv_resolve(
        employer: address,
        employee: address,
        approved: bool  // true = termination approved, false = reversed (employee stays)
    ) -> Future {
        // Only admin (UWV) can resolve disputes
        assert_eq(self.caller, ADMIN);
        
        // Compute employment hash using EmploymentKey struct
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: employer,
            employee: employee,
        });
        
        return finalize_terminate_uwv_resolve(employment_hash, employer, approved);
    }
    
    async function finalize_terminate_uwv_resolve(employment_hash: field, employer: address, approved: bool) {
        // Check pending termination exists (dispute in progress)
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);
        
        // Clear pending termination
        Mapping::set(pending_terminations, employment_hash, 0u64);
        
        if approved {
            // Termination approved - finalize it
            Mapping::set(employments, employment_hash, false);
            
            // Decrement employee count
            let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
            Mapping::set(employee_count, employer, current_count - 1u64);
        } else {
            // Termination reversed - employment continues
            // employments mapping stays true (active)
            // Employee count unchanged
        }
    }    

    // ============================================
    // PREMIUM DEPOSIT TRANSITIONS
    // ============================================

    // Employer deposits premium for a period
    // Requires prior approval: mock_usdc.aleo/approve(zk_insurancex.aleo, amount)
    // Flow:
    //   1. Employer calculates total premium off-chain (sum of 3% × salary for all employees)
    //   2. Employer approves zk_insurancex to spend USDC
    //   3. Employer calls deposit_premium(amount, period)
    //   4. Contract pulls USDC from employer to pool
    async transition deposit_premium(
        public amount: u128,      // Total USDC amount (6 decimals)
        public period: u64        // Period identifier (1, 2, 3...)
    ) -> (PremiumReceipt, Future) {
        let employer: address = self.caller;
        
        // Amount must be positive
        assert(amount > 0u128);
        
        // Create receipt for employer
        let receipt: PremiumReceipt = PremiumReceipt {
            owner: employer,
            employer: employer,
            amount: amount,
            period: period,
        };
        
        // Compute premium period key
        let period_key: field = BHP256::hash_to_field(PremiumKey {
            employer: employer,
            period: period,
        });
        
        // Call mock_usdc to transfer from employer to pool
        let transfer_future: Future = mock_usdc.aleo/transfer_from(employer, POOL, amount);
        
        return (receipt, finalize_deposit_premium(employer, amount, period_key, transfer_future));
    }
    
    async function finalize_deposit_premium(
        employer: address, 
        amount: u128, 
        period_key: field,
        transfer_future: Future
    ) {
        // Await the USDC transfer
        transfer_future.await();
        
        // Check employer is registered
        let employer_registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(employer_registered);
        
        // Check period not already paid
        let already_paid: bool = Mapping::get_or_use(premium_periods, period_key, false);
        assert(!already_paid);
        
        // Mark period as paid
        Mapping::set(premium_periods, period_key, true);
        
        // Update employer's running total
        let current_total: u128 = Mapping::get_or_use(employer_premium_totals, employer, 0u128);
        Mapping::set(employer_premium_totals, employer, current_total + amount);
        
        // Update pool balance
        let current_pool: u128 = Mapping::get_or_use(pool_balance, 0u8, 0u128);
        Mapping::set(pool_balance, 0u8, current_pool + amount);
    }

}
