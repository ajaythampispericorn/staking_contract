module staking_contract::tests {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use staking_contract::staking;
    use staking_contract::roles;
    use staking_contract::mycoin::{Self, MyCoin};
    use aptos_framework::aptos_account;

    // Constants for testing
    const INITIAL_STAKE_AMOUNT: u64 = 100;
    const INITIAL_APY_RATE: u64 = 5000; // 50%
    const TEST_DURATION: u64 = 31536000; // 1 year
    
    // Error codes
    const ENOT_ADMIN: u64 = 1;
    const EZERO_MINT_AMOUNT: u64 = 2;
    const EACCOUNT_NOT_REGISTERED: u64 = 3;
    const EMAX_SUPPLY_EXCEEDED: u64 = 4;
    const EINVALID_MATH_RESULT: u64 = 7;

    // Test setup helper
    fun setup_test_env(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        // Initialize framework
        timestamp::set_time_has_started_for_testing(framework);
        
        // Create accounts
        let admin_addr = signer::address_of(admin);
        let user_addr = signer::address_of(user);
        let deployer_addr = signer::address_of(deployer);
        
        if (!account::exists_at(admin_addr)) {
            aptos_account::create_account(admin_addr);
        };
        if (!account::exists_at(user_addr)) {
            aptos_account::create_account(user_addr);
        };
        if (!account::exists_at(deployer_addr)) {
            aptos_account::create_account(deployer_addr);
        };
    }

    // ROLES MODULE TESTS

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_roles_initialization(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        roles::initialize(deployer);
        assert!(roles::check_roles_initialized(), 0);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_admin_role_assignment(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        roles::initialize(deployer);
        
        let admin_addr = signer::address_of(admin);
        assert!(!roles::is_admin(admin_addr), 0);
        
        roles::assign_role(signer::address_of(deployer), admin, admin_addr, 1);
        assert!(roles::is_admin(admin_addr), 1);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_staker_role_assignment(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        roles::initialize(deployer);
        
        let user_addr = signer::address_of(user);
        assert!(!roles::is_staker(user_addr), 0);
        
        roles::assign_role(signer::address_of(deployer), admin, user_addr, 2);
        assert!(roles::is_staker(user_addr), 1);
    }

    // STAKING MODULE TESTS

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_staking_pool_initialization(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        staking::initialize_pool(deployer, INITIAL_APY_RATE);
        assert!(staking::check_pool_initialized(), 1);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_stake_and_unstake(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        
        // Initialize modules
        roles::initialize(deployer);
        staking::initialize_pool(deployer, INITIAL_APY_RATE);
        
        // Setup roles
        let deployer_addr = signer::address_of(deployer);
        let user_addr = signer::address_of(user);
        roles::assign_role(deployer_addr, admin, user_addr, 2);
        
        // Test stake
        staking::stake(user, INITIAL_STAKE_AMOUNT, true);
        
        // Test unstake
        staking::unstake(user, INITIAL_STAKE_AMOUNT);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_rewards_calculation(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        
        // Initialize modules
        roles::initialize(deployer);
        staking::initialize_pool(deployer, INITIAL_APY_RATE);
        
        // Setup roles and stake
        let deployer_addr = signer::address_of(deployer);
        let user_addr = signer::address_of(user);
        roles::assign_role(deployer_addr, admin, user_addr, 2);
        staking::stake(user, INITIAL_STAKE_AMOUNT, true);
        
        // Advance time and claim rewards
        timestamp::fast_forward_seconds(TEST_DURATION);
        staking::claim_rewards(user);
    }

    // MYCOIN MODULE TESTS

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_coin_initialization(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        mycoin::init_for_testing(deployer);
        assert!(coin::is_coin_initialized<MyCoin>(), 1);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_mint_and_burn(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        
        // Initialize coin
        mycoin::init_for_testing(deployer);
        mycoin::register(user);
        
        let deployer_addr = signer::address_of(deployer);
        let user_addr = signer::address_of(user);
        
        // Test mint
        let mint_amount = 1000;
        mycoin::mint(deployer_addr, admin, mint_amount, user_addr);
        assert!(mycoin::balance_of(user_addr) == mint_amount, 1);
        
        // Test burn
        let coin = coin::withdraw<MyCoin>(user, mint_amount);
        mycoin::burn(deployer_addr, coin, admin);
        assert!(mycoin::balance_of(user_addr) == 0, 2);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    public fun test_coin_supply(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        
        // Initialize coin
        mycoin::init_for_testing(deployer);
        mycoin::register(user);
        
        let initial_supply = mycoin::total_supply();
        let mint_amount = 1000;
        
        // Test supply increase after mint
        mycoin::mint(signer::address_of(deployer), admin, mint_amount, signer::address_of(user));
        assert!(mycoin::total_supply() == initial_supply + mint_amount, 1);
    }

    // ERROR CASE TESTS

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure(abort_code = EZERO_MINT_AMOUNT)]
    public fun test_zero_mint_failure(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        mycoin::init_for_testing(deployer);
        mycoin::register(user);
        mycoin::mint(signer::address_of(deployer), admin, 0, signer::address_of(user));
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure(abort_code = EMAX_SUPPLY_EXCEEDED)]
    public fun test_exceed_max_supply(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        mycoin::init_for_testing(deployer);
        mycoin::register(user);
        let max_supply = mycoin::max_supply() + 1;
        mycoin::mint(signer::address_of(deployer), admin, max_supply, signer::address_of(user));
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure(abort_code = EACCOUNT_NOT_REGISTERED)]
    public fun test_mint_to_unregistered(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        mycoin::init_for_testing(deployer);
        mycoin::mint(signer::address_of(deployer), admin, 1000, signer::address_of(user));
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure]
    public fun test_unauthorized_mint(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        mycoin::init_for_testing(deployer);
        mycoin::register(user);
        mycoin::mint(signer::address_of(deployer), user, 1000, signer::address_of(user));
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure]
    public fun test_unauthorized_burn(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        mycoin::init_for_testing(deployer);
        mycoin::register(user);
        mycoin::mint(signer::address_of(deployer), admin, 1000, signer::address_of(user));
        let coin = coin::withdraw<MyCoin>(user, 1000);
        mycoin::burn(signer::address_of(deployer), coin, user);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure]
    public fun test_unauthorized_staking(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        staking::initialize_pool(deployer, INITIAL_APY_RATE);
        staking::stake(user, INITIAL_STAKE_AMOUNT, true);
    }

    #[test(framework = @0x1, admin = @0x123, user = @0x456, deployer = @0x789)]
    #[expected_failure]
    public fun test_unstake_more_than_staked(
        framework: &signer,
        admin: &signer,
        user: &signer,
        deployer: &signer
    ) {
        setup_test_env(framework, admin, user, deployer);
        roles::initialize(deployer);
        staking::initialize_pool(deployer, INITIAL_APY_RATE);
        
        let deployer_addr = signer::address_of(deployer);
        let user_addr = signer::address_of(user);
        roles::assign_role(deployer_addr, admin, user_addr, 2);
        
        staking::stake(user, INITIAL_STAKE_AMOUNT, true);
        staking::unstake(user, INITIAL_STAKE_AMOUNT * 2);
    }
}