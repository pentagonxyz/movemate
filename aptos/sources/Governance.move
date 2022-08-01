// SPDX-License-Identifier: MIT
// Based on: OpenZeppelin Contracts

/// @title Governance
/// @notice On-chain governance. In your existing contracts, give on-chain access control to your contracts by requiring usage of your forum's signer (represented by its `SignerCapability`).
/// Then, when it's time to upgrade, create a governance proposal from your new module that calls `create_proposal<CoinType, ProposalCapabilityType>()`.
/// Tokenholders call `cast_vote<CoinType, ProposalCapabilityType>()` to cast votes.
/// When the proposal passes, call `execute_proposal<CoinType, ProposalCapabilityType>()` to retrieve the forum's `signer`.
module Movemate::Governance {
    use Std::ASCII::String;
    use Std::Signer;
    use Std::Vector;

    use AptosFramework::Account;
    use AptosFramework::BCS;
    use AptosFramework::Coin::{Self, Coin};
    use AptosFramework::Table::{Self, Table};
    use AptosFramework::Timestamp;
    use AptosFramework::TransactionContext;
    use AptosFramework::TypeInfo;

    use Movemate::Math;

    struct Forum<phantom CoinType> has key {
        voting_delay: u64,
        voting_period: u64,
        queue_period: u64,
        execution_window: u64,
        proposal_threshold: u64,
        approval_threshold: u64,
        cancellation_threshold: u64,
        proposals: vector<Proposal>,
        signer_capability: Account::SignerCapability
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
        let type_info = TypeInfo::type_of<CoinType>();
        let (sig, sig_cap) = Account::create_resource_account(forum, b"Movemate::Governance::Forum<" + BCS::to_bytes(TypeInfo::account_address(type_info)) + b"::" + TypeInfo::module_name(type_info) + b"::" + TypeInfo::struct_name(type_info) + b">");
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
        let sender = Signer::address_of(account);
        let coin_in = Coin::withdraw<CoinType>(account, amount);

        if (exists<CoinStore<CoinType>>(sender)) {
            Coin::merge(&mut borrow_global_mut<CoinStore<CoinType>>(sender).coin, coin_in);
        } else {
            move_to(account, CoinStore { coin: coin_in });
        };

        // Update checkpoints
        write_checkpoint<CoinType>(borrow_global<Delegate<CoinType>>(sender).delegatee, false, amount);
    }

    /// @dev Unlock coins locked for voting.
    public entry fun unlock_coins<CoinType>(account: &signer, amount: u64) acquires CoinStore, Checkpoints, Delegate {
        // Update checkpoints
        let sender = Signer::address_of(account);
        write_checkpoint<CoinType>(borrow_global<Delegate<CoinType>>(sender).delegatee, true, amount);

        // Move coin out
        Coin::deposit(sender, Coin::extract(&mut borrow_global_mut<CoinStore<CoinType>>(sender).coin, amount));
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
        let proposer_address = Signer::address_of(proposer);
        let proposer_votes = get_votes<CoinType>(proposer_address);
        let forum_res = borrow_global_mut<Forum<CoinType>>(forum_address);
        assert!(proposer_votes >= forum_res.proposal_threshold, 1000);

        // Add proposal to forum
        Vector::push_back(&mut forum_res.proposals, Proposal {
            name,
            metadata,
            votes: Table::new(),
            approval_votes: 0,
            cancellation_votes: 0,
            timestamp: Timestamp::now_seconds(),
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
        let proposal = Vector::borrow_mut(&mut forum_res.proposals, proposal_id);

        // Check timestamps
        let voting_start = proposal.timestamp + forum_res.voting_delay;
        let now = Timestamp::now_seconds();
        assert!(now >= voting_start, 1000);
        assert!(now < voting_start + forum_res.voting_period, 1000);

        // Get past votes
        let sender = Signer::address_of(account);
        let votes = get_past_votes<CoinType>(sender, voting_start);

        // Remove old vote if necessary
        if (Table::contains(&proposal.votes, sender)) {
            let old_vote = Table::remove(&mut proposal.votes, sender);
            assert!(vote != old_vote, 1000); // VOTE_NOT_CHANGED
            if (old_vote) *&mut proposal.approval_votes = *&proposal.approval_votes - votes
            else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes - votes;
        };

        // Cast new vote
        Table::add(&mut proposal.votes, sender, vote);
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
        let proposal = Vector::borrow_mut(&mut forum_res.proposals, proposal_id);

        // Check timestamps
        let post_queue = proposal.timestamp + forum_res.voting_delay + forum_res.voting_period + forum_res.queue_period;
        let now = Timestamp::now_seconds();
        assert!(now >= post_queue, 1000);
        let expiration = post_queue + forum_res.execution_window;
        assert!(now < expiration, 1000);
        assert!(!proposal.executed, 1000);
        assert!(TransactionContext::get_script_hash() == proposal.script_hash, 1000);

        // Check votes
        assert!(proposal.approval_votes >= forum_res.approval_threshold, 1000);
        assert!(proposal.cancellation_votes < forum_res.cancellation_threshold, 1000);

        // Set proposal as executed
        *&mut proposal.executed = true;

        // Return signer
        Account::get_signer_with_capability(&forum_res.signer_capability)
    }

    /// @dev Get the address `account` is currently delegating to.
    public fun delegates<CoinType>(account: address): address acquires Delegate {
        borrow_global<Delegate<CoinType>>(account).delegatee
    }

    /// @dev Gets the current votes balance for `account`
    public fun get_votes<CoinType>(account: address): u64 acquires Checkpoints {
        let checkpoints = &borrow_global<Checkpoints<CoinType>>(account).checkpoints;
        let pos = Vector::length(checkpoints);
        if (pos == 0) 0 else Vector::borrow(checkpoints, pos - 1).votes
    }

    /// @dev Retrieve the number of votes for `account` at the end of `blockNumber`.
    /// Requirements:
    /// - `timestamp` must have already happened
    public fun get_past_votes<CoinType>(account: address, timestamp: u64): u64 acquires Checkpoints {
        assert!(timestamp < Timestamp::now_seconds(), 1000);
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
        let high = Vector::length(ckpts);
        let low = 0;

        while (low < high) {
            let mid = Math::average(low, high);
            if (Vector::borrow(ckpts, mid).from_timestamp > timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        };

        if (high == 0) 0 else Vector::borrow(ckpts, high - 1).votes
    }

    /// @dev Change delegation for `delegator` to `delegatee`.
    public entry fun delegate<CoinType>(delegator: &signer, delegatee: address) acquires CoinStore, Checkpoints, Delegate {
        // Get delegator address and locked balance
        let delegator_address = Signer::address_of(delegator);
        let delegator_balance = Coin::value(&borrow_global<CoinStore<CoinType>>(delegator_address).coin);
        
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

        let pos = Vector::length(ckpts);
        let last_ckpt = Vector::borrow_mut(ckpts, pos - 1);
        let old_weight = if (pos == 0) 0 else last_ckpt.votes;
        let new_weight = if (subtract_not_add) old_weight - delta else old_weight + delta;
        let now = Timestamp::now_seconds();

        if (pos > 0 && last_ckpt.from_timestamp == now) {
            *&mut last_ckpt.votes = new_weight;
        } else {
            Vector::push_back(ckpts, Checkpoint {
                from_timestamp: now,
                votes: new_weight
            });
        };

        (old_weight, new_weight)
    }
}
