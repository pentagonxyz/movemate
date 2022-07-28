// SPDX-License-Identifier: MIT
// Based on: OpenZeppelin Contracts (last updated v4.7.0) (utils/escrow/Escrow.sol)

/// @title Escrow
/// @dev Base escrow module, holds funds designated for a payee until they withdraw them.
module Movemate::Escrow {
    use std::signer;

    use sui::coin::{Self, Coin};
    use sui::vec_map::{Self, VecMap};

    struct Escrow<phantom T> has key {
        coins: VecMap<address, Coin<T>>
    }

    public fun deposits_of<T>(payer: address, payee: address): u64 acquires Escrow {
        coin::value(vec_map::get(&borrow_global<Escrow<T>>(payer).coins, &payee))
    }

    /// @dev Stores the sent amount as credit to be withdrawn.
    /// @param payee The destination address of the funds.
    public entry fun deposit<T>(payer: &signer, payee: address, coin_in: Coin<T>) acquires Escrow {
        let payer_address = Signer::address_of(payer);
        if (!exists<Escrow<T>>(payer_address)) move_to(payer, Escrow<T> { coins: vec_map::empty() });
        let coins = &mut borrow_global_mut<Escrow<T>>(payer_address).coins;
        if (vec_map::contains(coins, &payee)) coin::join(&mut coin_in, vec_map::remove(coins, &payee));
        vec_map::insert(coins, &payee, coin_in);
    }

    /// @dev Withdraw accumulated balance for a payee, forwarding all gas to the
    /// recipient.
    /// @param payee The address whose funds will be withdrawn and transferred to.
    public entry fun withdraw<T>(payer: &signer, payee: address) acquires Escrow {
        let payer_address = signer::address_of(payer);
        let coins = &mut borrow_global_mut<Escrow<T>>(payer_address).coins;
        coin::transfer(vec_map::remove(&mut coins, &payee), payee);
    }
}
