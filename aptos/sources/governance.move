// SPDX-License-Identifier: MIT
// Based on: OpenZeppelin Contracts

/// @title governance
/// @notice On-chain governance. In your existing contracts, give on-chain access control to your contracts by requiring usage of your forum's signer (represented by its `SignerCapability`).
/// Then, when it's time to upgrade, create a governance proposal from your new module that calls `create_proposal<CoinType, ProposalCapabilityType>()`.
/// Tokenholders call `cast_vote<CoinType, ProposalCapabilityType>()` to cast votes.
/// When the proposal passes, call `execute_proposal<CoinType, ProposalCapabilityType>()` to retrieve the forum's `signer`.
/// @dev TODO: Finish tests.
module movemate::governance {
    use std::error;
    use std::signer;
    use std::string::String;
    use std::vector;

    use aptos_std::table::{Self, Table};
    use aptos_std::type_info;

    use aptos_framework::account;
    use aptos_framework::bcs;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context;

    use movemate::math;
    
    /// @dev When the proposer's votes are below the threshold required to create a proposal.
    const EPROPOSER_VOTES_BELOW_THRESHOLD: u64 = 0;

    /// @dev When trying to vote when the voting period has not yet started.
    const EVOTING_NOT_STARTED: u64 = 1;

    /// @dev When trying to vote when the voting period has ended.
    const EVOTING_ENDED: u64 = 2;

    /// @dev When trying to cast the same vote for the same proposal twice.
    const EVOTE_NOT_CHANGED: u64 = 3;

    /// @dev When trying to execute a proposal whose queue period has not yet ended.
    const EQUEUE_PERIOD_NOT_OVER: u64 = 4;

    /// @dev When trying to execute an expired proposal--i.e., one whose execution window has passed.
    const EPROPOSAL_EXPIRED: u64 = 5;

    /// @dev When trying to execute a proposal that has already been executed.
    const EPROPOSAL_ALREADY_EXECUTED: u64 = 6;

    /// @dev When trying to execute a proposal from the wrong script.
    const ESCRIPT_HASH_MISMATCH: u64 = 7;

    /// @dev When trying to execute an unapproved proposal.
    const EAPPROVAL_VOTES_BELOW_THRESHOLD: u64 = 8;

    /// @dev When trying to execute a cancelled proposal.
    const ECANCELLATION_VOTES_ABOVE_THRESHOLD: u64 = 9;

    /// @dev When trying to `get_past_votes` for a timestamp in the future.
    const ETIMESTAMP_IN_FUTURE: u64 = 10;

    struct Forum<phantom CoinType> has key {
        voting_delay: u64,
        voting_period: u64,
        queue_period: u64,
        execution_window: u64,
        proposal_threshold: u64,
        approval_threshold: u64,
        cancellation_threshold: u64,
        proposals: vector<Proposal>,
        signer_capability: account::SignerCapability
    }

    struct Proposal has store {
        name: String,
        metadata: vector<u8>,
        votes: Table<address, bool>,
        approval_votes: u64,
        cancellation_votes: u64,
        timestamp: u64,
        script_hash: vector<u8>,
        executed: bool
    }

    struct Delegate<phantom CoinType> has key {
        delegatee: address
    }

    struct Checkpoint has store {
        votes: u64,
        from_timestamp: u64
    }

    struct Checkpoints<phantom CoinType> has key {
        checkpoints: vector<Checkpoint>
    }

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    /// @notice Initiate a new forum under the signer provided.
    public entry fun init_forum<CoinType>(
        forum: &signer,
        voting_delay: u64,
        voting_period: u64,
        queue_period: u64,
        execution_window: u64,
        proposal_threshold: u64,
        approval_threshold: u64,
        cancellation_threshold: u64
    ) {
        let type_info = type_info::type_of<CoinType>();
        let seed = b"movemate::governance::Forum<";
        vector::append(&mut seed, bcs::to_bytes(&type_info::account_address(&type_info))); // TODO: Convert to hex?
        vector::append(&mut seed, b"::");
        vector::append(&mut seed, type_info::module_name(&type_info));
        vector::append(&mut seed, b"::");
        vector::append(&mut seed, type_info::struct_name(&type_info));
        vector::append(&mut seed, b">");
        let (_, sig_cap) = account::create_resource_account(forum, seed);
        move_to(forum, Forum<CoinType> {
            voting_delay,
            voting_period,
            queue_period,
            execution_window,
            proposal_threshold,
            approval_threshold,
            cancellation_threshold,
            proposals: vector::empty(),
            signer_capability: sig_cap
        });
    }

