module staking_contract::mycoin {
    use std::string;
    use std::error;
    use std::signer;
    use std::option;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use staking_contract::roles;
    use staking_contract::resource_account;

    /// Error codes
    const ENOT_ADMIN: u64 = 1;
    const EZERO_MINT_AMOUNT: u64 = 2;
    const EACCOUNT_NOT_REGISTERED: u64 = 3;
    const EMAX_SUPPLY_EXCEEDED: u64 = 4;
    const EINVALID_DECIMALS: u64 = 5;
    const EALREADY_REGISTERED: u64 = 6;

    /// Constants
    const MAX_SUPPLY: u64 = 1000000000000000; 
    const MIN_DECIMALS: u8 = 6;
    const MAX_DECIMALS: u8 = 18;

    /// MyCoin token
    struct MyCoin {}

    /// Storing mint and burn capabilities
    struct Capabilities has key {
        mint_cap: MintCapability<MyCoin>,
        burn_cap: BurnCapability<MyCoin>,
    }

    /// Events
    struct MintEvent has drop, store {
        amount: u64,
        recipient: address,
        timestamp: u64,
    }

    struct BurnEvent has drop, store {
        amount: u64,
        burner: address,
        timestamp: u64,
    }

    /// Event handles stored in a separate resource
    struct CoinEvents has key {
        mint_events: EventHandle<MintEvent>,
        burn_events: EventHandle<BurnEvent>,
    }

    fun init_module(deployer: &signer) {
        let resource_signer = resource_account::get_resource_signer();
        let resource_addr = resource_account::get_resource_account_address();

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyCoin>(
            &resource_signer,
            string::utf8(b"MyCoin"),
            string::utf8(b"MCOIN"),
            8,
            true,
        );

        move_to(&resource_signer, Capabilities {
            mint_cap,
            burn_cap,
        });

        move_to(&resource_signer, CoinEvents {
            mint_events: account::new_event_handle<MintEvent>(&resource_signer),
            burn_events: account::new_event_handle<BurnEvent>(&resource_signer),
        });

        coin::destroy_freeze_cap(freeze_cap);
    }
    
    #[test_only]
public fun init_for_testing(deployer: &signer) {
    let resource_addr = resource_account::get_resource_account_address();
    
    // Only initialize if coin and capabilities don't exist
    if (!exists<Capabilities>(resource_addr)) {
        // Initialize resource account if needed
        resource_account::initialize_for_test(deployer);
        let resource_signer = resource_account::get_resource_signer();

        // Only initialize coin if it hasn't been initialized
        if (!coin::is_coin_initialized<MyCoin>()) {
            let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyCoin>(
                &resource_signer,
                string::utf8(b"MyCoin"),
                string::utf8(b"MCOIN"),
                8,
                true,
            );

            move_to(&resource_signer, Capabilities {
                mint_cap,
                burn_cap,
            });

            move_to(&resource_signer, CoinEvents {
                mint_events: account::new_event_handle<MintEvent>(&resource_signer),
                burn_events: account::new_event_handle<BurnEvent>(&resource_signer),
            });

            coin::destroy_freeze_cap(freeze_cap);
        };
    };
}
    public fun register(account: &signer) {
        coin::register<MyCoin>(account);
    }

    public entry fun mint(
        admin: &signer,
        amount: u64,
        to: address,
    ) acquires Capabilities, CoinEvents {
        roles::assert_admin(admin);
        
        let resource_addr = resource_account::get_resource_account_address();
        assert!(exists<Capabilities>(resource_addr), error::not_found(7));
        let caps = borrow_global<Capabilities>(resource_addr);
        
        assert!(amount > 0, error::invalid_argument(EZERO_MINT_AMOUNT));
        assert!(coin::is_account_registered<MyCoin>(to), error::invalid_state(EACCOUNT_NOT_REGISTERED));

        let current_supply = option::extract(&mut coin::supply<MyCoin>());
        assert!(
            current_supply + (amount as u128) <= (MAX_SUPPLY as u128),
            error::invalid_argument(EMAX_SUPPLY_EXCEEDED)
        );

        let coins_minted = coin::mint(amount, &caps.mint_cap);
        coin::deposit(to, coins_minted);

        // Emit mint event
        let events = borrow_global_mut<CoinEvents>(resource_addr);
        event::emit_event(
            &mut events.mint_events,
            MintEvent {
                amount,
                recipient: to,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    public fun burn(
        coins: coin::Coin<MyCoin>,
        admin: &signer,
    ) acquires Capabilities, CoinEvents {
        roles::assert_admin(admin);
        
        let resource_addr = resource_account::get_resource_account_address();
        assert!(exists<Capabilities>(resource_addr), error::not_found(7));
        let caps = borrow_global<Capabilities>(resource_addr);
        
        let amount = coin::value(&coins);
        let burner = signer::address_of(admin);
        
        coin::burn(coins, &caps.burn_cap);

        // Emit burn event
        let events = borrow_global_mut<CoinEvents>(resource_addr);
        event::emit_event(
            &mut events.burn_events,
            BurnEvent {
                amount,
                burner,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    public fun get_token_info(): (string::String, string::String, u8) {
        (
            string::utf8(b"MyCoin"),
            string::utf8(b"MCOIN"),
            8
        )
    }

    public fun balance_of(owner: address): u64 {
        if (coin::is_account_registered<MyCoin>(owner)) {
            coin::balance<MyCoin>(owner)
        } else {
            0
        }
    }

    public fun total_supply(): u64 {
        option::extract(&mut coin::supply<MyCoin>()) as u64
    }

    public fun max_supply(): u64 {
        MAX_SUPPLY
    }

    #[test_only]
    public fun test_mint(amount: u64, recipient: address) acquires Capabilities {
        let caps = borrow_global<Capabilities>(resource_account::get_resource_account_address());
        let coins = coin::mint(amount, &caps.mint_cap);
        coin::deposit(recipient, coins);
    }

    #[test_only]
    public fun test_burn(coins: coin::Coin<MyCoin>) acquires Capabilities {
        let caps = borrow_global<Capabilities>(resource_account::get_resource_account_address());
        coin::burn(coins, &caps.burn_cap);
    }
}