// SPDX-License-Identifier: UNLICENSED

/// @title Governance
/// @notice On-chain governance. In your existing contracts, give on-chain access control to your contracts by requiring the use of a `GovernanceCapability<CoinType>` with `verify_governance_capability<CoinType>(governance_capability: &GovernanceCapability<CoinType>, forum_address: address)`
/// Then, when it's time to upgrade, create a governance proposal from your new module that calls `create_proposal<CoinType, ProposalCapabilityType>()`.
/// Tokenholders call `cast_vote<CoinType, ProposalCapabilityType>()` to cast votes.
/// When the proposal passes, call `execute_proposal<CoinType, ProposalCapabilityType>()` to retrieve a copy of the `GovernanceCapability<CoinType>`.
module Movemate::Governance {
    use std::string::String;
    use std::signer;
    use std::vector;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::table::{Self, Table};
    use aptos_framework::timestamp;

    use Movemate::Math;

    struct Forum<phantom CoinType> has key {
        voting_delay: u64,
        voting_period: u64,
        queue_period: u64,
        execution_window: u64,
        proposal_threshold: u64,
        approval_threshold: u64,
        cancellation_threshold: u64
    }

    struct Proposal<phantom CoinType, phantom ProposalCapability> has key {
        name: String,
        metadata: vector<u8>,
        votes: Table<address, bool>,
        approval_votes: u64,
        cancellation_votes: u64,
        timestamp: u64
    }

    struct GovernanceCapability<phantom CoinType> has drop {
        forum_address: address,
        expiration: u64
    }

    struct Delegate has key {
        delegatee: address
    }

    struct Checkpoint has store {
        votes: u64,
        from_timestamp: u64
    }

