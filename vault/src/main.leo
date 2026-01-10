// ZK_InsuranceX - Private Unemployment Insurance Protocol
// Phase 1: Employer Registration


// TESTNET
// 1. leo build
// 2. leo deploy --network testnet --broadcast


// DEVNET alternative 1
// 1. leo build
// 2. leo devnet --snarkos $(which snarkos) --snarkos-features test_network --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11 --clear-storage
// 3. leo deploy --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 4. leo execute register_employer aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0 --network testnet --broadcast --consensus-heights 0,1,2,3,4,5,6,7,8,9,10,11
// 5. CHECK: curl http://localhost:3030/testnet/program/zk_insurancex.aleo/mapping/employers/aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0



program zk_insurancex.aleo {

    @noupgrade
    async constructor() {}


    // The admin address (UWV authority)
    // const ADMIN: address = aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0; // Testnet
    const ADMIN: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px; // Devnet

    // ============================================
    // MAPPINGS
    // ============================================
    
    // Tracks registered employers: employer_address => is_registered
    // MAPPING is PUBLIC - visible to everyone on-chain
    mapping employers: address => bool;
    
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
    
    // ============================================
    // VIEW HELPERS (for testing)
    // ============================================
    
    // Check if an address is a registered employer
    // Note: This is a transition that returns the value via finalize
    // In practice, you'd query the mapping directly off-chain
    async transition is_employer(employer: address) -> Future {
        return finalize_is_employer(employer);
    }
    
    async function finalize_is_employer(employer: address) {
        // This will fail if not registered (get throws on missing key)
        // Or we could use get_or_use and assert
        let registered: bool = Mapping::get_or_use(employers, employer, false);
        assert(registered); // Will fail if not an employer
    }
}