    /// @notice Lock your coins for voting in the specified forum.
    public entry fun lock_coins<CoinType>(account: &signer, amount: u64) acquires CoinStore, Checkpoints, Delegate {
        // Move coin in
        let sender = signer::address_of(account);
        let coin_in = coin::withdraw<CoinType>(account, amount);

        if (exists<CoinStore<CoinType>>(sender)) {
            coin::merge(&mut borrow_global_mut<CoinStore<CoinType>>(sender).coin, coin_in);
        } else {
            move_to(account, CoinStore { coin: coin_in });
        };

        // Update checkpoints
        write_checkpoint<CoinType>(borrow_global<Delegate<CoinType>>(sender).delegatee, false, amount);
    }

    /// @dev Unlock coins locked for voting.
    public entry fun unlock_coins<CoinType>(account: &signer, amount: u64) acquires CoinStore, Checkpoints, Delegate {
        // Update checkpoints
        let sender = signer::address_of(account);
        write_checkpoint<CoinType>(borrow_global<Delegate<CoinType>>(sender).delegatee, true, amount);

        // Move coin out
        coin::deposit(sender, coin::extract(&mut borrow_global_mut<CoinStore<CoinType>>(sender).coin, amount));
    }

    /// @notice Create a new proposal to allow a certain script hash to retrieve the signer.
    public entry fun create_proposal<CoinType>(
        forum_address: address,
        proposer: &signer,
        script_hash: vector<u8>,
        name: String,
        metadata: vector<u8>,
    ) acquires Forum, Checkpoints {
        // Validate !exists and proposer votes >= proposer threshold
        let proposer_address = signer::address_of(proposer);
        let proposer_votes = get_votes<CoinType>(proposer_address);
        let forum_res = borrow_global_mut<Forum<CoinType>>(forum_address);
        assert!(proposer_votes >= forum_res.proposal_threshold, error::permission_denied(EPROPOSER_VOTES_BELOW_THRESHOLD));

        // Add proposal to forum
        vector::push_back(&mut forum_res.proposals, Proposal {
            name,
            metadata,
            votes: table::new(),
            approval_votes: 0,
            cancellation_votes: 0,
            timestamp: timestamp::now_seconds(),
            script_hash,
            executed: false
        });
    }

    public entry fun cast_vote<CoinType>(
        account: &signer,
        forum_address: address,
        proposal_id: u64,
        vote: bool
    ) acquires Forum, Checkpoints {
        // Get proposal and forum
        let forum_res = borrow_global_mut<Forum<CoinType>>(forum_address);
        let proposal = vector::borrow_mut(&mut forum_res.proposals, proposal_id);

        // Check timestamps
        let voting_start = proposal.timestamp + forum_res.voting_delay;
        let now = timestamp::now_seconds();
        assert!(now >= voting_start, error::invalid_state(EVOTING_NOT_STARTED));
        assert!(now < voting_start + forum_res.voting_period, error::invalid_state(EVOTING_ENDED));

        // Get past votes
        let sender = signer::address_of(account);
        let votes = get_past_votes<CoinType>(sender, voting_start);

        // Remove old vote if necessary
        if (table::contains(&proposal.votes, sender)) {
            let old_vote = table::remove(&mut proposal.votes, sender);
            assert!(vote != old_vote, error::already_exists(EVOTE_NOT_CHANGED));
            if (old_vote) *&mut proposal.approval_votes = *&proposal.approval_votes - votes
            else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes - votes;
        };

        // Cast new vote
        table::add(&mut proposal.votes, sender, vote);
        if (vote) *&mut proposal.approval_votes = *&proposal.approval_votes + votes
        else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes + votes;
    }

