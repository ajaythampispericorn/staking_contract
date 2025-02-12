module staking_contract::roles {
    use std::error;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;

    /// Error codes
    const ENOT_ADMIN: u64 = 1;
    const EROLE_NOT_FOUND: u64 = 2;
    const EROLE_ALREADY_ASSIGNED: u64 = 3;
    const EINVALID_ROLE: u64 = 4;
    const ESELF_REVOKE: u64 = 5;
    const ESIGNER_CAP_NOT_FOUND: u64 = 6;

    /// Role types
    const ROLE_ADMIN: u8 = 1;
    const ROLE_STAKER: u8 = 2;

    /// Resource account capability
    struct RoleCapability has key {
        signer_cap: SignerCapability
    }

    /// Role events
    struct RoleGrantEvent has drop, store {
        role: u8,
        account: address,
        granted_by: address,
        timestamp: u64,
    }

    struct RoleRevokeEvent has drop, store {
        role: u8,
        account: address,
        revoked_by: address,
        timestamp: u64,
    }

    /// Stores role information with multi-role support
    struct UserRoles has key {
        roles: vector<u8>
    }

    /// Event handles
    struct RoleEvents has key {
        grant_events: EventHandle<RoleGrantEvent>,
        revoke_events: EventHandle<RoleRevokeEvent>,
    }

    fun get_resource_signer(deployer_address: address): signer acquires RoleCapability {
        assert!(exists<RoleCapability>(deployer_address), error::not_found(ESIGNER_CAP_NOT_FOUND));
        let signer_cap = &borrow_global<RoleCapability>(deployer_address).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Initialize roles with event handling
    public fun initialize(deployer: &signer) {
        let (resource_signer, signer_cap) = account::create_resource_account(
            deployer,
            b"ROLES"
        );

        move_to(deployer, RoleCapability { signer_cap });
        
        let roles = vector::empty<u8>();
        vector::push_back(&mut roles, ROLE_ADMIN);
        move_to(&resource_signer, UserRoles { roles });

        move_to(&resource_signer, RoleEvents {
            grant_events: account::new_event_handle<RoleGrantEvent>(&resource_signer),
            revoke_events: account::new_event_handle<RoleRevokeEvent>(&resource_signer),
        });
    }

    #[test_only]
    public fun initialize_for_test(deployer: &signer, admin: &signer, _user: &signer) {
        if (!exists<RoleEvents>(@staking_contract)) {
            let (resource_signer, signer_cap) = account::create_resource_account(
                deployer,
                b"ROLES"
            );

            move_to(deployer, RoleCapability { signer_cap });

            // Initialize admin role
            let roles = vector::empty<u8>();
            vector::push_back(&mut roles, ROLE_ADMIN);
            move_to(&resource_signer, UserRoles { roles });

            // Initialize event handles
            move_to(&resource_signer, RoleEvents {
                grant_events: account::new_event_handle<RoleGrantEvent>(&resource_signer),
                revoke_events: account::new_event_handle<RoleRevokeEvent>(&resource_signer),
            });

            // Setup admin role for the admin account
            if (!exists<UserRoles>(signer::address_of(admin))) {
                move_to(admin, UserRoles { 
                    roles: vector::singleton(ROLE_ADMIN) 
                });
            };
        }
    }

    fun validate_role(role: u8) {
        assert!(
            role == ROLE_ADMIN || role == ROLE_STAKER,
            error::invalid_argument(EINVALID_ROLE)
        );
    }

    public entry fun assign_role(
        deployer_address: address,
        admin: &signer,
        account_addr: address,
        role: u8,
    ) acquires UserRoles, RoleEvents, RoleCapability {
        let resource_signer = get_resource_signer(deployer_address);
        let admin_addr = signer::address_of(admin);
        assert!(is_admin(admin_addr), error::permission_denied(ENOT_ADMIN));
        validate_role(role);

        assert!(account::exists_at(account_addr), error::not_found(EROLE_NOT_FOUND));
        
        if (!exists<UserRoles>(account_addr)) {
            move_to(&resource_signer, UserRoles { 
                roles: vector::empty() 
            });
        };

        let user_roles = borrow_global_mut<UserRoles>(account_addr);
        assert!(
            !vector::contains(&user_roles.roles, &role),
            error::already_exists(EROLE_ALREADY_ASSIGNED)
        );
        vector::push_back(&mut user_roles.roles, role);

        // Emit role grant event
        let events = borrow_global_mut<RoleEvents>(@staking_contract);
        event::emit_event(&mut events.grant_events, RoleGrantEvent {
            role,
            account: account_addr,
            granted_by: admin_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    public fun has_role(account: address, role: u8): bool acquires UserRoles {
        if (!exists<UserRoles>(account)) {
            return false
        };
        let user_roles = borrow_global<UserRoles>(account);
        vector::contains(&user_roles.roles, &role)
    }

    public fun is_admin(addr: address): bool acquires UserRoles {
        has_role(addr, ROLE_ADMIN)
    }

    public fun is_staker(addr: address): bool acquires UserRoles {
        has_role(addr, ROLE_STAKER)
    }

    public fun assert_admin(admin: &signer) acquires UserRoles {
        assert!(
            is_admin(signer::address_of(admin)),
            error::permission_denied(ENOT_ADMIN)
        );
    }

    public fun get_user_roles(account: address): vector<u8> acquires UserRoles {
        if (!exists<UserRoles>(account)) {
            vector::empty()
        } else {
            *&borrow_global<UserRoles>(account).roles
        }
    }

    #[test_only]
    public fun create_user_roles(): UserRoles {
        UserRoles {
            roles: vector::empty()
        }
    }

    #[test_only]
    public fun init_for_testing(deployer: &signer) {
        initialize(deployer);
    }

    #[test_only]
    public fun check_roles_initialized(): bool {
        exists<RoleEvents>(@staking_contract)
    }
}