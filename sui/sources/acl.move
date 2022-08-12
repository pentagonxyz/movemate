// SPDX-License-Identifier: UNLICENSED

/// @title acl
/// @notice Multi-role access control list (ACL).
/// @dev Maps addresses to `u128`s with each bit representing the presence of (or lack of) each role.
module movemate::acl {
    use std::errors;

    use sui::vec_map::{Self, VecMap};

    /// @dev When attempting to add/remove a role >= 128.
    const EROLE_NUMBER_TOO_LARGE: u64 = 0;

    /// @dev Maps addresses to `u128`s with each bit representing the presence of (or lack of) each role.
    struct ACL {
        permissions: VecMap<address, u128>
    }

    /// @notice Create a new ACL (access control list).
    public fun new(): ACL {
        ACL { permissions: vec_map::empty() }
    }

    /// @notice Check if a member has a role in the ACL.
    public fun has_role(acl: &ACL, member: address, role: u8): bool {
        assert!(role < 128, errors::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        vec_map::contains(&acl.permissions, &member) && *vec_map::get(&acl.permissions, &member) & (1 << role) > 0
    }

    /// @notice Set all roles for a member in the ACL.
    /// @param permissions Permissions for a member, represented as a `u128` with each bit representing the presence of (or lack of) each role.
    public fun set_role(acl: &mut ACL, member: address, permissions: u128) {
        if (vec_map::contains(&acl.permissions, &member)) *vec_map::get_mut(&mut acl.permissions, &member) = permissions
        else vec_map::insert(&mut acl.permissions, member, permissions);
    }

    /// @notice Add a role for a member in the ACL.
    public fun add_role(acl: &mut ACL, member: address, role: u8) {
        assert!(role < 128, errors::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        if (vec_map::contains(&acl.permissions, &member)) {
            let perms = vec_map::get_mut(&mut acl.permissions, &member);
            *perms = *perms | (1 << role);
        } else {
            vec_map::insert(&mut acl.permissions, member, 1 << role);
        }
    }

    /// @notice Revoke a role for a member in the ACL.
    public fun remove_role(acl: &mut ACL, member: address, role: u8) {
        assert!(role < 128, errors::invalid_argument(EROLE_NUMBER_TOO_LARGE));
        if (vec_map::contains(&acl.permissions, &member)) {
            let perms = vec_map::get_mut(&mut acl.permissions, &member);
            *perms = *perms - (1 << role);
        }
    }
}