    /// @notice Executes a proposal by returning the new module the governance signer.
    public fun execute_proposal<CoinType>(
        forum_address: address,
        proposal_id: u64
    ): signer acquires Forum {
        // Get proposal and forum
        let forum_res = borrow_global_mut<Forum<CoinType>>(forum_address);
        let proposal = vector::borrow_mut(&mut forum_res.proposals, proposal_id);

        // Check timestamps
        let post_queue = proposal.timestamp + forum_res.voting_delay + forum_res.voting_period + forum_res.queue_period;
        let now = timestamp::now_seconds();
        assert!(now >= post_queue, error::invalid_state(EQUEUE_PERIOD_NOT_OVER));
        let expiration = post_queue + forum_res.execution_window;
        assert!(now < expiration, error::invalid_state(EPROPOSAL_EXPIRED));
        assert!(!proposal.executed, error::invalid_state(EPROPOSAL_ALREADY_EXECUTED));
        assert!(transaction_context::get_script_hash() == proposal.script_hash, error::permission_denied(ESCRIPT_HASH_MISMATCH));

        // Check votes
        assert!(proposal.approval_votes >= forum_res.approval_threshold, error::invalid_state(EAPPROVAL_VOTES_BELOW_THRESHOLD));
        assert!(proposal.cancellation_votes < forum_res.cancellation_threshold, error::invalid_state(ECANCELLATION_VOTES_ABOVE_THRESHOLD));

        // Set proposal as executed
        *&mut proposal.executed = true;

        // Return signer
        account::create_signer_with_capability(&forum_res.signer_capability)
    }

    /// @dev Get the address `account` is currently delegating to.
    public fun delegates<CoinType>(account: address): address acquires Delegate {
        borrow_global<Delegate<CoinType>>(account).delegatee
    }

    /// @dev Gets the current votes balance for `account`
    public fun get_votes<CoinType>(account: address): u64 acquires Checkpoints {
        let checkpoints = &borrow_global<Checkpoints<CoinType>>(account).checkpoints;
        let pos = vector::length(checkpoints);
        if (pos == 0) 0 else vector::borrow(checkpoints, pos - 1).votes
    }

    /// @dev Retrieve the number of votes for `account` at the end of `blockNumber`.
    /// Requirements:
    /// - `timestamp` must have already happened
    public fun get_past_votes<CoinType>(account: address, timestamp: u64): u64 acquires Checkpoints {
        assert!(timestamp <= timestamp::now_seconds(), error::invalid_argument(ETIMESTAMP_IN_FUTURE));
        checkpoints_lookup<CoinType>(account, timestamp)
    }

