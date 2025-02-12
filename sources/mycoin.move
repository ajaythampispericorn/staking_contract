module staking_contract::mycoin {
    use std::string;
    use std::error;
    use std::signer;
    use std::option;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use staking_contract::roles;

    /// Error codes
    const ENOT_ADMIN: u64 = 1;
    const EZERO_MINT_AMOUNT: u64 = 2;
    const EACCOUNT_NOT_REGISTERED: u64 = 3;
    const EMAX_SUPPLY_EXCEEDED: u64 = 4;
    const EINVALID_DECIMALS: u64 = 5;
    const EALREADY_REGISTERED: u64 = 6;
    const ESIGNER_CAP_NOT_FOUND: u64 = 7;

    /// Constants
    const MAX_SUPPLY: u64 = 1000000000000000; 
    const MIN_DECIMALS: u8 = 6;
    const MAX_DECIMALS: u8 = 18;

    /// MyCoin token
    struct MyCoin {}

    /// Resource account capability
    struct CoinCapability has key {
        signer_cap: SignerCapability
    }

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
        let (resource_signer, signer_cap) = account::create_resource_account(
            deployer,
            b"MYCOIN"
        );

        move_to(deployer, CoinCapability { signer_cap });

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
        if (!coin::is_coin_initialized<MyCoin>()) {
            let (resource_signer, signer_cap) = account::create_resource_account(
                deployer,
                b"MYCOIN"
            );

            move_to(deployer, CoinCapability { signer_cap });

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
    }

    fun get_resource_signer(deployer_address: address): signer acquires CoinCapability {
        assert!(exists<CoinCapability>(deployer_address), error::not_found(ESIGNER_CAP_NOT_FOUND));
        let signer_cap = &borrow_global<CoinCapability>(deployer_address).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    public fun register(account: &signer) {
        coin::register<MyCoin>(account);
    }

    public entry fun mint(
        deployer_address: address,
        admin: &signer,
        amount: u64,
        to: address,
    ) acquires Capabilities, CoinCapability {
        let _resource_signer = get_resource_signer(deployer_address);
        roles::assert_admin(admin);
        
        assert!(exists<Capabilities>(@staking_contract), error::not_found(7));
        let caps = borrow_global<Capabilities>(@staking_contract);
        
        assert!(amount > 0, error::invalid_argument(EZERO_MINT_AMOUNT));
        assert!(coin::is_account_registered<MyCoin>(to), error::invalid_state(EACCOUNT_NOT_REGISTERED));

        let current_supply = option::extract(&mut coin::supply<MyCoin>());
        assert!(
            current_supply + (amount as u128) <= (MAX_SUPPLY as u128),
            error::invalid_argument(EMAX_SUPPLY_EXCEEDED)
        );

        let coins_minted = coin::mint(amount, &caps.mint_cap);
        coin::deposit(to, coins_minted);
    }

    public fun burn(
        deployer_address: address,
        coins: coin::Coin<MyCoin>,
        admin: &signer,
    ) acquires Capabilities, CoinCapability {
        let _resource_signer = get_resource_signer(deployer_address);
        roles::assert_admin(admin);
        
        assert!(exists<Capabilities>(@staking_contract), error::not_found(7));
        let caps = borrow_global<Capabilities>(@staking_contract);
        coin::burn(coins, &caps.burn_cap);
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
    public fun test_mint(deployer: &signer, amount: u64, recipient: address) acquires Capabilities {
        let caps = borrow_global<Capabilities>(@staking_contract);
        let coins = coin::mint(amount, &caps.mint_cap);
        coin::deposit(recipient, coins);
    }

    #[test_only]
    public fun test_burn(coins: coin::Coin<MyCoin>) acquires Capabilities {
        let caps = borrow_global<Capabilities>(@staking_contract);
        coin::burn(coins, &caps.burn_cap);
    }
}