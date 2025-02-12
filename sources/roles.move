module staking_contract::roles {
    use std::error;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;  // Add coin module import
    use staking_contract::resource_account;
    use staking_contract::mycoin::MyCoin;

    /// Error codes
    const ENOT_ADMIN: u64 = 1;
    const EROLE_NOT_FOUND: u64 = 2;
    const EROLE_ALREADY_ASSIGNED: u64 = 3;
    const EINVALID_ROLE: u64 = 4;
    const ESELF_REVOKE: u64 = 5;

    /// Role types
    const ROLE_ADMIN: u8 = 1;
    const ROLE_STAKER: u8 = 2;

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
    struct Roles has key {
        user_roles: vector<UserRole>,
        grant_events: EventHandle<RoleGrantEvent>,
        revoke_events: EventHandle<RoleRevokeEvent>,
    }

    struct UserRole has store {
        account: address,
        roles: vector<u8>
    }

    /// Initialize roles with event handling
    public fun initialize(deployer: &signer) acquires Roles {  // Added 'acquires Roles'
    let resource_signer = resource_account::get_resource_signer();
    let resource_addr = resource_account::get_resource_account_address();
    
    assert!(!exists<Roles>(resource_addr), 0);

    move_to(&resource_signer, Roles {
        user_roles: vector::empty(),
        grant_events: account::new_event_handle<RoleGrantEvent>(&resource_signer),
        revoke_events: account::new_event_handle<RoleRevokeEvent>(&resource_signer),
    });

    // Initialize deployer as admin
    let deployer_addr = signer::address_of(deployer);
    internal_assign_role(deployer_addr, ROLE_ADMIN, deployer_addr);
}

    fun validate_role(role: u8) {
        assert!(
            role == ROLE_ADMIN || role == ROLE_STAKER,
            error::invalid_argument(EINVALID_ROLE)
        );
    }

    fun find_user_role_index(roles: &vector<UserRole>, account: address): (bool, u64) {
        let i = 0;
        let len = vector::length(roles);
        while (i < len) {
            if (vector::borrow(roles, i).account == account) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    fun internal_assign_role(account: address, role: u8, admin_addr: address) acquires Roles {
        validate_role(role);
        
        let roles = borrow_global_mut<Roles>(resource_account::get_resource_account_address());
        let (exists, index) = find_user_role_index(&roles.user_roles, account);
        
        if (!exists) {
            let new_user_role = UserRole {
                account,
                roles: vector::singleton(role)
            };
            vector::push_back(&mut roles.user_roles, new_user_role);
        } else {
            let user_role = vector::borrow_mut(&mut roles.user_roles, index);
            assert!(!vector::contains(&user_role.roles, &role), error::already_exists(EROLE_ALREADY_ASSIGNED));
            vector::push_back(&mut user_role.roles, role);
        };

        event::emit_event(&mut roles.grant_events, RoleGrantEvent {
            role,
            account,
            granted_by: admin_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    public entry fun assign_role(
        admin: &signer,
        account: address,
        role: u8,
    ) acquires Roles {
        let admin_addr = signer::address_of(admin);
        assert!(is_admin(admin_addr), error::permission_denied(ENOT_ADMIN));
        internal_assign_role(account, role, admin_addr);
    }

    public fun has_role(account: address, role: u8): bool acquires Roles {
        let roles = borrow_global<Roles>(resource_account::get_resource_account_address());
        let (exists, index) = find_user_role_index(&roles.user_roles, account);
        if (!exists) {
            return false
        };
        let user_role = vector::borrow(&roles.user_roles, index);
        vector::contains(&user_role.roles, &role)
    }

    public fun is_admin(addr: address): bool acquires Roles {
        has_role(addr, ROLE_ADMIN)
    }

    public fun is_staker(addr: address): bool acquires Roles {
        has_role(addr, ROLE_STAKER)
    }

    public fun assert_admin(admin: &signer) acquires Roles {
        assert!(
            is_admin(signer::address_of(admin)),
            error::permission_denied(ENOT_ADMIN)
        );
    }

    public fun get_user_roles(account: address): vector<u8> acquires Roles {
        let roles = borrow_global<Roles>(resource_account::get_resource_account_address());
        let (exists, index) = find_user_role_index(&roles.user_roles, account);
        if (!exists) {
            vector::empty()
        } else {
            *&vector::borrow(&roles.user_roles, index).roles
        }
    }

    #[test_only]
public fun initialize_for_test(deployer: &signer, admin: &signer, _user: &signer) acquires Roles {
    if (!exists<Roles>(resource_account::get_resource_account_address())) {
        resource_account::initialize_for_test(deployer);
        initialize(deployer);
        
        // Setup additional admin role if needed
        if (signer::address_of(admin) != signer::address_of(deployer)) {
            internal_assign_role(
                signer::address_of(admin),
                ROLE_ADMIN,
                signer::address_of(deployer)
            );
        };
    }
}

    #[test_only]
    public fun check_roles_initialized(): bool {
        exists<Roles>(resource_account::get_resource_account_address())
    }
}