    /// @dev Lookup a value in a list of (sorted) checkpoints.
    fun checkpoints_lookup<CoinType>(account: address, timestamp: u64): u64 acquires Checkpoints {
        let ckpts = &borrow_global<Checkpoints<CoinType>>(account).checkpoints;

        // We run a binary search to look for the earliest checkpoint taken after `blockNumber`.
        //
        // During the loop, the index of the wanted checkpoint remains in the range [low-1, high).
        // With each iteration, either `low` or `high` is moved towards the middle of the range to maintain the invariant.
        // - If the middle checkpoint is after `timestamp`, we look in [low, mid)
        // - If the middle checkpoint is before or equal to `timestamp`, we look in [mid+1, high)
        // Once we reach a single value (when low == high), we've found the right checkpoint at the index high-1, if not
        // out of bounds (in which case we're looking too far in the past and the result is 0).
        // Note that if the latest checkpoint available is exactly for `timestamp`, we end up with an index that is
        // past the end of the array, so we technically don't find a checkpoint after `timestamp`, but it works out
        // the same.
        let high = vector::length(ckpts);
        let low = 0;

        while (low < high) {
            let mid = math::average(low, high);
            if (vector::borrow(ckpts, mid).from_timestamp > timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        };

        if (high == 0) 0 else vector::borrow(ckpts, high - 1).votes
    }

    /// @dev Change delegation for `delegator` to `delegatee`.
    public entry fun delegate<CoinType>(delegator: &signer, delegatee: address) acquires CoinStore, Checkpoints, Delegate {
        // Get delegator address and locked balance
        let delegator_address = signer::address_of(delegator);
        let delegator_balance = coin::value(&borrow_global<CoinStore<CoinType>>(delegator_address).coin);
        
        if (exists<Delegate<CoinType>>(delegator_address)) {
            // Update delegatee (removing old delegatee's votes)
            let delegate_ref = &mut borrow_global_mut<Delegate<CoinType>>(delegator_address).delegatee;
            write_checkpoint<CoinType>(*delegate_ref, true, delegator_balance);
            *delegate_ref = delegatee;
        } else {
            // Add delegatee
            move_to(delegator, Delegate<CoinType> { delegatee });
        };

        // Add votes to new delegatee
        write_checkpoint<CoinType>(delegatee, false, delegator_balance);
    }

    /// @dev Internal function to add a votes checkpoint.
    fun write_checkpoint<CoinType>(account: address, subtract_not_add: bool, delta: u64): (u64, u64) acquires Checkpoints {
        let ckpts = &mut borrow_global_mut<Checkpoints<CoinType>>(account).checkpoints;
        let pos = vector::length(ckpts);
        let now = timestamp::now_seconds();

        if (pos > 0) {
            let last_ckpt = vector::borrow_mut(ckpts, pos - 1);
            let old_weight = last_ckpt.votes;
            let new_weight = if (subtract_not_add) old_weight - delta else old_weight + delta;

            if (last_ckpt.from_timestamp == now) {
                *&mut last_ckpt.votes = new_weight;
            } else {
                vector::push_back(ckpts, Checkpoint {
                    from_timestamp: now,
                    votes: new_weight
                });
            };

            (old_weight, new_weight)
        } else {
            let old_weight = 0;
            let new_weight = if (subtract_not_add) old_weight - delta else old_weight + delta;

            vector::push_back(ckpts, Checkpoint {
                from_timestamp: now,
                votes: new_weight
            });

            (old_weight, new_weight)
        }
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

    #[test(forum_creator = @0x1000, voter_a = @0x1001, voter_b = @0x1002, voter_c = @0x1003, voter_d = @0x1004, coin_creator = @0x1005)]
    public entry fun test_end_to_end(forum_creator: signer, voter_a: signer, voter_b: signer, voter_c: signer, voter_d: signer, coin_creator: signer) acquires Forum, CoinStore, Checkpoints, Delegate {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );

        coin::register_for_test<FakeMoney>(&voter_a);
        coin::register_for_test<FakeMoney>(&voter_b);
        coin::register_for_test<FakeMoney>(&voter_c);
        coin::register_for_test<FakeMoney>(&voter_d);
        let voter_a_address = signer::address_of(&voter_a);
        let voter_b_address = signer::address_of(&voter_b);
        let voter_c_address = signer::address_of(&voter_c);
        let voter_d_address = signer::address_of(&voter_d);
        coin::deposit(voter_a_address, coin::mint<FakeMoney>(1234567890, &mint_cap));
        coin::deposit(voter_b_address, coin::mint<FakeMoney>(400000000, &mint_cap));
        coin::deposit(voter_c_address, coin::mint<FakeMoney>(600000000, &mint_cap));
        coin::deposit(voter_d_address, coin::mint<FakeMoney>(1100000000, &mint_cap));

        // Init forum
        init_forum<FakeMoney>(
            &forum_creator,
            86400 * 2,
            86400 * 3,
            86400 * 2,
            86400 * 2,
            1200000000,
            2000000000,
            1500000000
        );

        // Lock coins and delegate from C to A
        lock_coins<FakeMoney>(&voter_a, 1234567890);
        unlock_coins<FakeMoney>(&voter_a, 34567890);
        assert!(coin::balance<FakeMoney>(voter_a_address) == 34567890, 0);
        assert!(get_votes<FakeMoney>(voter_a_address) == 1200000000, 1);
        lock_coins<FakeMoney>(&voter_b, 400000000);
        lock_coins<FakeMoney>(&voter_c, 600000000);
        lock_coins<FakeMoney>(&voter_d, 1100000000);
        delegate<FakeMoney>(&voter_c, voter_a_address);
        assert!(get_votes<FakeMoney>(voter_a_address) == 1800000000, 2);
        assert!(get_votes<FakeMoney>(voter_b_address) == 400000000, 3);
        assert!(get_votes<FakeMoney>(voter_c_address) == 0, 4);
        assert!(get_votes<FakeMoney>(voter_d_address) == 1100000000, 5);

        // Create proposal from address A
        let forum_address = signer::address_of(&forum_creator);
        create_proposal<FakeMoney>(
            forum_address,
            &voter_a,
            transaction_context::get_script_hash(),
            std::string::utf8(b"Test"),
            b"Example"
        );

        // Cast votes
        fast_forward_seconds(86400 * 2);
        cast_vote<FakeMoney>(&voter_a, forum_address, 0, true);
        cast_vote<FakeMoney>(&voter_b, forum_address, 0, true);
        cast_vote<FakeMoney>(&voter_c, forum_address, 0, false);
        cast_vote<FakeMoney>(&voter_d, forum_address, 0, false);

        // Execute proposal
        fast_forward_seconds(86400 * 5);
        let gov_signer = execute_proposal<FakeMoney>(
            forum_address,
            0
        );

        // Check signer
        let seed = b"movemate::governance::Forum<";
        vector::append(&mut seed, bcs::to_bytes(&@movemate));
        vector::append(&mut seed, b"::governance::FakeMoney>");
        let address_bytes = bcs::to_bytes(&forum_address);
        vector::append(&mut address_bytes, seed);
        let expected_gov_signer_address = account::create_address_for_test(std::hash::sha3_256(address_bytes));
        assert!(signer::address_of(&gov_signer) == expected_gov_signer_address, 6);

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }

    #[test(forum_creator = @0x1000, voter_a = @0x1001, voter_b = @0x1002, voter_c = @0x1003, coin_creator = @0x1004)]
    #[expected_failure(abort_code = 0x30009)]
    public entry fun test_proposal_cancellation(forum_creator: signer, voter_a: signer, voter_b: signer, voter_c: signer, coin_creator: signer) acquires Forum, CoinStore, Checkpoints, Delegate {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );

        coin::register_for_test<FakeMoney>(&voter_a);
        coin::register_for_test<FakeMoney>(&voter_b);
        coin::register_for_test<FakeMoney>(&voter_c);
        let voter_a_address = signer::address_of(&voter_a);
        let voter_b_address = signer::address_of(&voter_b);
        let voter_c_address = signer::address_of(&voter_c);
        coin::deposit(voter_a_address, coin::mint<FakeMoney>(1800000000, &mint_cap));
        coin::deposit(voter_b_address, coin::mint<FakeMoney>(400000000, &mint_cap));
        coin::deposit(voter_c_address, coin::mint<FakeMoney>(1100000000, &mint_cap));

        // Init forum
        init_forum<FakeMoney>(
            &forum_creator,
            86400 * 2,
            86400 * 3,
            86400 * 2,
            86400 * 2,
            1200000000,
            1800000000,
            1500000000
        );

        // Lock coins
        lock_coins<FakeMoney>(&voter_a, 1800000000);
        lock_coins<FakeMoney>(&voter_b, 400000000);
        lock_coins<FakeMoney>(&voter_c, 1100000000);
        assert!(get_votes<FakeMoney>(voter_a_address) == 1800000000, 0);
        assert!(get_votes<FakeMoney>(voter_b_address) == 400000000, 1);
        assert!(get_votes<FakeMoney>(voter_c_address) == 1100000000, 2);

        // Create proposal from address A
        let forum_address = signer::address_of(&forum_creator);
        create_proposal<FakeMoney>(
            forum_address,
            &voter_a,
            transaction_context::get_script_hash(),
            std::string::utf8(b"Test"),
            b"Example"
        );

        // Cast votes
        fast_forward_seconds(86400 * 2);
        cast_vote<FakeMoney>(&voter_a, forum_address, 0, true);
        cast_vote<FakeMoney>(&voter_b, forum_address, 0, false);
        cast_vote<FakeMoney>(&voter_c, forum_address, 0, false);

        // Execute proposal
        fast_forward_seconds(86400 * 5);
        execute_proposal<FakeMoney>(
            forum_address,
            0
        );

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }

