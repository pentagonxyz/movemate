// SPDX-License-Identifier: MIT

/// @title LinearVesting
/// @dev This contract handles the vesting of Eth and ERC20 tokens for a given beneficiary. Custody of multiple tokens
/// can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
/// The vesting schedule is customizable through the {vestedAmount} function.
/// Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
/// Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
/// be immediately releasable.
module Movemate::LinearVesting {
    use Std::Signer;
    use Std::Vector;

    use AptosFramework::Coin::{Self, Coin};
    use AptosFramework::IterableTable::{Self, IterableTable};
    use AptosFramework::Table::{Self, Table};
    use AptosFramework::Timestamp;

    struct WalletInfo has store {
        start: u64,
        duration: u64,
        can_clawback: bool
    }

    struct WalletInfoCollection has key {
        wallets: IterableTable<address, vector<WalletInfo>>
    }

    struct CoinStore<phantom T> has store {
        coin: Coin<T>,
        released: u64
    }

    struct CoinStoreCollection<phantom T> has key {
        wallets: IterableTable<address, Table<u64, CoinStore<T>>>
    }

    /// @dev Enables an asset on the admin's wallet collecton.
    public fun init_asset<T>(admin: &signer) {
        move_to(admin, CoinStoreCollection<T> {
            wallets: IterableTable::new()
        });
    }

    /// @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
    public fun init_wallet(admin: &signer, beneficiary: address, start_timestamp: u64, duration_seconds: u64, can_clawback: bool) acquires WalletInfoCollection {
        // Create WalletInfoCollection if it doesn't exist
        let admin_address = Signer::address_of(admin);

        if (!exists<WalletInfoCollection>(admin_address)) {
            move_to(admin, WalletInfoCollection {
                wallets: IterableTable::new()
            });
        };

        // Add beneficiary to collection
        let wallet_infos = &mut borrow_global_mut<WalletInfoCollection>(admin_address).wallets;
        if (!IterableTable::contains(wallet_infos, beneficiary)) IterableTable::add(wallet_infos, beneficiary, Vector::empty());
        let collection = IterableTable::borrow_mut(wallet_infos, beneficiary);

        // Add wallet to array
        Vector::push_back(collection, WalletInfo {
            start: start_timestamp,
            duration: duration_seconds,
            can_clawback
        });
    }

    /// @notice Returns the vesting wallet details.
    public fun wallet_info(admin: address, beneficiary: address, index: u64): (u64, u64, bool) acquires WalletInfoCollection {
        let wallet_infos = &mut borrow_global_mut<WalletInfoCollection>(admin).wallets;
        let collection = IterableTable::borrow(wallet_infos, beneficiary);
        let wallet_info = Vector::borrow(collection, index);
        (wallet_info.start, wallet_info.duration, wallet_info.can_clawback)
    }

    /// @notice Returns the vesting wallet asset balance and amount released.
    public fun wallet_asset<T>(admin: address, beneficiary: address, index: u64): (u64, u64) acquires CoinStoreCollection {
        let coin_stores = &borrow_global<CoinStoreCollection<T>>(admin).wallets;
        let collection = IterableTable::borrow(coin_stores, beneficiary);
        let coin_store = Table::borrow(collection, index);
        (Coin::value(&coin_store.coin), coin_store.released)
    }

    /// @dev Release the tokens that have already vested.
    public fun release<T>(admin: address, beneficiary: address, index: u64) acquires WalletInfoCollection, CoinStoreCollection {
        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin).wallets;
        let collection = IterableTable::borrow(wallet_infos, beneficiary);
        let wallet_info = Vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin).wallets;
        let collection = IterableTable::borrow_mut(coin_stores, beneficiary);
        let coin_store = Table::borrow_mut(collection, index);

        // Release amount
        let releasable = vested_amount(wallet_info.start, wallet_info.duration, Coin::value(&coin_store.coin), coin_store.released, Timestamp::now_seconds()) - coin_store.released;
        *&mut coin_store.released = *&coin_store.released + releasable;
        let release_coin = Coin::extract(&mut coin_store.coin, releasable);
        Coin::deposit(beneficiary, release_coin);
    }

    /// @notice Claws back coins to the admin if `can_clawback` is enabled.
    public fun clawback<T>(admin: &signer, beneficiary: address, index: u64) acquires WalletInfoCollection, CoinStoreCollection {
        // Get admin address
        let admin_address = Signer::address_of(admin);

        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin_address).wallets;
        let collection = IterableTable::borrow(wallet_infos, beneficiary);
        let wallet_info = Vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin_address).wallets;
        let collection = IterableTable::borrow_mut(coin_stores, beneficiary);
        let coin_store = Table::borrow_mut(collection, index);

        // Release amount
        let releasable = vested_amount(wallet_info.start, wallet_info.duration, Coin::value(&coin_store.coin), coin_store.released, Timestamp::now_seconds()) - coin_store.released;
        *&mut coin_store.released = *&coin_store.released + releasable;
        let release_coin = Coin::extract(&mut coin_store.coin, releasable);
        Coin::deposit(beneficiary, release_coin);

        // Validate clawback
        assert!(wallet_info.can_clawback, 1000);

        // Execute clawback
        let clawback_coin = Coin::extract_all(&mut coin_store.coin);
        Coin::deposit<T>(admin_address, clawback_coin);
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
