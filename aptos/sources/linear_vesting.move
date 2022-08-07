// SPDX-License-Identifier: MIT

/// @title linear_vesting
/// @dev This contract handles the vesting of coins for a given beneficiary. Custody of multiple coins
/// can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
/// The vesting schedule is customizable through the {vestedAmount} function.
/// Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
/// Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
/// be immediately releasable.
module movemate::linear_vesting {
    use std::error;
    use std::signer;
    use std::vector;

    use aptos_std::iterable_table::{Self, IterableTable};
    use aptos_std::table::{Self, Table};

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

    /// @dev When trying to clawback a wallet without the privilege to do so.
    const ECANNOT_CLAWBACK: u64 = 0;

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
    public entry fun init_asset<T>(admin: &signer) {
        move_to(admin, CoinStoreCollection<T> {
            wallets: iterable_table::new()
        });
    }

    /// @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
    public entry fun init_wallet(admin: &signer, beneficiary: address, start_timestamp: u64, duration_seconds: u64, can_clawback: bool) acquires WalletInfoCollection {
        // Create WalletInfoCollection if it doesn't exist
        let admin_address = signer::address_of(admin);

        if (!exists<WalletInfoCollection>(admin_address)) {
            move_to(admin, WalletInfoCollection {
                wallets: iterable_table::new()
            });
        };

        // Add beneficiary to collection
        let wallet_infos = &mut borrow_global_mut<WalletInfoCollection>(admin_address).wallets;
        if (!iterable_table::contains(wallet_infos, beneficiary)) iterable_table::add(wallet_infos, beneficiary, vector::empty());
        let collection = iterable_table::borrow_mut(wallet_infos, beneficiary);

        // Add wallet to array
        vector::push_back(collection, WalletInfo {
            start: start_timestamp,
            duration: duration_seconds,
            can_clawback
        });
    }

