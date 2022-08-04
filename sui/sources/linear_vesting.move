// SPDX-License-Identifier: MIT

/// @title linear_vesting
/// @dev This contract handles the vesting of coins for a given beneficiary. Custody of multiple coins
/// can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
/// The vesting schedule is customizable through the {vestedAmount} function.
/// Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
/// Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
/// be immediately releasable.
module movemate::linear_vesting {
    use std::option::{Self, Option};

    use sui::coin::{Self, Coin};
    use sui::object::{Self, Info};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct Wallet<phantom T> has key {
        info: Info,
        beneficiary: address,
        coin: Coin<T>,
        released: u64,
        start: u64,
        duration: u64,
        clawbacker: Option<address>
    }

    /// @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
    public entry fun init_wallet<T>(beneficiary: address, start: u64, duration: u64, clawbacker: Option<address>, ctx: &mut TxContext) {
        transfer::share_object(Wallet<T> {
            info: object::new(ctx),
            beneficiary,
            coin: coin::zero<T>(ctx),
            released: 0,
            start,
            duration,
            clawbacker
        });
    }

    /// @dev Deposits `coin_in` to `wallet`.
    public fun deposit<T>(wallet: &mut Wallet<T>, coin_in: Coin<T>) {
        coin::join(&mut wallet.coin, coin_in)
    }

    /// @notice Returns the vesting wallet details.
    public fun wallet_info<T>(wallet: &mut Wallet<T>): (address, u64, u64, u64, u64, Option<address>) {
        (wallet.beneficiary, coin::value(&wallet.coin), wallet.released, wallet.start, wallet.duration, wallet.clawbacker)
    }

    /// @dev Release the tokens that have already vested.
    public entry fun release<T>(wallet: &mut Wallet<T>, ctx: &mut TxContext) {
        // Release amount
        let releasable = vested_amount(wallet.start, wallet.duration, coin::value(&wallet.coin), wallet.released, tx_context::epoch(ctx)) - wallet.released;
        *&mut wallet.released = *&wallet.released + releasable;
        coin::split_and_transfer<T>(&mut wallet.coin, releasable, wallet.beneficiary, ctx);
    }

    /// @notice Claws back coins to the `clawbacker` if enabled.
    /// @dev TODO: Clawback capability.
    /// @dev TODO: Destroy wallet.
    public entry fun clawback<T>(wallet: &mut Wallet<T>, ctx: &mut TxContext) {
        // Check clawbacker address
        let sender = tx_context::sender(ctx);
        assert!(option::is_some(&wallet.clawbacker) && sender == *option::borrow(&wallet.clawbacker), 1000);

        // Release amount
        let releasable = vested_amount(wallet.start, wallet.duration, coin::value(&wallet.coin), wallet.released, tx_context::epoch(ctx)) - wallet.released;
        *&mut wallet.released = *&wallet.released + releasable;
        coin::split_and_transfer<T>(&mut wallet.coin, releasable, wallet.beneficiary, ctx);

        // Execute clawback
        let coin_out = &mut wallet.coin;
        let value = coin::value(coin_out);
        coin::split_and_transfer<T>(coin_out, value, sender, ctx);
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
