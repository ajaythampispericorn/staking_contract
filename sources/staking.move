module staking_contract::staking {
    use std::signer;
    use std::vector;
    use std::string;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use std::error;
    use std::timestamp;
    use aptos_framework::account;
    use staking_contract::resource_account;

    const SECONDS_PER_YEAR: u64 = 31536000;
    const BASIS_POINTS_DIVISOR: u64 = 10000;
    const MAX_APY_RATE: u64 = 10000; // 100% in basis points
    
    // Error codes
    const EINVALID_MATH_RESULT: u64 = 7;
    const ESTAKING_POOL_ALREADY_EXISTS: u64 = 1;
    const EINVALID_APY_RATE: u64 = 2;
    const EEMERGENCY_MODE_ACTIVE: u64 = 3;
    const EZERO_UNSTAKE_AMOUNT: u64 = 4;
    const EINSUFFICIENT_STAKE: u64 = 5;
    const MAX_U64: u128 = 18446744073709551615;

    struct StakingPool has key {
        stakes: SimpleMap<address, UserStake>,
        total_staked: u64,
        emergency_mode: bool,
        apy_rate: u64,
        event_handle: event::EventHandle<StakingEvent>,
    }

    struct UserStake has store {
        amount: u64,
        start_time: u64,
        last_claim_time: u64,
        total_rewards_claimed: u64,
        compound_enabled: bool,
    }

    struct StakingEvent has drop, store {
        event_type: u8,
        user: address,
        amount: u64,
        fee_paid: u64,
        timestamp: u64,
    }

    struct ReentrancyGuard has key {
        entered: bool,
        last_operation: u8,
    }

    public fun initialize_pool(deployer: &signer, apy_rate: u64) {
        let resource_account_addr = resource_account::get_resource_account_address();
        assert!(!exists<StakingPool>(resource_account_addr), error::already_exists(ESTAKING_POOL_ALREADY_EXISTS));
        assert!(apy_rate <= MAX_APY_RATE / 2, error::invalid_argument(EINVALID_APY_RATE));

        let resource_signer = resource_account::get_resource_signer();

        move_to(&resource_signer, StakingPool { 
            stakes: simple_map::new(),
            total_staked: 0,
            emergency_mode: false,
            apy_rate,
            event_handle: account::new_event_handle<StakingEvent>(&resource_signer),
        });
        
        // Initialize reentrancy guard
        if (!exists<ReentrancyGuard>(resource_account_addr)) {
            move_to(&resource_signer, ReentrancyGuard {
                entered: false,
                last_operation: 0,
            });
        };
    }

    #[test_only]
    public fun initialize_for_test(deployer: &signer, apy_rate: u64) {
        resource_account::initialize_for_test(deployer);
        let resource_account_addr = resource_account::get_resource_account_address();
        
        if (!exists<StakingPool>(resource_account_addr)) {
            let resource_signer = resource_account::get_resource_signer();

            move_to(&resource_signer, StakingPool { 
                stakes: simple_map::new(),
                total_staked: 0,
                emergency_mode: false,
                apy_rate,
                event_handle: account::new_event_handle<StakingEvent>(&resource_signer),
            });
            
            if (!exists<ReentrancyGuard>(resource_account_addr)) {
                move_to(&resource_signer, ReentrancyGuard {
                    entered: false,
                    last_operation: 0,
                });
            };
        }
    }

    fun begin_operation(operation: u8) acquires ReentrancyGuard {
        let resource_account_addr = resource_account::get_resource_account_address();
        let guard = borrow_global_mut<ReentrancyGuard>(resource_account_addr);
        assert!(!guard.entered, error::invalid_state(6));
        guard.entered = true;
        guard.last_operation = operation;
    }

    fun end_operation() acquires ReentrancyGuard {
        let resource_account_addr = resource_account::get_resource_account_address();
        let guard = borrow_global_mut<ReentrancyGuard>(resource_account_addr);
        guard.entered = false;
    }

    public fun get_pool_address(): address {
        resource_account::get_resource_account_address()
    }

    public fun stake(user: &signer, amount: u64, compound: bool) 
    acquires StakingPool, ReentrancyGuard {
        begin_operation(1);
        
        let resource_account_addr = get_pool_address();
        let pool = borrow_global_mut<StakingPool>(resource_account_addr);
        assert!(!pool.emergency_mode, error::invalid_state(EEMERGENCY_MODE_ACTIVE));

        let staker_addr = signer::address_of(user);
        let now = timestamp::now_seconds();

        if (!simple_map::contains_key(&pool.stakes, &staker_addr)) {
            simple_map::add(
                &mut pool.stakes,
                staker_addr,
                UserStake {
                    amount: 0,
                    start_time: now,
                    last_claim_time: now,
                    total_rewards_claimed: 0,
                    compound_enabled: compound
                }
            );
        };

        let user_stake = simple_map::borrow_mut(&mut pool.stakes, &staker_addr);
        user_stake.amount = user_stake.amount + amount;
        user_stake.compound_enabled = compound;
        pool.total_staked = pool.total_staked + amount;

        event::emit_event(
            &mut pool.event_handle,
            StakingEvent {
                event_type: 0,
                user: staker_addr,
                amount,
                fee_paid: 0,
                timestamp: now
            }
        );
        
        end_operation();
    }

    public fun unstake(user: &signer, amount: u64) 
    acquires StakingPool, ReentrancyGuard {
        begin_operation(2);
        
        let resource_account_addr = get_pool_address();
        let pool = borrow_global_mut<StakingPool>(resource_account_addr);
        let staker_addr = signer::address_of(user);
        let now = timestamp::now_seconds();

        let user_stake = simple_map::borrow_mut(&mut pool.stakes, &staker_addr); 
        assert!(amount > 0, error::invalid_argument(EZERO_UNSTAKE_AMOUNT));
        assert!(user_stake.amount >= amount, error::invalid_argument(EINSUFFICIENT_STAKE));

        user_stake.amount = user_stake.amount - amount;
        pool.total_staked = pool.total_staked - amount;

        event::emit_event(
            &mut pool.event_handle,
            StakingEvent {
                event_type: 1,
                user: staker_addr,
                amount,
                fee_paid: 0,
                timestamp: now
            }
        );
        
        end_operation();
    }

    public fun claim_rewards(user: &signer) 
    acquires StakingPool, ReentrancyGuard {
        begin_operation(3);
        
        let resource_account_addr = get_pool_address();
        let pool = borrow_global_mut<StakingPool>(resource_account_addr);
        let staker_addr = signer::address_of(user);
        let now = timestamp::now_seconds();

        let user_stake = simple_map::borrow_mut(&mut pool.stakes, &staker_addr); 
        let reward = calculate_rewards(user_stake.amount, now - user_stake.last_claim_time, pool.apy_rate);

        user_stake.total_rewards_claimed = user_stake.total_rewards_claimed + reward;
        user_stake.last_claim_time = now;

        event::emit_event(
            &mut pool.event_handle,
            StakingEvent {
                event_type: 2,
                user: staker_addr,
                amount: reward,
                fee_paid: 0,
                timestamp: now
            }
        );
        
        end_operation();
    }

    fun calculate_rewards(stake_amount: u64, duration: u64, apy: u64): u64 {
        let stake_u128 = (stake_amount as u128);
        let apy_u128 = (apy as u128);
        let duration_u128 = (duration as u128);
        
        let numerator = stake_u128 * apy_u128 * duration_u128;
        let denominator = (BASIS_POINTS_DIVISOR as u128) * (SECONDS_PER_YEAR as u128);
        
        assert!(numerator / denominator <= MAX_U64, error::invalid_state(EINVALID_MATH_RESULT));
        
        ((numerator / denominator) as u64)
    }

    public fun set_emergency_mode(admin: &signer, enabled: bool)
    acquires StakingPool {
        let resource_account_addr = get_pool_address();
        let pool = borrow_global_mut<StakingPool>(resource_account_addr);
        pool.emergency_mode = enabled;
    }

    public fun update_apy_rate(admin: &signer, new_apy_rate: u64)
    acquires StakingPool {
        assert!(new_apy_rate <= MAX_APY_RATE, error::invalid_argument(EINVALID_APY_RATE));
        let resource_account_addr = get_pool_address();
        let pool = borrow_global_mut<StakingPool>(resource_account_addr);
        pool.apy_rate = new_apy_rate;
    }

    #[test_only]
    public fun check_pool_initialized(): bool {
        exists<StakingPool>(get_pool_address())
    }
}