    #[test(forum_creator = @0x1000, voter_a = @0x1001, voter_b = @0x1002, coin_creator = @0x1003)]
    #[expected_failure(abort_code = 0x30008)]
    public entry fun test_proposal_lack_of_quorum(forum_creator: signer, voter_a: signer, voter_b: signer, coin_creator: signer) acquires Forum, CoinStore, Checkpoints, Delegate {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );

        coin::register_for_test<FakeMoney>(&voter_a);
        coin::register_for_test<FakeMoney>(&voter_b);
        let voter_a_address = signer::address_of(&voter_a);
        let voter_b_address = signer::address_of(&voter_b);
        coin::deposit(voter_a_address, coin::mint<FakeMoney>(1700000000, &mint_cap));
        coin::deposit(voter_b_address, coin::mint<FakeMoney>(400000000, &mint_cap));

        // Init forum
        init_forum<FakeMoney>(
            &forum_creator,
            86400 * 2,
            86400 * 3,
            86400 * 2,
            86400 * 2,
            1200000000,
            1800000000,
            1500000000
        );

        // Lock coins
        lock_coins<FakeMoney>(&voter_a, 1700000000);
        lock_coins<FakeMoney>(&voter_b, 400000000);
        assert!(get_votes<FakeMoney>(voter_a_address) == 1700000000, 0);
        assert!(get_votes<FakeMoney>(voter_b_address) == 400000000, 1);

