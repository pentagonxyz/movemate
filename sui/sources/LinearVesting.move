// SPDX-License-Identifier: MIT

/// @title LinearVesting
/// @dev This contract handles the vesting of coins for a given beneficiary. Custody of multiple coins
/// can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
/// The vesting schedule is customizable through the {vestedAmount} function.
/// Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
/// Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
/// be immediately releasable.
module Movemate::LinearVesting {
    use std::signer;
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    struct WalletInfo has store {
        start: u64,
        duration: u64,
        can_clawback: bool
    }

    struct WalletInfoCollection has key {
        wallets: VecMap<address, vector<WalletInfo>>
    }

    struct CoinStore<phantom T> has store {
        coin: Coin<T>,
        released: u64
    }

    struct CoinStoreCollection<phantom T> has key {
        wallets: VecMap<address, VecMap<u64, CoinStore<T>>>
    }

    /// @dev Enables an asset on the admin's wallet collecton.
    public entry fun init_asset<T>(admin: &signer) {
        move_to(admin, CoinStoreCollection<T> {
            wallets: vec_map::empty()
        });
    }

    /// @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
    public entry fun init_wallet(admin: &signer, beneficiary: address, start_timestamp: u64, duration_seconds: u64, can_clawback: bool) acquires WalletInfoCollection {
        // Create WalletInfoCollection if it doesn't exist
        let admin_address = signer::address_of(admin);

        if (!exists<WalletInfoCollection>(admin_address)) {
            move_to(admin, WalletInfoCollection {
                wallets: vec_map::empty()
            });
        };

        // Add beneficiary to collection
        let wallet_infos = &mut borrow_global_mut<WalletInfoCollection>(admin_address).wallets;
        if (!vec_map::contains(wallet_infos, &beneficiary)) vec_map::insert(wallet_infos, beneficiary, vector::empty());
        let collection = vec_map::get_mut(wallet_infos, &beneficiary);

        // Add wallet to array
        vector::push_back(collection, WalletInfo {
            start: start_timestamp,
            duration: duration_seconds,
            can_clawback
        });
    }

    /// @notice Returns the vesting wallet details.
    public fun wallet_info(admin: address, beneficiary: address, index: u64): (u64, u64, bool) acquires WalletInfoCollection {
        let wallet_infos = &mut borrow_global_mut<WalletInfoCollection>(admin).wallets;
        let collection = vec_map::get(wallet_infos, &beneficiary);
        let wallet_info = vector::borrow(collection, index);
        (wallet_info.start, wallet_info.duration, wallet_info.can_clawback)
    }

    /// @notice Returns the vesting wallet asset balance and amount released.
    public fun wallet_asset<T>(admin: address, beneficiary: address, index: u64): (u64, u64) acquires CoinStoreCollection {
        let coin_stores = &borrow_global<CoinStoreCollection<T>>(admin).wallets;
        let collection = vec_map::get(coin_stores, &beneficiary);
        let coin_store = vec_map::get(collection, &index);
        (coin::value(&coin_store.coin), coin_store.released)
    }

    /// @dev Release the tokens that have already vested.
    public entry fun release<T>(admin: address, beneficiary: address, index: u64, ctx: &mut TxContext) acquires WalletInfoCollection, CoinStoreCollection {
        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin).wallets;
        let collection = vec_map::get(wallet_infos, &beneficiary);
        let wallet_info = vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin).wallets;
        let collection = vec_map::get_mut(coin_stores, &beneficiary);
        let coin_store = vec_map::get_mut(collection, &index);

        // Release amount
        let releasable = vested_amount(wallet_info.start, wallet_info.duration, coin::value(&coin_store.coin), coin_store.released, tx_context::epoch(ctx)) - coin_store.released;
        *&mut coin_store.released = *&coin_store.released + releasable;
        coin::split_and_transfer<T>(&mut coin_store.coin, releasable, beneficiary, ctx);
    }

    /// @notice Claws back coins to the admin if `can_clawback` is enabled.
    public entry fun clawback<T>(admin: &signer, beneficiary: address, index: u64, ctx: &mut TxContext) acquires WalletInfoCollection, CoinStoreCollection {
        // Get admin address
        let admin_address = signer::address_of(admin);

        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin_address).wallets;
        let collection = vec_map::get(wallet_infos, &beneficiary);
        let wallet_info = vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin_address).wallets;
        let collection = vec_map::get_mut(coin_stores, &beneficiary);
        let coin_store = vec_map::get_mut(collection, &index);

        // Release amount
        let releasable = vested_amount(wallet_info.start, wallet_info.duration, coin::value(&coin_store.coin), coin_store.released, tx_context::epoch(ctx)) - coin_store.released;
        *&mut coin_store.released = *&coin_store.released + releasable;
        coin::split_and_transfer<T>(&mut coin_store.coin, releasable, copy beneficiary, ctx);

        // Validate clawback
        assert!(wallet_info.can_clawback, 1000);

        // Execute clawback
        let coin_out = &mut coin_store.coin;
        let value = coin::value(coin_out);
        coin::split_and_transfer<T>(coin_out, value, admin_address, ctx);
    }

    /// Calculates the amount that has already vested. Default implementation is a linear vesting curve.
    fun vested_amount(start: u64, duration: u64, balance: u64, already_released: u64, timestamp: u64): u64 {
        vesting_schedule(start, duration, balance + already_released, timestamp)
    }

    /// @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for an asset given its total historical allocation.
    fun vesting_schedule(start: u64, duration: u64, total_allocation: u64, timestamp: u64): u64 {
        if (timestamp < start) return 0;
        if (timestamp > start + duration) return total_allocation;
        (total_allocation * (timestamp - start)) / duration
    }
}
