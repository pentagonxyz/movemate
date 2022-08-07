// SPDX-License-Identifier: UNLICENSED

/// @title VirtualBlock
/// @dev This module allows the creation of virtual blocks with transactions sorted by fees, turning transaction latency auctions into fee auctions.
/// Once you've created a new mempool (specifying a miner fee rate and a block time/delay), simply add entries to the block,
/// mine the entries (for a miner fee), and repeat. Extract mempool fees as necessary.
module movemate::virtual_block {
    use std::errors;
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};

    use movemate::crit_bit::{Self, CB};

    /// @dev When trying to mine a block before the block time has passed.
    const EBLOCK_TIME_NOT_PASSED: u64 = 0;

    /// @notice Struct for a virtual block with entries sorted by bids.
    struct Mempool<phantom BidAssetType, EntryType> has store {
        blocks: vector<CB<vector<EntryType>>>,
        current_block_bids: Coin<BidAssetType>,
        last_block_timestamp: u64,
        mempool_fees: Coin<BidAssetType>,
        miner_fee_rate: u64,
        block_time: u64
    }

    /// @notice Creates a new mempool (specifying miner fee rate and block time/delay).
    public fun new_mempool<BidAssetType, EntryType>(miner_fee_rate: u64, block_time: u64, ctx: &mut TxContext): Mempool<BidAssetType, EntryType> {
        Mempool<BidAssetType, EntryType> {
            blocks: vector::singleton<CB<vector<EntryType>>>(crit_bit::empty<vector<EntryType>>()),
            current_block_bids: coin::zero<BidAssetType>(ctx),
            last_block_timestamp: tx_context::epoch(ctx),
            mempool_fees: coin::zero<BidAssetType>(ctx),
            miner_fee_rate,
            block_time
        }
    }

    /// @notice Extracts all fees accrued by a mempool.
    public fun extract_mempool_fees<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, ctx: &mut TxContext): Coin<BidAssetType> {
        let value = coin::value(&mempool.mempool_fees);
        coin::take(coin::balance_mut(&mut mempool.mempool_fees), value, ctx)
    }

    /// @notice Adds an entry to the latest virtual block.
    public fun add_entry<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, entry: EntryType, bid: Coin<BidAssetType>) {
        // Add bid to block
        let bid_value = (coin::value(&bid) as u128);
        coin::join(&mut mempool.current_block_bids, bid);

        // Add entry to tree
        let len = vector::length(&mempool.blocks);
        let block = vector::borrow_mut(&mut mempool.blocks, len - 1);
        if (crit_bit::has_key(block, bid_value)) vector::push_back(crit_bit::borrow_mut(block, bid_value), entry)
        else crit_bit::insert(block, bid_value, vector::singleton(entry));
    }

    /// @notice Validates the block time and distributes fees.
    public fun mine_entries<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, miner: address, ctx: &mut TxContext): CB<vector<EntryType>> {
        // Validate time now >= last block time + block delay
        let now = tx_context::epoch(ctx);
        assert!(now >= mempool.last_block_timestamp + mempool.block_time, errors::invalid_state(EBLOCK_TIME_NOT_PASSED));

        // Withdraw miner_fee_rate / 2**16 to the miner
        let miner_fee = coin::value(&mempool.current_block_bids) * mempool.miner_fee_rate / (1 << 16);
        coin::split_and_transfer(&mut mempool.current_block_bids, miner_fee, miner, ctx);

        // Send the rest to the mempool admin
        let remaining = coin::value(&mempool.current_block_bids);
        coin::join(&mut mempool.mempool_fees, coin::take(coin::balance_mut(&mut mempool.current_block_bids), remaining, ctx));

        // Get last block
        let last_block = vector::pop_back(&mut mempool.blocks);

        // Create next block
        vector::push_back(&mut mempool.blocks, crit_bit::empty<vector<EntryType>>());
        *&mut mempool.last_block_timestamp = now;

        // Return entries of last block
        last_block
    }

    #[test_only]
    struct FakeEntry has store, drop {
        stuff: u64
    }

    #[test_only]
    struct FakeMoney { }

    #[test_only]
    struct TempMempool has key {
        mempool: Mempool<FakeMoney, FakeEntry>
    }

    #[test_only]
    const TEST_MINER_ADDR: address = @0xA11CE;

    #[test]
    public entry fun test_end_to_end() {
        // Test scenario
        let scenario = &mut test_scenario::begin(&TEST_MINER_ADDR);

        // Mint fake coin
        let coin_in_a = coin::mint_for_testing<FakeMoney>(1234000000, test_scenario::ctx(scenario));
        let coin_in_b = coin::mint_for_testing<FakeMoney>(5678000000, test_scenario::ctx(scenario));

        // create mempool
        let mempool = new_mempool<FakeMoney, FakeEntry>(1 << 14, 5, ctx); // 25% miner fee rate and 5 epoch block time

        // add entry
        add_entry(&mut mempool, FakeEntry { stuff: 1234 }, coin_in_a);

        // fast forward and add entry
        test_scenario::next_epoch(scenario);
        test_scenario::next_epoch(scenario);
        test_scenario::next_epoch(scenario);
        add_entry(&mut mempool, FakeEntry { stuff: 5678 }, coin_in_b);

        // fast forward and mine block
        test_scenario::next_epoch(scenario);
        test_scenario::next_epoch(scenario);
        test_scenario::next_epoch(scenario);
        let cb = mine_entries(&mut mempool, TEST_MINER_ADDR, ctx);
        assert!(coin::balance<FakeMoney>(TEST_MINER_ADDR) == (1234000000 + 5678000000) / 4, 0);

        // Loop through highest to lowest bid
        let last_bid = 0xFFFFFFFFFFFFFFFF;

        while (!crit_bit::is_empty(&cb)) {
            let bid = crit_bit::max_key(&cb);
            assert!(bid < last_bid, 1);
            crit_bit::pop(&mut cb, bid);
        };

        crit_bit::destroy_empty(cb);

        // extract mempool fees
        let mempool_fees = extract_mempool_fees(&mut mempool);
        assert!(coin::value(&mempool_fees) == (1234000000 + 5678000000) - ((1234000000 + 5678000000) / 4), 2);

        // clean up: we can't drop coins so we burn them
        coin::destroy_for_testing(mempool_fees);

        // clean up: we can't drop mempool so we store it
        transfer::transfer(coin_creator_address, TempMempool {
            mempool,
        });
    }

    #[test(miner = @0x1000, coin_creator = @0x1001)]
    #[expected_failure(abort_code = 0x50000)]
    public entry fun test_mine_before_time(miner: signer, coin_creator: signer) {
        // Test scenario
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);

        // Mint fake coin
        let coin_in = coin::mint_for_testing<FakeMoney>(1234000000, test_scenario::ctx(scenario));

        // create mempool
        let mempool = new_mempool<FakeMoney, FakeEntry>(1 << 14, 5, ctx); // 25% miner fee rate and 5 epoch block time

        // add entry
        add_entry(&mut mempool, FakeEntry { stuff: 1234 }, coin_in);

        // fast forward and try to mine
        test_scenario::next_epoch(scenario);
        test_scenario::next_epoch(scenario);
        test_scenario::next_epoch(scenario);
        let cb = mine_entries(&mut mempool, TEST_MINER_ADDR, ctx);

        // destroy cb tree
        crit_bit::pop(&mut cb, 1234);
        crit_bit::destroy_empty(cb);

        // clean up: we can't drop mempool so we store it
        transfer::transfer(coin_creator_address, TempMempool {
            mempool,
        });
    }
}
