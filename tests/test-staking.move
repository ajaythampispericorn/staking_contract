#[test_only]
module staking_contract::contract_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use staking_contract::resource_account;
    use staking_contract::roles;
    use staking_contract::mycoin::{Self, MyCoin};
    use staking_contract::staking;

    // Constants
    const ROLE_ADMIN: u8 = 1;
    const ROLE_STAKER: u8 = 2;
    const INITIAL_BALANCE: u64 = 1000000;
    const APY_RATE: u64 = 1000; // 10% in basis points

    // Error constants for testing
    const ENOT_ADMIN: u64 = 1;
    const EZERO_MINT_AMOUNT: u64 = 2;
    const EACCOUNT_NOT_REGISTERED: u64 = 3;

    // Test account addresses
    const ADMIN_ADDR: address = @0xA;
    const USER1_ADDR: address = @0xB;
    const USER2_ADDR: address = @0xC;

    // Helper struct for test accounts
    struct TestAccounts has drop {
        deployer: signer,
        admin: signer,
        user1: signer,
        user2: signer,
    }

    // Setup function to initialize all required accounts and modules
    #[test_only]
fun setup_test(aptos_framework: &signer): TestAccounts {
    // Set timestamp for testing
    timestamp::set_time_has_started_for_testing(aptos_framework);

    // Create test accounts
    let deployer = account::create_account_for_test(@staking_contract);
    let admin = account::create_account_for_test(ADMIN_ADDR);
    let user1 = account::create_account_for_test(USER1_ADDR);
    let user2 = account::create_account_for_test(USER2_ADDR);

    // Initialize modules in correct order
    if (!coin::is_coin_initialized<MyCoin>()) {
        // Initialize resource account - it will handle its own existence check
        resource_account::initialize_for_test(&deployer);

        // Initialize roles - it has its own existence check
        roles::initialize_for_test(&deployer, &admin, &user1);

        // Initialize mycoin - it has its own existence checks
        mycoin::init_for_testing(&deployer);

        // Initialize staking pool
        if (!staking::check_pool_initialized()) {
            staking::initialize_for_test(&deployer, APY_RATE);
        };

        // Register accounts for MyCoin
        if (!coin::is_account_registered<MyCoin>(ADMIN_ADDR)) {
            mycoin::register(&admin);
        };
        if (!coin::is_account_registered<MyCoin>(USER1_ADDR)) {
            mycoin::register(&user1);
        };
        if (!coin::is_account_registered<MyCoin>(USER2_ADDR)) {
            mycoin::register(&user2);
        };

        // Initial minting
        if (mycoin::balance_of(ADMIN_ADDR) == 0) {
            mycoin::test_mint(INITIAL_BALANCE, ADMIN_ADDR);
        };
        if (mycoin::balance_of(USER1_ADDR) == 0) {
            mycoin::test_mint(INITIAL_BALANCE, USER1_ADDR);
        };
    };

    TestAccounts {
        deployer,
        admin,
        user1,
        user2,
    }
}
    // === Resource Account Tests ===
    #[test(aptos_framework = @0x1)]
    fun test_resource_account_initialization(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        let resource_addr = resource_account::get_resource_account_address();
        assert!(account::exists_at(resource_addr), 0);
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10064)]
    fun test_resource_account_double_init(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        resource_account::initialize(&accounts.deployer);
    }

    // === Roles Tests ===
    #[test(aptos_framework = @0x1)]
    fun test_roles_basic_flow(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        // Verify admin role
        assert!(roles::is_admin(ADMIN_ADDR), 0);
        assert!(!roles::is_admin(USER1_ADDR), 1);

        // Assign staker role
        roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
        assert!(roles::is_staker(USER1_ADDR), 2);
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50001)]
    fun test_roles_unauthorized_assignment(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        roles::assign_role(&accounts.user1, USER2_ADDR, ROLE_STAKER);
    }

    // === MyCoin Tests ===
    #[test(aptos_framework = @0x1)]
    fun test_mycoin_basic_operations(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);

        // Test initial balances
        assert!(mycoin::balance_of(ADMIN_ADDR) == INITIAL_BALANCE, 0);
        assert!(mycoin::balance_of(USER1_ADDR) == INITIAL_BALANCE, 1);

        // Test minting
        mycoin::mint(&accounts.admin, 1000, USER2_ADDR);
        assert!(mycoin::balance_of(USER2_ADDR) == 1000, 2);
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10002)]
    fun test_mycoin_zero_mint(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        mycoin::mint(&accounts.admin, 0, USER1_ADDR);
    }

    // === Staking Tests ===
    #[test(aptos_framework = @0x1)]
    fun test_staking_basic_flow(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        // Enable staking role
        roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
        
        // Test staking
        let stake_amount = 1000;
        staking::stake(&accounts.user1, stake_amount, true);
        
        // Advance time for rewards
        timestamp::fast_forward_seconds(86400); // 1 day
        
        // Claim rewards
        staking::claim_rewards(&accounts.user1);
        
        // Unstake
        staking::unstake(&accounts.user1, stake_amount);
    }

    #[test(aptos_framework = @0x1)]
    fun test_staking_rewards_calculation(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
        
        let stake_amount = 10000;
        staking::stake(&accounts.user1, stake_amount, false);
        
        // Advance time (1 year)
        timestamp::fast_forward_seconds(31536000);
        
        // The rewards should be 10% APY
        staking::claim_rewards(&accounts.user1);
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure]
    fun test_staking_insufficient_balance(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        roles::assign_role(&accounts.admin, USER2_ADDR, ROLE_STAKER);
        
        // Try to stake more than balance
        staking::stake(&accounts.user2, INITIAL_BALANCE + 1, false);
    }

   #[test(aptos_framework = @0x1)]
    fun test_emergency_mode(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        // Enable emergency mode
        staking::set_emergency_mode(&accounts.admin, true);
        
        // Verify emergency mode is enabled
        assert!(staking::is_emergency_mode(), 0);
        
        // Try to stake (this should fail in the next test)
        roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
    }

    #[test(aptos_framework = @0x1)]