    struct Checkpoints has key {
        checkpoints: vector<Checkpoint>
    }

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    /// @notice Checks if a governance capability matches the forum address and is unexpired. For use in an existing contract.
    public fun verify_governance_capability<CoinType>(governance_capability: &GovernanceCapability<CoinType>, forum_address: address): bool {
        governance_capability.forum_address == forum_address && timestamp::now_seconds() < governance_capability.expiration
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
        move_to(forum, Forum<CoinType> {
            voting_delay,
            voting_period,
            queue_period,
            execution_window,
            proposal_threshold,
            approval_threshold,
            cancellation_threshold
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
        write_checkpoint(borrow_global<Delegate>(sender).delegatee, false, amount);
    }

    /// @dev Unlock coins locked for voting.
    fun unlock_coins<CoinType>(account: &signer, amount: u64) acquires CoinStore, Checkpoints, Delegate {
        // Update checkpoints
        let sender = signer::address_of(account);
        write_checkpoint(borrow_global<Delegate>(sender).delegatee, true, amount);

        // Move coin out
        coin::deposit(sender, coin::extract(&mut borrow_global_mut<CoinStore<CoinType>>(sender).coin, amount));
    }

    /// @notice Create a new proposal, requiring the use of ProposalCapabilityType to execute it.
    public fun create_proposal<CoinType, ProposalCapabilityType>(
        forum: &signer,
        proposer: &signer,
        _proposal_capability: &ProposalCapabilityType,
        name: String,
        metadata: vector<u8>,
    ) acquires Forum, Checkpoints {
        // Validate !exists and proposer votes >= proposer threshold
        let forum_address = signer::address_of(forum);
        assert!(!exists<Proposal<CoinType, ProposalCapabilityType>>(forum_address), 1000);
        let proposer_address = signer::address_of(proposer);
        let proposer_votes = get_votes(proposer_address);
        let forum_res = borrow_global<Forum<CoinType>>(forum_address);
        assert!(proposer_votes >= forum_res.proposal_threshold, 1000);

        // Add proposal to forum
        move_to(forum, Proposal<CoinType, ProposalCapabilityType> {
            name,
            metadata,
            votes: table::new(),
            approval_votes: 0,
            cancellation_votes: 0,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun cast_vote<CoinType, ProposalCapabilityType>(
        account: &signer,
        forum_address: address,
        vote: bool
    ) acquires Forum, Proposal, Checkpoints {
        // Get proposal and forum
        let proposal = borrow_global_mut<Proposal<CoinType, ProposalCapabilityType>>(forum_address);
        let forum_res = borrow_global<Forum<CoinType>>(forum_address);

        // Check timestamps
        let voting_start = proposal.timestamp + forum_res.voting_delay;
        assert!(timestamp::now_seconds() >= voting_start, 1000);
        assert!(timestamp::now_seconds() < voting_start + forum_res.voting_period, 1000);

        // Get past votes
        let sender = signer::address_of(account);
        let votes = get_past_votes(sender, voting_start);

        // Remove old vote if necessary
        if (table::contains(&proposal.votes, sender)) {
            let old_vote = table::remove(&mut proposal.votes, sender);
            assert!(vote != old_vote, 1000); // VOTE_NOT_CHANGED
            if (old_vote) *&mut proposal.approval_votes = *&proposal.approval_votes - votes
            else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes - votes;
        };

        // Cast new vote
        table::add(&mut proposal.votes, sender, vote);
        if (vote) *&mut proposal.approval_votes = *&proposal.approval_votes + votes
        else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes + votes;
    }

    /// @notice Executes a proposal by returning the new contract a GovernanceCapability.
    public fun execute_proposal<CoinType, ProposalCapabilityType>(
        forum_address: address,
        _proposal_capacility: &ProposalCapabilityType
    ): GovernanceCapability<CoinType> acquires Forum, Proposal {
        // Get proposal and forum
        let proposal = borrow_global<Proposal<CoinType, ProposalCapabilityType>>(forum_address);
        let forum_res = borrow_global<Forum<CoinType>>(forum_address);

        // Check timestamps
        let post_queue = proposal.timestamp + forum_res.voting_delay + forum_res.voting_period + forum_res.queue_period;
        assert!(timestamp::now_seconds() >= post_queue, 1000);
        let expiration = post_queue + forum_res.execution_window;
        assert!(timestamp::now_seconds() < expiration, 1000);

        // Check votes
        assert!(proposal.approval_votes >= forum_res.approval_threshold, 1000);
        assert!(proposal.cancellation_votes < forum_res.cancellation_threshold, 1000);

        // Return GovernanceCapability with forum address and expiration date
        GovernanceCapability<CoinType> { forum_address, expiration }
    }

    /// @dev Get the address `account` is currently delegating to.
    public fun delegates(account: address): address acquires Delegate {
        borrow_global<Delegate>(account).delegatee
    }

    /// @dev Gets the current votes balance for `account`
    public fun get_votes(account: address): u64 acquires Checkpoints {
        let checkpoints = &borrow_global<Checkpoints>(account).checkpoints;
        let pos = vector::length(checkpoints);
        if (pos == 0) 0 else vector::borrow(checkpoints, pos - 1).votes
    }

    /// @dev Retrieve the number of votes for `account` at the end of `blockNumber`.
    /// Requirements:
    /// - `timestamp` must have already happened
    public fun get_past_votes(account: address, timestamp: u64): u64 acquires Checkpoints {
        assert!(timestamp < timestamp::now_seconds(), 1000);
        checkpoints_lookup(account, timestamp)
    }

    /// @dev Lookup a value in a list of (sorted) checkpoints.
    fun checkpoints_lookup(account: address, timestamp: u64): u64 acquires Checkpoints {
        let ckpts = &borrow_global<Checkpoints>(account).checkpoints;

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
            let mid = Math::average(low, high);
            if (vector::borrow(ckpts, mid).from_timestamp > timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        };

        if (high == 0) 0 else vector::borrow(ckpts, high - 1).votes
    }

    /// @dev Change delegation for `delegator` to `delegatee`.
    public fun delegate<CoinType>(delegator: &signer, delegatee: address) acquires CoinStore, Checkpoints, Delegate {
        // Get delegator address and locked balance
        let delegator_address = signer::address_of(delegator);
        let delegator_balance = coin::value(&borrow_global<CoinStore<CoinType>>(delegator_address).coin);

        if (exists<Delegate>(delegator_address)) {
            // Update delegatee (removing old delegatee's votes)
            let delegate_ref = &mut borrow_global_mut<Delegate>(delegator_address).delegatee;
            write_checkpoint(*delegate_ref, true, delegator_balance);
            *delegate_ref = delegatee;
        } else {
            // Add delegatee
            move_to(delegator, Delegate { delegatee });
        };

        // Add votes to new delegatee
        write_checkpoint(delegatee, false, delegator_balance);
    }

    /// @dev Internal function to add a votes checkpoint.
    fun write_checkpoint(account: address, subtract_not_add: bool, delta: u64): (u64, u64) acquires Checkpoints {
        let ckpts = &mut borrow_global_mut<Checkpoints>(account).checkpoints;

        let pos = vector::length(ckpts);
        let last_ckpt = vector::borrow_mut(ckpts, pos - 1);
        let old_weight = if (pos == 0) 0 else last_ckpt.votes;
        let new_weight = if (subtract_not_add) old_weight - delta else old_weight + delta;
        let now = timestamp::now_seconds();

        if (pos > 0 && last_ckpt.from_timestamp == now) {
            *&mut last_ckpt.votes = new_weight;
        } else {
            vector::push_back(ckpts, Checkpoint {
                from_timestamp: now,
                votes: new_weight
            });
        };

        (old_weight, new_weight)
    }
}
