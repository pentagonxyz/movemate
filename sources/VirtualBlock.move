// SPDX-License-Identifier: UNLICENSED

/// @title VirtualBlock
/// @dev This module allows the creation of virtual blocks with transactions sorted by fees, turning transaction latency auctions into fee auctions.
/// Once you've created a new mempool (specifying a miner fee rate and a block time/delay), simply add entries to the block,
/// mine the entries (for a miner fee), and repeat. Extract mempool fees as necessary.
module Movemate::VirtualBlock {
    use std::vector;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

    use Econia::CritBit::{Self, CB};

    /// @notice Struct for a virtual block with entries sorted by bids.
    struct Mempool<phantom BidAssetType, EntryType> {
        blocks: vector<CB<EntryType>>,
        current_block_bids: Coin<BidAssetType>,
        last_block_timestamp: u64,
        mempool_fees: Coin<BidAssetType>,
        miner_fee_rate: u64,
        block_time: u64
    }

    /// @notice Creates a new mempool (specifying miner fee rate and block time/delay).
    public fun new_mempool<BidAssetType, EntryType>(miner_fee_rate: u64, block_time: u64): Mempool<BidAssetType, EntryType> {
        Mempool<BidAssetType, EntryType> {
            blocks: vector::singleton<CB<EntryType>>(CritBit::empty<EntryType>()),
            current_block_bids: coin::zero<BidAssetType>(),
            last_block_timestamp: timestamp::now_microseconds(),
            mempool_fees: coin::zero<BidAssetType>(),
            miner_fee_rate,
            block_time
        }
    }

    /// @notice Extracts all fees accrued by a mempool.
    public fun extract_mempool_fees<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>): Coin<BidAssetType> {
        coin::extract_all(&mut mempool.mempool_fees)
    }

    /// @notice Adds an entry to the latest virtual block.
    public fun add_entry<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, entry: EntryType, bid: Coin<BidAssetType>) {
        let coin_value = (coin::value(&bid) as u128);

        // Add bid to block
        coin::merge(&mut mempool.current_block_bids, bid);

        let blocks_length = vector::length(&mempool.blocks);

        // Add entry to tree
        let block = vector::borrow_mut(&mut mempool.blocks, blocks_length - 1);
        CritBit::insert(block, coin_value, entry);
    }

    /// @notice Validates the block time and distributes fees.
    public fun mine_entries<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, miner: address): CB<EntryType> {
        // Validate time now >= last block time + block delay
        let now = timestamp::now_microseconds();
        assert!(now >= mempool.last_block_timestamp + mempool.block_time, 1000);

        // Withdraw miner_fee_rate / 2**16 to the miner
        let miner_fee = coin::value(&mempool.current_block_bids) * mempool.miner_fee_rate / (1 << 16);
        coin::deposit(miner, coin::extract(&mut mempool.current_block_bids, miner_fee));

        // Send the rest to the mempool admin
        coin::merge(&mut mempool.mempool_fees, coin::extract_all(&mut mempool.current_block_bids));

        // Get last block
        let last_block = vector::pop_back(&mut mempool.blocks);

        // Create next block
        vector::push_back(&mut mempool.blocks, CritBit::empty<EntryType>());
        *&mut mempool.last_block_timestamp = timestamp::now_microseconds();

        // Return entries of last block
        last_block
    }
}