    /// @dev Deposits `coin_in` to a wallet.
    public fun deposit<T>(admin: address, beneficiary: address, index: u64, coin_in: Coin<T>) acquires CoinStoreCollection {
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin).wallets;
        let collection = iterable_table::borrow_mut(coin_stores, beneficiary);
        let coin_store = table::borrow_mut(collection, index);
        coin::merge(&mut coin_store.coin, coin_in)
    }

    /// @dev Transfers in `amount` coins to a wallet from `depositor`.
    public entry fun transfer_in<T>(depositor: &signer, admin: address, beneficiary: address, index: u64, amount: u64) acquires CoinStoreCollection {
        deposit<T>(admin, beneficiary, index, coin::withdraw<T>(depositor, amount));
    }

    /// @notice Returns the vesting wallet details.
    public fun wallet_info(admin: address, beneficiary: address, index: u64): (u64, u64, bool) acquires WalletInfoCollection {
        let wallet_infos = &mut borrow_global_mut<WalletInfoCollection>(admin).wallets;
        let collection = iterable_table::borrow(wallet_infos, beneficiary);
        let wallet_info = vector::borrow(collection, index);
        (wallet_info.start, wallet_info.duration, wallet_info.can_clawback)
    }

    /// @notice Returns the vesting wallet asset balance and amount released.
    public fun wallet_asset<T>(admin: address, beneficiary: address, index: u64): (u64, u64) acquires CoinStoreCollection {
        let coin_stores = &borrow_global<CoinStoreCollection<T>>(admin).wallets;
        let collection = iterable_table::borrow(coin_stores, beneficiary);
        let coin_store = table::borrow(collection, index);
        (coin::value(&coin_store.coin), coin_store.released)
    }

    /// @dev Release the tokens that have already vested.
    public entry fun release<T>(admin: address, beneficiary: address, index: u64) acquires WalletInfoCollection, CoinStoreCollection {
        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin).wallets;
        let collection = iterable_table::borrow(wallet_infos, beneficiary);
        let wallet_info = vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin).wallets;
        let collection = iterable_table::borrow_mut(coin_stores, beneficiary);
        let coin_store = table::borrow_mut(collection, index);

        // Release amount
        let releasable = vested_amount(wallet_info.start, wallet_info.duration, coin::value(&coin_store.coin), coin_store.released, timestamp::now_seconds()) - coin_store.released;
        *&mut coin_store.released = *&coin_store.released + releasable;
        let release_coin = coin::extract(&mut coin_store.coin, releasable);
        coin::deposit(beneficiary, release_coin);
    }

    /// @notice Claws back coins to the admin if `can_clawback` is enabled.
    public entry fun clawback<T>(admin: &signer, beneficiary: address, index: u64) acquires WalletInfoCollection, CoinStoreCollection {
        // Get admin address
        let admin_address = signer::address_of(admin);

        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin_address).wallets;
        let collection = iterable_table::borrow(wallet_infos, beneficiary);
        let wallet_info = vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &mut borrow_global_mut<CoinStoreCollection<T>>(admin_address).wallets;
        let collection = iterable_table::borrow_mut(coin_stores, beneficiary);
        let coin_store = table::borrow_mut(collection, index);

        // Release amount
        let releasable = vested_amount(wallet_info.start, wallet_info.duration, coin::value(&coin_store.coin), coin_store.released, timestamp::now_seconds()) - coin_store.released;
        *&mut coin_store.released = *&coin_store.released + releasable;
        let release_coin = coin::extract(&mut coin_store.coin, releasable);
        coin::deposit(beneficiary, release_coin);

        // Validate clawback
        assert!(wallet_info.can_clawback, error::permission_denied(ECANNOT_CLAWBACK));

        // Execute clawback
        let clawback_coin = coin::extract_all(&mut coin_store.coin);
        coin::deposit<T>(admin_address, clawback_coin);
    }

    /// @dev Returns (1) the amount that has vested at the current time and the (2) portion of that amount that has not yet been released.
    public fun vesting_status<T>(admin: address, beneficiary: address, index: u64): (u64, u64) acquires WalletInfoCollection, CoinStoreCollection {
        // Get wallet info
        let wallet_infos = &borrow_global<WalletInfoCollection>(admin).wallets;
        let collection = iterable_table::borrow(wallet_infos, beneficiary);
        let wallet_info = vector::borrow(collection, index);

        // Get coin store
        let coin_stores = &borrow_global<CoinStoreCollection<T>>(admin).wallets;
        let collection = iterable_table::borrow(coin_stores, beneficiary);
        let coin_store = table::borrow(collection, index);

        // Return vested amount
        let vested = vested_amount(wallet_info.start, wallet_info.duration, coin::value(&coin_store.coin), coin_store.released, timestamp::now_seconds());
        (vested, vested - coin_store.released)
    }

    /// @dev Calculates the amount that has already vested. Default implementation is a linear vesting curve.
    fun vested_amount(start: u64, duration: u64, balance: u64, already_released: u64, timestamp: u64): u64 {
        vesting_schedule(start, duration, balance + already_released, timestamp)
    }

    /// @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for an asset given its total historical allocation.
    fun vesting_schedule(start: u64, duration: u64, total_allocation: u64, timestamp: u64): u64 {
        if (timestamp < start) return 0;
        if (timestamp > start + duration) return total_allocation;
        (total_allocation * (timestamp - start)) / duration
    }

    #[test_only]
    struct FakeMoney { }

    #[test_only]
    struct FakeMoneyCapabilities has key {
        mint_cap: coin::MintCapability<FakeMoney>,
        burn_cap: coin::BurnCapability<FakeMoney>,
    }
    
    #[test_only]
    fun fast_forward_seconds(timestamp_seconds: u64) {
        timestamp::update_global_time_for_test(timestamp::now_microseconds() + timestamp_seconds * 1000000);
    }

    #[test(admin = @0x1000, beneficiary = @0x1001, coin_creator = @movemate)]
    public entry fun test_end_to_end(admin: signer, beneficiary: signer, coin_creator: signer) acquires WalletInfoCollection, CoinStoreCollection {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );
        let coin_in = coin::mint<FakeMoney>(1234567890, &mint_cap);

        // init wallet and asset
        let beneficiary_address = signer::address_of(&beneficiary);
        init_wallet(&admin, beneficiary_address, timestamp::now_seconds(), 86400, true);
        init_asset<FakeMoney>(&admin);
        let admin_address = signer::address_of(&admin);
        deposit<FakeMoney>(admin_address, beneficiary_address, 0, coin_in);

        // fast forward and release
        fast_forward_seconds(3600);
        coin::register_for_test<FakeMoney>(&beneficiary);
        release<FakeMoney>(admin_address, beneficiary_address, 0);
        assert!(coin::balance<FakeMoney>(beneficiary_address) == 51440328, 0);

        // fast forward and claw back
        fast_forward_seconds(7200);
        coin::register_for_test<FakeMoney>(&admin);
        clawback<FakeMoney>(&admin, beneficiary_address, 0);
        assert!(coin::balance<FakeMoney>(admin_address) == 102880658, 1);

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }

    #[test(admin = @0x1000, beneficiary = @0x1001, beneficiary2 = @0x1002)]
    public entry fun test_multiple_wallets(admin: signer, beneficiary: signer, beneficiary2: signer) acquires WalletInfoCollection {
        // init wallet and asset
        let beneficiary_address = signer::address_of(&beneficiary);
        init_wallet(&admin, beneficiary_address, timestamp::now_seconds(), 86400, true);

        // init wallet and asset
        let beneficiary2_address = signer::address_of(&beneficiary2);
        init_wallet(&admin, beneficiary2_address, timestamp::now_seconds(), 86400, true);

        // init wallet and asset
        init_wallet(&admin, beneficiary2_address, timestamp::now_seconds(), 172800, true);
    }

    #[test(admin = @0x1000, beneficiary = @0x1001, coin_creator = @movemate)]
    #[expected_failure(abort_code = 0x50000)]
    public entry fun test_no_clawback(admin: signer, beneficiary: signer, coin_creator: signer) acquires WalletInfoCollection, CoinStoreCollection {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );
        let coin_in = coin::mint<FakeMoney>(1234567890, &mint_cap);

        // init wallet and asset
        let beneficiary_address = signer::address_of(&beneficiary);
        init_wallet(&admin, beneficiary_address, timestamp::now_seconds(), 86400, true);
        init_asset<FakeMoney>(&admin);
        let admin_address = signer::address_of(&admin);
        deposit<FakeMoney>(admin_address, beneficiary_address, 0, coin_in);

        // fast forward and claw back (should fail)
        fast_forward_seconds(3600);
        coin::register_for_test<FakeMoney>(&admin);
        clawback<FakeMoney>(&admin, beneficiary_address, 0);

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }
}
