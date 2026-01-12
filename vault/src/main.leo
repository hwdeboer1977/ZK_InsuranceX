// ZK_InsuranceX - Private Unemployment Insurance Protocol
// Phase 1: Employer Registration
// Phase 2: Employee Registration
// Phase 3: Employment Termination
// Phase 4: Premium Deposits
// Phase 5: Claims & Benefits

// TESTNET
// 1. leo build
// 2. leo deploy --network testnet --broadcast


// DEVNET alternative 1
// 1. leo build
// 2. leo devnet --snarkos $(which snarkos) --snarkos-features test_network --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage
// Check 

import mock_usdc.aleo;

program zk_insurancex_v1.aleo {

    // The constructor is configured to prevent upgrades.
    @noupgrade
    async constructor() {}

    // ============================================
    // CONSTANTS
    // ============================================

    // The admin address (UWV authority)
    // const ADMIN: address = aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0; // Testnet
    const ADMIN: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px; // Devnet

    // Pool address - where premiums are collected
    // In production, this could be a multi-sig or the program itself
    const POOL: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px; // Same as admin for testing

    // Termination response period in blocks
    const TERMINATION_RESPONSE_PERIOD: u64 = 10u64;           // ~10 blocks (testing)
    // const TERMINATION_RESPONSE_PERIOD: u64 = 2592000u64;   // ~30 days (production)
    
    // Benefit calculation constants
    // For testing, use smaller values. For production, use real block times.
    const BLOCKS_PER_MONTH: u64 = 10u64;                     // Testing: 10 blocks 
    // const BLOCKS_PER_MONTH: u64 = 2592000u64;              // Production: ~30 days
    const BLOCKS_PER_YEAR: u64 = 1200u64;                     // Testing: 1200 blocks = 1 year
    // const BLOCKS_PER_YEAR: u64 = 31536000u64;              // Production: ~365 days
    const MIN_WORK_DURATION: u64 = 10u64;                     // Testing: 10 blocks for easy testing
    // const MIN_WORK_DURATION: u64 = 600u64;                  // Testing: 600 blocks = 26 weeks
    // const MIN_WORK_DURATION: u64 = 15724800u64;            // Production: 26 weeks
    
    const MIN_BENEFIT_MONTHS: u64 = 3u64;                     // Minimum 3 months benefit
    const MAX_BENEFIT_MONTHS: u64 = 24u64;                    // Maximum 24 months benefit
    const BENEFIT_PERCENTAGE: u64 = 70u64;                    // 70% of salary

    // Termination types
    // 0 = active (employed)
    // 1 = mutual (both agreed)
    // 2 = employer-initiated (finalized after deadline)
    // 3 = disputed (pending UWV review) - NOT eligible for benefits
    // 4 = UWV-resolved

    // ============================================
    // STRUCTS
    // ============================================

    // Simple struct for hashing employer-employee pairs
    struct EmploymentKey {
        employer: address,
        employee: address,
    }

    // Struct for hashing employer-period pairs (premium tracking)
    struct PremiumKey {
        employer: address,
        period: u64,
    }

    // Struct for hashing claim keys
    struct ClaimKey {
        employer: address,
        employee: address,
        end_block: u64,
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
        termination_type: u8,     // 0 = active, 1 = mutual, 2 = employer-initiated, 3 = disputed, 4 = UWV-resolved
    }

    // Premium receipt - proof of payment for employer
    record PremiumReceipt {
        owner: address,           // Employer
        employer: address,        // Same as owner
        amount: u128,             // USDC amount deposited
        period: u64,              // Period identifier (1, 2, 3...)
    }

    // Claim record - held by employee after submitting claim
    record Claim {
        owner: address,           // Employee
        employee: address,        // Same as owner
        employer: address,        // Former employer (for reference)
        benefit_amount: u128,     // 70% of monthly salary (USDC, 6 decimals)
        total_months: u64,        // Total months of benefit eligibility
        months_claimed: u64,      // Months already withdrawn
        last_withdraw_block: u64, // Block of last withdrawal (for monthly tracking)
        end_block: u64,           // Employment end block (for claim uniqueness)
    }

    // ============================================
    // MAPPINGS
    // ============================================
    
    // Employer registration
    mapping employers: address => bool;
    
    // Employment tracking
    mapping employments: field => bool;           // hash(employer, employee) => is_active
    mapping employee_count: address => u64;       // employer => count
    mapping pending_terminations: field => u64;   // hash(employer, employee) => deadline_block

    // Premium tracking
    mapping employer_premium_totals: address => u128;  // employer => running total
    mapping premium_periods: field => bool;            // hash(employer, period) => paid
    mapping pool_balance: u8 => u128;                  // 0u8 => total USDC in pool

    // Claim tracking
    mapping claims: field => bool;                // hash(employer, employee, end_block) => claimed
    mapping active_claims: address => bool;       // employee => has active claim

    // ============================================
    // TRANSITIONS: EMPLOYER REGISTRATION
    // ============================================
    
    // Register an employer (admin only)
    async transition register_employer(employer: address) -> Future {
        assert_eq(self.caller, ADMIN);
        return finalize_register_employer(employer);
    }
    
    async function finalize_register_employer(employer: address) {
        let already_registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(!already_registered);
        Mapping::set(employers, employer, true);
    }
    
    // ============================================
    // TRANSITIONS: EMPLOYEE REGISTRATION
    // ============================================
    
    // Register an employee (employer only)
    async transition register_employee(
        employee: address,
        salary: u64,
        start_block: u64
    ) -> (Employment, Employment, Future) {
        let employer: address = self.caller;
        
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
        
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: employer,
            employee: employee,
        });
        
        return (employer_record, employee_record, finalize_register_employee(employer, employment_hash));
    }
    
    async function finalize_register_employee(employer: address, employment_hash: field) {
        let employer_registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(employer_registered);
        
        let already_exists: bool = Mapping::get_or_use(employments, employment_hash, false);
        assert(!already_exists);
        
        Mapping::set(employments, employment_hash, true);
        
        let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
        Mapping::set(employee_count, employer, current_count + 1u64);
    }

    // ============================================
    // TRANSITIONS: TERMINATION
    // ============================================
    
    // Employer initiates termination
    async transition terminate_initiate(
        emp: Employment,
        current_block: u64
    ) -> (Employment, Future) {
        assert_eq(self.caller, emp.employer);
        assert_eq(emp.owner, emp.employer);
        assert(emp.is_active);
        
        let updated_record: Employment = Employment {
            owner: emp.employer,
            employer: emp.employer,
            employee: emp.employee,
            salary: emp.salary,
            start_block: emp.start_block,
            end_block: current_block,
            is_active: false,
            termination_type: 2u8,
        };
        
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: emp.employer,
            employee: emp.employee,
        });
        
        let deadline: u64 = current_block + TERMINATION_RESPONSE_PERIOD;
        
        return (updated_record, finalize_terminate_initiate(employment_hash, deadline));
    }
    
    async function finalize_terminate_initiate(employment_hash: field, deadline: u64) {
        let is_active: bool = Mapping::get_or_use(employments, employment_hash, false);
        assert(is_active);
        
        let existing_deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert_eq(existing_deadline, 0u64);
        
        Mapping::set(pending_terminations, employment_hash, deadline);
    }

    // Employee confirms termination (mutual agreement)
    async transition terminate_confirm(
        emp: Employment,
        end_block: u64
    ) -> (Employment, Future) {
        assert_eq(self.caller, emp.employee);
        assert_eq(emp.owner, emp.employee);
        assert(emp.is_active);
        
        let updated_record: Employment = Employment {
            owner: emp.employee,
            employer: emp.employer,
            employee: emp.employee,
            salary: emp.salary,
            start_block: emp.start_block,
            end_block: end_block,
            is_active: false,
            termination_type: 1u8,
        };
        
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: emp.employer,
            employee: emp.employee,
        });
        
        return (updated_record, finalize_terminate_confirm(employment_hash, emp.employer));
    }
    
    async function finalize_terminate_confirm(employment_hash: field, employer: address) {
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);
        
        Mapping::set(employments, employment_hash, false);
        Mapping::set(pending_terminations, employment_hash, 0u64);
        
        let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
        Mapping::set(employee_count, employer, current_count - 1u64);
    }
    
    // Employee disputes termination (escalates to UWV)
    async transition terminate_dispute(
        emp: Employment,
        current_block: u64
    ) -> (Employment, Future) {
        assert_eq(self.caller, emp.employee);
        assert_eq(emp.owner, emp.employee);
        assert(emp.is_active);
        
        let updated_record: Employment = Employment {
            owner: emp.employee,
            employer: emp.employer,
            employee: emp.employee,
            salary: emp.salary,
            start_block: emp.start_block,
            end_block: current_block,
            is_active: false,
            termination_type: 3u8,
        };
        
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: emp.employer,
            employee: emp.employee,
        });
        
        return (updated_record, finalize_terminate_dispute(employment_hash));
    }
    
    async function finalize_terminate_dispute(employment_hash: field) {
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);
        // Keep pending_terminations entry for UWV to resolve
    }
    
    // Anyone can finalize termination after deadline (no employee response)
    async transition terminate_finalize(
        employer: address,
        employee: address,
        current_block: u64
    ) -> Future {
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: employer,
            employee: employee,
        });
        
        return finalize_terminate_finalize(employment_hash, employer, current_block);
    }
    
    async function finalize_terminate_finalize(employment_hash: field, employer: address, current_block: u64) {
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);
        assert(current_block >= deadline);
        
        Mapping::set(employments, employment_hash, false);
        Mapping::set(pending_terminations, employment_hash, 0u64);
        
        let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
        Mapping::set(employee_count, employer, current_count - 1u64);
    }
    
    // UWV resolves a disputed termination
    async transition terminate_uwv_resolve(
        employer: address,
        employee: address,
        approved: bool
    ) -> Future {
        assert_eq(self.caller, ADMIN);
        
        let employment_hash: field = BHP256::hash_to_field(EmploymentKey {
            employer: employer,
            employee: employee,
        });
        
        return finalize_terminate_uwv_resolve(employment_hash, employer, approved);
    }
    
    async function finalize_terminate_uwv_resolve(employment_hash: field, employer: address, approved: bool) {
        let deadline: u64 = Mapping::get_or_use(pending_terminations, employment_hash, 0u64);
        assert(deadline > 0u64);
        
        Mapping::set(pending_terminations, employment_hash, 0u64);
        
        if approved {
            Mapping::set(employments, employment_hash, false);
            let current_count: u64 = Mapping::get_or_use(employee_count, employer, 0u64);
            Mapping::set(employee_count, employer, current_count - 1u64);
        }
        // If not approved, employment stays active
    }    

    // ============================================
    // TRANSITIONS: PREMIUM DEPOSITS
    // ============================================

    // Employer deposits premium for a period
    async transition deposit_premium(
        public amount: u128,
        public period: u64
    ) -> (PremiumReceipt, Future) {
        let employer: address = self.caller;
        
        assert(amount > 0u128);
        
        let receipt: PremiumReceipt = PremiumReceipt {
            owner: employer,
            employer: employer,
            amount: amount,
            period: period,
        };
        
        let period_key: field = BHP256::hash_to_field(PremiumKey {
            employer: employer,
            period: period,
        });
        
        let transfer_future: Future = mock_usdc.aleo/transfer_from(employer, POOL, amount);
        
        return (receipt, finalize_deposit_premium(employer, amount, period_key, transfer_future));
    }
    
    async function finalize_deposit_premium(
        employer: address, 
        amount: u128, 
        period_key: field,
        transfer_future: Future
    ) {
        transfer_future.await();
        
        let employer_registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(employer_registered);
        
        let already_paid: bool = Mapping::get_or_use(premium_periods, period_key, false);
        assert(!already_paid);
        
        Mapping::set(premium_periods, period_key, true);
        
        let current_total: u128 = Mapping::get_or_use(employer_premium_totals, employer, 0u128);
        Mapping::set(employer_premium_totals, employer, current_total + amount);
        
        let current_pool: u128 = Mapping::get_or_use(pool_balance, 0u8, 0u128);
        Mapping::set(pool_balance, 0u8, current_pool + amount);
    }

    // ============================================
    // TRANSITIONS: CLAIMS & BENEFITS
    // ============================================

    // Employee submits unemployment claim after termination
    // Eligible termination types: 1 (mutual), 2 (employer-initiated finalized), 4 (UWV-resolved)
    // NOT eligible: 0 (active), 3 (disputed pending)
    async transition submit_claim(
        emp: Employment
    ) -> (Claim, Future) {
        // Only the employee can submit their own claim
        assert_eq(self.caller, emp.employee);
        assert_eq(emp.owner, emp.employee);
        
        // Must be terminated (not active)
        assert(!emp.is_active);
        
        // Must be eligible termination type (1, 2, or 4, NOT 3)
        // Type 3 (disputed) cannot claim until UWV resolves it to type 4
        let is_eligible: bool = (emp.termination_type == 1u8) || 
                                 (emp.termination_type == 2u8) || 
                                 (emp.termination_type == 4u8);
        assert(is_eligible);
        
        // Calculate work duration
        let work_duration: u64 = emp.end_block - emp.start_block;
        
        // Must have worked minimum duration (26 weeks)
        assert(work_duration >= MIN_WORK_DURATION);
        
        // Calculate benefit months based on Dutch WW rules:
        // - Minimum 3 months
        // - +1 month per year worked (after first year)
        // - Maximum 24 months
        let years_worked: u64 = work_duration / BLOCKS_PER_YEAR;
        let benefit_months: u64 = MIN_BENEFIT_MONTHS + years_worked;
        
        // Cap at maximum
        let final_months: u64 = benefit_months < MAX_BENEFIT_MONTHS ? benefit_months : MAX_BENEFIT_MONTHS;
        
        // Calculate benefit amount (70% of salary)
        // salary is u64, convert to u128 for USDC calculations
        let salary_u128: u128 = emp.salary as u128;
        let benefit_amount: u128 = (salary_u128 * BENEFIT_PERCENTAGE as u128) / 100u128;
        
        // Create claim record
        let claim: Claim = Claim {
            owner: emp.employee,
            employee: emp.employee,
            employer: emp.employer,
            benefit_amount: benefit_amount,
            total_months: final_months,
            months_claimed: 0u64,
            last_withdraw_block: emp.end_block,  // Start from termination
            end_block: emp.end_block,
        };
        
        // Compute claim key for mapping
        let claim_key: field = BHP256::hash_to_field(ClaimKey {
            employer: emp.employer,
            employee: emp.employee,
            end_block: emp.end_block,
        });
        
        return (claim, finalize_submit_claim(emp.employee, claim_key));
    }
    
    async function finalize_submit_claim(employee: address, claim_key: field) {
        // Check this specific employment hasn't been claimed already
        let already_claimed: bool = Mapping::get_or_use(claims, claim_key, false);
        assert(!already_claimed);
        
        // Check employee doesn't have an active claim
        // (can only have one active claim at a time)
        let has_active: bool = Mapping::get_or_use(active_claims, employee, false);
        assert(!has_active);
        
        // Mark claim as submitted
        Mapping::set(claims, claim_key, true);
        
        // Mark employee as having active claim
        Mapping::set(active_claims, employee, true);
    }

    // Employee withdraws monthly benefit
    // Can only withdraw once per month, up to total_months
    async transition withdraw_benefit(
        claim: Claim,
        current_block: u64
    ) -> (Claim, Future) {
        // Only the claim owner can withdraw
        assert_eq(self.caller, claim.employee);
        assert_eq(claim.owner, claim.employee);
        
        // Check there are remaining months to claim
        assert(claim.months_claimed < claim.total_months);
        
        // Check enough time has passed since last withdrawal (1 month)
        let next_withdraw_block: u64 = claim.last_withdraw_block + BLOCKS_PER_MONTH;
        assert(current_block >= next_withdraw_block);
        
        // Create updated claim record
        let updated_claim: Claim = Claim {
            owner: claim.employee,
            employee: claim.employee,
            employer: claim.employer,
            benefit_amount: claim.benefit_amount,
            total_months: claim.total_months,
            months_claimed: claim.months_claimed + 1u64,
            last_withdraw_block: current_block,
            end_block: claim.end_block,
        };
        
        // Check if this is the final withdrawal
        let is_final: bool = (claim.months_claimed + 1u64) >= claim.total_months;
        
        // Transfer benefit from POOL to employee
        // Note: POOL must have approved this program to spend USDC
        let transfer_future: Future = mock_usdc.aleo/transfer_from(POOL, claim.employee, claim.benefit_amount);
        
        return (updated_claim, finalize_withdraw_benefit(claim.employee, claim.benefit_amount, is_final, transfer_future));
    }
    
    async function finalize_withdraw_benefit(
        employee: address,
        amount: u128,
        is_final: bool,
        transfer_future: Future
    ) {
        // Execute the USDC transfer
        transfer_future.await();
        
        // Decrease pool balance
        let current_pool: u128 = Mapping::get_or_use(pool_balance, 0u8, 0u128);
        assert(current_pool >= amount);  // Pool must have enough funds
        Mapping::set(pool_balance, 0u8, current_pool - amount);
        
        // If final withdrawal, clear active claim status
        if is_final {
            Mapping::set(active_claims, employee, false);
        }
    }

}