        // Create proposal from address A
        let forum_address = signer::address_of(&forum_creator);
        create_proposal<FakeMoney>(
            forum_address,
            &voter_a,
            transaction_context::get_script_hash(),
            std::string::utf8(b"Test"),
            b"Example"
        );

        // Cast votes
        fast_forward_seconds(86400 * 2);
        cast_vote<FakeMoney>(&voter_a, forum_address, 0, true);
        cast_vote<FakeMoney>(&voter_b, forum_address, 0, false);

        // Execute proposal
        fast_forward_seconds(86400 * 5);
        execute_proposal<FakeMoney>(
            forum_address,
            0
        );

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }

    #[test(forum_creator = @0x1000, voter_a = @0x1001, voter_b = @0x1002, coin_creator = @0x1003)]
    #[expected_failure(abort_code = 0x50007)]
    public entry fun test_proposal_wrong_script_hash(forum_creator: signer, voter_a: signer, voter_b: signer, coin_creator: signer) acquires Forum, CoinStore, Checkpoints, Delegate {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );

        coin::register_for_test<FakeMoney>(&voter_a);
        coin::register_for_test<FakeMoney>(&voter_b);
        let voter_a_address = signer::address_of(&voter_a);
        let voter_b_address = signer::address_of(&voter_b);
        coin::deposit(voter_a_address, coin::mint<FakeMoney>(1800000000, &mint_cap));
        coin::deposit(voter_b_address, coin::mint<FakeMoney>(400000000, &mint_cap));

        // Init forum
        init_forum<FakeMoney>(
            &forum_creator,
            86400 * 2,
            86400 * 3,
            86400 * 2,
            86400 * 2,
            1200000000,
            1800000000,
            1500000000
        );

        // Lock coins
        lock_coins<FakeMoney>(&voter_a, 1800000000);
        lock_coins<FakeMoney>(&voter_b, 400000000);
        assert!(get_votes<FakeMoney>(voter_a_address) == 1800000000, 0);
        assert!(get_votes<FakeMoney>(voter_b_address) == 400000000, 1);

        // Create proposal from address A
        let forum_address = signer::address_of(&forum_creator);
        let script_hash = transaction_context::get_script_hash();
        let random_byte_ref = vector::borrow_mut(&mut script_hash, 7);
        *random_byte_ref = if (*random_byte_ref == 123) 45 else 123; // Mess up the script hash on purpose
        create_proposal<FakeMoney>(
            forum_address,
            &voter_a,
            script_hash,
            std::string::utf8(b"Test"),
            b"Example"
        );

        // Cast votes
        fast_forward_seconds(86400 * 2);
        cast_vote<FakeMoney>(&voter_a, forum_address, 0, true);
        cast_vote<FakeMoney>(&voter_b, forum_address, 0, false);

        // Execute proposal
        fast_forward_seconds(86400 * 5);
        execute_proposal<FakeMoney>(
            forum_address,
            0
        );

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }

    #[test(forum_creator = @0x1000, voter_a = @0x1001, coin_creator = @0x1002)]
    #[expected_failure(abort_code = 0x50000)]
    public entry fun test_unqualified_proposer(forum_creator: signer, voter_a: signer, coin_creator: signer) acquires Forum, CoinStore, Checkpoints, Delegate {
        // mint fake coin
        let (mint_cap, burn_cap) = coin::initialize<FakeMoney>(
            &coin_creator,
            std::string::utf8(b"Fake Money A"),
            std::string::utf8(b"FMA"),
            6,
            true
        );

        coin::register_for_test<FakeMoney>(&voter_a);
        let voter_a_address = signer::address_of(&voter_a);
        coin::deposit(voter_a_address, coin::mint<FakeMoney>(800000000, &mint_cap));

        // Init forum
        init_forum<FakeMoney>(
            &forum_creator,
            86400 * 2,
            86400 * 3,
            86400 * 2,
            86400 * 2,
            1200000000,
            1800000000,
            1500000000
        );

        // Lock coins
        lock_coins<FakeMoney>(&voter_a, 800000000);
        assert!(get_votes<FakeMoney>(voter_a_address) == 800000000, 0);

        // Attempt to create proposal from address A
        let forum_address = signer::address_of(&forum_creator);
        create_proposal<FakeMoney>(
            forum_address,
            &voter_a,
            transaction_context::get_script_hash(),
            std::string::utf8(b"Test"),
            b"Example"
        );

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities {
            mint_cap: mint_cap,
            burn_cap: burn_cap,
        });
    }
}