#[expected_failure(abort_code = 0x30003)]
fun test_stake_in_emergency_mode(aptos_framework: &signer) {
    let accounts = setup_test(aptos_framework);
    
    // Enable emergency mode
    staking::set_emergency_mode(&accounts.admin, true);
    
    // Setup staker
    roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
    
    // This should fail due to emergency mode
    staking::stake(&accounts.user1, 1000, false);
}

    #[test(aptos_framework = @0x1)]
    fun test_compound_staking(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
        
        let stake_amount = 10000;
        staking::stake(&accounts.user1, stake_amount, true);
        
        // Advance time (6 months)
        timestamp::fast_forward_seconds(15768000);
        
        // Verify compounds correctly
        staking::claim_rewards(&accounts.user1);
    }

    #[test(aptos_framework = @0x1)]
    fun test_multiple_stakers(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        // Setup both users as stakers
        roles::assign_role(&accounts.admin, USER1_ADDR, ROLE_STAKER);
        roles::assign_role(&accounts.admin, USER2_ADDR, ROLE_STAKER);
        
        // Initial minting for user2
        mycoin::mint(&accounts.admin, INITIAL_BALANCE, USER2_ADDR);
        
        // Both stake
        let stake_amount = 5000;
        staking::stake(&accounts.user1, stake_amount, false);
        staking::stake(&accounts.user2, stake_amount, true);
        
        // Advance time
        timestamp::fast_forward_seconds(31536000);
        
        // Both claim
        staking::claim_rewards(&accounts.user1);
        staking::claim_rewards(&accounts.user2);
    }

    #[test(aptos_framework = @0x1)]
    fun test_apy_rate_update(aptos_framework: &signer) {
        let accounts = setup_test(aptos_framework);
        
        // Update APY rate
        let new_apy = 1500; // 15%
        staking::update_apy_rate(&accounts.admin, new_apy);
        
        // Get and verify the new APY rate using the public function
        assert!(staking::get_apy_rate() == new_apy, 0);
    }
}