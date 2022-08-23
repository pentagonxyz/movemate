// SPDX-License-Identifier: UNLICENSED

/// @title virtual_block
/// @dev This module allows the creation of virtual blocks with transactions sorted by fees, turning transaction latency auctions into fee auctions.
/// Once you've created a new mempool (specifying a miner fee rate and a block time/delay), simply add entries to the block,
/// mine the entries (for a miner fee), and repeat. Extract mempool fees as necessary.
module movemate::virtual_block {
    use std::error;
    use std::vector;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

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
    public fun new_mempool<BidAssetType, EntryType>(miner_fee_rate: u64, block_time: u64): Mempool<BidAssetType, EntryType> {
        Mempool<BidAssetType, EntryType> {
            blocks: vector::singleton<CB<vector<EntryType>>>(crit_bit::empty<vector<EntryType>>()),
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
        // Add bid to block
        let bid_value = (coin::value(&bid) as u128);
        coin::merge(&mut mempool.current_block_bids, bid);

        // Add entry to tree
        let len = vector::length(&mempool.blocks);
        let block = vector::borrow_mut(&mut mempool.blocks, len - 1);
        if (crit_bit::has_key(block, bid_value)) vector::push_back(crit_bit::borrow_mut(block, bid_value), entry)
        else crit_bit::insert(block, bid_value, vector::singleton(entry));
    }

    /// @notice Validates the block time and distributes fees.
    public fun mine_entries<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, miner: address): CB<vector<EntryType>> {
        // Validate time now >= last block time + block delay
        let now = timestamp::now_microseconds();
        assert!(now >= mempool.last_block_timestamp + mempool.block_time, error::invalid_state(EBLOCK_TIME_NOT_PASSED));

        // Withdraw miner_fee_rate / 2**16 to the miner
        let miner_fee = coin::value(&mempool.current_block_bids) * mempool.miner_fee_rate / (1 << 16);
        coin::deposit(miner, coin::extract(&mut mempool.current_block_bids, miner_fee));

        // Send the rest to the mempool admin
        coin::merge(&mut mempool.mempool_fees, coin::extract_all(&mut mempool.current_block_bids));

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
    struct FakeMoneyCapabilities has key {
        mint_cap: coin::MintCapability<FakeMoney>,
        burn_cap: coin::BurnCapability<FakeMoney>,
        freeze_cap: coin::FreezeCapability<FakeMoney>,
    }

    #[test_only]
    struct TempMempool has key {
        mempool: Mempool<FakeMoney, FakeEntry>
    }

    #[test_only]
    fun fast_forward_microseconds(timestamp_microseconds: u64) {
        timestamp::update_global_time_for_test(timestamp::now_microseconds() + timestamp_microseconds);
    }

    #[test(miner = @0x1000, coin_creator = @movemate, aptos_framework = @aptos_framework)]
    public entry fun test_end_to_end(miner: signer, coin_creator: signer, aptos_framework: signer) {
        // start the clock
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        // mint fake coin
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );
        let coin_in_a = coin::mint<FakeMoney>(1234000000, &mint_cap);
        let coin_in_b = coin::mint<FakeMoney>(5678000000, &mint_cap);

        // create mempool
        let mempool = new_mempool<FakeMoney, FakeEntry>(1 << 14, 5000000); // 25% miner fee rate and 5 second block time

        // add entry
        add_entry(&mut mempool, FakeEntry { stuff: 1234 }, coin_in_a);

        // fast forward and add entry
        fast_forward_microseconds(3000000);
        add_entry(&mut mempool, FakeEntry { stuff: 5678 }, coin_in_b);

        // fast forward and mine block
        fast_forward_microseconds(3000000);
        let miner_address = std::signer::address_of(&miner);
        coin::register_for_test<FakeMoney>(&miner);
        let cb = mine_entries(&mut mempool, miner_address);
        assert!(coin::balance<FakeMoney>(miner_address) == (1234000000 + 5678000000) / 4, 0);

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
        coin::burn(mempool_fees, &burn_cap);

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            burn_cap,
            freeze_cap,
            mint_cap
        });
        move_to(&coin_creator, TempMempool {
            mempool,
        });
    }

    #[test(miner = @0x1000, coin_creator = @movemate, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 0x30000)]
    public entry fun test_mine_before_time(miner: signer, coin_creator: signer, aptos_framework: signer) {
        // start the clock
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        // mint fake coin
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );
        let coin_in = coin::mint<FakeMoney>(1234000000, &mint_cap);

        // create mempool
        let mempool = new_mempool<FakeMoney, FakeEntry>(1 << 14, 5000000); // 25% miner fee rate and 5 second block time

        // add entry
        add_entry(&mut mempool, FakeEntry { stuff: 1234 }, coin_in);

        // fast forward and try to mine
        fast_forward_microseconds(3000000);
        let miner_address = std::signer::address_of(&miner);
        coin::register_for_test<FakeMoney>(&miner);
        let cb = mine_entries(&mut mempool, miner_address);

        // destroy cb tree
        crit_bit::pop(&mut cb, 1234);
        crit_bit::destroy_empty(cb);

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            burn_cap,
            freeze_cap,
            mint_cap
        });
        move_to(&coin_creator, TempMempool {
            mempool,
        });
    }
}
