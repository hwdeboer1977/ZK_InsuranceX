// ZK_InsuranceX - Private Unemployment Insurance Protocol
// Phase 1: Employer Registration
// Phase 2: Employee Registration

// TESTNET
// 1. leo build
// 2. leo deploy --network testnet --broadcast


// DEVNET alternative 1
// 1. leo build
// 2. leo devnet --snarkos $(which snarkos) --snarkos-features test_network --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage
// 3. leo deploy --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 4. leo execute register_employer aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 5. CHECK: curl http://localhost:3030/testnet/program/zk_insurancex.aleo/mapping/employers/aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0
// 6. leo execute register_employee aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px 5000000000u64 1000u64 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11


program zk_insurancex.aleo {

    @noupgrade
    async constructor() {}


    // The admin address (UWV authority)
    // const ADMIN: address = aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0; // Testnet
    const ADMIN: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px; // Devnet

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
        termination_type: u8      // 0 = active, 1 = mutual, 2 = employer-initiated, 3 = UWV-resolved
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
        
        // Compute hash for duplicate check (only employer + employee matter)
        let employment_hash: field = BHP256::hash_to_field(Employment {
            owner: employer,
            employer: employer,
            employee: employee,
            salary: 0u64,
            start_block: 0u64,
            end_block: 0u64,
            is_active: true,
            termination_type: 0u8,
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
}
