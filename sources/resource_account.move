module staking_contract::resource_account {
    use std::signer;
    use aptos_framework::account::{Self, SignerCapability};
    use std::bcs;
    use std::error;
    
    // Error codes
    const ERESOURCE_CAP_ALREADY_EXISTS: u64 = 100;
    const ERESOURCE_CAP_NOT_FOUND: u64 = 101;
    
    struct ResourceCap has key {
        signer_cap: SignerCapability
    }
    
    /// Initialize the resource account using the staking_contract address as seed
    public fun initialize(deployer: &signer) {
        assert!(!exists<ResourceCap>(@staking_contract), error::already_exists(ERESOURCE_CAP_ALREADY_EXISTS));
        
        // Convert the module address to bytes to use as seed
        let seed = bcs::to_bytes(&@staking_contract);
        
        let (resource_signer, signer_cap) = account::create_resource_account(
            deployer,
            seed
        );
        move_to(deployer, ResourceCap { signer_cap });
    }
    
    /// Get the resource account signer using the stored capability
    public fun get_resource_signer(): signer acquires ResourceCap {
        assert!(exists<ResourceCap>(@staking_contract), error::not_found(ERESOURCE_CAP_NOT_FOUND));
        let signer_cap = &borrow_global<ResourceCap>(@staking_contract).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }
    
    /// Get the address of the resource account (for testing/verification)
    public fun get_resource_account_address(): address acquires ResourceCap {
        let resource_signer = get_resource_signer();
        signer::address_of(&resource_signer)
    }
    
    #[test_only]
    public fun initialize_for_test(deployer: &signer) {
        if (!exists<ResourceCap>(@staking_contract)) {
            initialize(deployer);
        }
    }

    #[test_only]
    /// Check if resource account is initialized
    public fun is_initialized(): bool {
        exists<ResourceCap>(@staking_contract)
    }
}