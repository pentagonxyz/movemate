// SPDX-License-Identifier: MIT

/// @title Governance
/// @notice On-chain governance. In your existing contracts, give on-chain access control to your contracts by requiring the use of a `GovernanceCapability<CoinType>` with `verify_governance_capability<CoinType>(governance_capability: &GovernanceCapability<CoinType>, forum_address: address)`
/// Then, when it's time to upgrade, create a governance proposal from your new module that calls `create_proposal<CoinType, ProposalCapabilityType>()`.
/// Tokenholders call `cast_vote<CoinType, ProposalCapabilityType>()` to cast votes.
/// When the proposal passes, call `execute_proposal<CoinType, ProposalCapabilityType>()` to retrieve a copy of the `GovernanceCapability<CoinType>`.
module Movemate::Governance {
    use std::ascii::String;
    use std::signer;
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, Info};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use Movemate::Math;

    struct Forum<phantom CoinType> has key {
        info: Info,
        voting_delay: u64,
        voting_period: u64,
        queue_period: u64,
        execution_window: u64,
        proposal_threshold: u64,
        approval_threshold: u64,
        cancellation_threshold: u64
    }

    struct Proposal<phantom ProposalCapability> has key {
        info: Info,
        forum_id: ID,
        name: String,
        metadata: vector<u8>,
        votes: VecMap<address, bool>,
        approval_votes: u64,
        cancellation_votes: u64,
        timestamp: u64,
        executed: bool
    }

    struct GovernanceCapability has drop {
        forum_id: ID
    }

    struct CoinStore<phantom CoinType> has key {
        info: Info,
        delegatee: address,
        coin: Coin<CoinType>
    }

    struct Delegate<phantom CoinType> has key {
        info: Info,
        delegatee: address,
        checkpoints: vector<Checkpoint>
    }

    struct Checkpoint has store {
        votes: u64,
        from_timestamp: u64
    }

    /// @notice Checks if a governance capability matches the forum address. For use in an existing contract.
    public fun verify_governance_capability(governance_capability: &GovernanceCapability, forum_id: ID): bool {
        governance_capability.forum_id == forum_id
    }

    /// @notice Initiate a new forum under the signer provided.
    public entry fun init_forum<CoinType>(
        voting_delay: u64,
        voting_period: u64,
        queue_period: u64,
        execution_window: u64,
        proposal_threshold: u64,
        approval_threshold: u64,
        cancellation_threshold: u64,
        ctx: &mut TxContext
    ) {
        transfer::share_object(Forum<CoinType> {
            info: object::new(ctx),
            voting_delay,
            voting_period,
            queue_period,
            execution_window,
            proposal_threshold,
            approval_threshold,
            cancellation_threshold
        });
    }

    /// @notice Creates a new Delegate object.
    public entry fun new_voter<CoinType>(delegatee: address, ctx: &mut TxContext) {
        transfer::share_object(Delegate<CoinType> {
            info: object::new(ctx),
            delegatee,
            checkpoints: vector::empty()
        });
    }

    /// @notice Lock your coins for voting in the specified forum.
    public entry fun lock_coins<CoinType>(coins: &mut Coin<CoinType>, owner: address, amount: u64, delegatee: &mut Delegate<CoinType>, ctx: &mut TxContext) {
        // Move coin in
        let coin_in = coin::take<CoinType>(coin::balance_mut(coins), amount, ctx);

        // Create new store
        let coin_store = CoinStore {
            info: object::new(ctx),
            coin: coin_in,
            delegatee: delegatee.delegatee
        };

        // Update checkpoints
        write_checkpoint<CoinType>(delegatee, false, amount, ctx);

        // Transfer store to owner
        transfer::transfer(coin_store, owner);
    }

    /// @notice Lock your coins for voting in the specified forum.
    public entry fun lock_more_coins<CoinType>(coin_store: &mut CoinStore<CoinType>, coins: &mut Coin<CoinType>, amount: u64, delegatee: &mut Delegate<CoinType>, ctx: &mut TxContext) {
        // Input validation
        assert!(delegatee.delegatee == coin_store.delegatee, 1000);

        // Move coin in
        let coin_in = coin::take<CoinType>(coin::balance_mut(coins), amount, ctx);

        // Add to store
        coin::join(&mut coin_store.coin, coin_in);

        // Update checkpoints
        write_checkpoint<CoinType>(delegatee, false, amount, ctx);
    }

    /// @dev Unlock coins locked for voting.
    public entry fun unlock_coins<CoinType>(coin_store: &mut CoinStore<CoinType>, recipient: address, amount: u64, delegatee: &mut Delegate<CoinType>, ctx: &mut TxContext) {
        // Input validation
        assert!(delegatee.delegatee == coin_store.delegatee, 1000);

        // Update checkpoints
        write_checkpoint<CoinType>(delegatee, true, amount, ctx);

        // Move coin out
        coin::split_and_transfer(&mut coin_store.coin, amount, recipient, ctx);
    }

    /// @notice Create a new proposal, requiring the use of ProposalCapabilityType to execute it.
    public entry fun create_proposal<CoinType, ProposalCapabilityType>(
        forum: &Forum<CoinType>,
        proposer: &signer,
        name: String,
        metadata: vector<u8>,
        voter: &Delegate<CoinType>,
        ctx: &mut TxContext
    ) {
        // Validate !exists and proposer votes >= proposer threshold
        let proposer_address = signer::address_of(proposer);
        assert!(proposer_address == voter.delegatee, 1000);
        let proposer_votes = get_votes(voter);
        assert!(proposer_votes >= forum.proposal_threshold, 1000);

        // Add proposal to forum
        transfer::share_object(Proposal<ProposalCapabilityType> {
            info: object::new(ctx),
            forum_id: *object::info_id(&forum.info),
            name,
            metadata,
            votes: vec_map::empty(),
            approval_votes: 0,
            cancellation_votes: 0,
            timestamp: tx_context::epoch(ctx),
            executed: false
        });
    }

    public entry fun cast_vote<CoinType, ProposalCapabilityType>(
        forum: &Forum<CoinType>,
        proposal: &mut Proposal<ProposalCapabilityType>,
        account: &signer,
        vote: bool,
        voter: &Delegate<CoinType>,
        ctx: &mut TxContext
    ) {
        // Check timestamps
        assert!(*object::info_id(&forum.info) == proposal.forum_id, 1000);
        let voting_start = proposal.timestamp + forum.voting_delay;
        let now = tx_context::epoch(ctx);
        assert!(now >= voting_start, 1000);
        assert!(now < voting_start + forum.voting_period, 1000);

        // Get past votes
        let sender = signer::address_of(account);
        assert!(sender == voter.delegatee, 1000);
        let votes = get_past_votes(voter, voting_start, ctx);

        // Remove old vote if necessary
        if (vec_map::contains(&proposal.votes, &sender)) {
            let (_, old_vote) = vec_map::remove(&mut proposal.votes, &sender);
            assert!(vote != old_vote, 1000); // VOTE_NOT_CHANGED
            if (old_vote) *&mut proposal.approval_votes = *&proposal.approval_votes - votes
            else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes - votes;
        };

        // Cast new vote
        vec_map::insert(&mut proposal.votes, sender, vote);
        if (vote) *&mut proposal.approval_votes = *&proposal.approval_votes + votes
        else *&mut proposal.cancellation_votes = *&proposal.cancellation_votes + votes;
    }

    /// @notice Executes a proposal by returning the new contract a GovernanceCapability.
    public fun execute_proposal<CoinType, ProposalCapabilityType: drop>(
        forum: &Forum<CoinType>,
        proposal: &mut Proposal<ProposalCapabilityType>,
        _proposal_capability: ProposalCapabilityType,
        ctx: &mut TxContext
    ): GovernanceCapability {
        // Check timestamps
        assert!(*object::info_id(&forum.info) == proposal.forum_id, 1000);
        let post_queue = proposal.timestamp + forum.voting_delay + forum.voting_period + forum.queue_period;
        let now = tx_context::epoch(ctx);
        assert!(now >= post_queue, 1000);
        let expiration = post_queue + forum.execution_window;
        assert!(now < expiration, 1000);
        assert!(!proposal.executed, 1000);

        // Check votes
        assert!(proposal.approval_votes >= forum.approval_threshold, 1000);
        assert!(proposal.cancellation_votes < forum.cancellation_threshold, 1000);

        // Set proposal as executed
        *&mut proposal.executed = true;

        // Return GovernanceCapability with forum ID
        GovernanceCapability { forum_id: *object::info_id(&forum.info) }
    }

    /// @dev Get the address `account` is currently delegating to.
    public fun delegates<CoinType>(coin_store: &CoinStore<CoinType>): address {
        coin_store.delegatee
    }

    /// @dev Gets the current votes balance for `account`
    public fun get_votes<CoinType>(voter: &Delegate<CoinType>): u64 {
        let checkpoints = &voter.checkpoints;
        let pos = vector::length(checkpoints);
        if (pos == 0) 0 else vector::borrow(checkpoints, pos - 1).votes
    }

    /// @dev Retrieve the number of votes for `account` at the end of `blockNumber`.
    /// Requirements:
    /// - `timestamp` must have already happened
    public fun get_past_votes<CoinType>(voter: &Delegate<CoinType>, timestamp: u64, ctx: &mut TxContext): u64 {
        assert!(timestamp < tx_context::epoch(ctx), 1000);
        checkpoints_lookup(voter, timestamp)
    }

    /// @dev Lookup a value in a list of (sorted) checkpoints.
    fun checkpoints_lookup<CoinType>(voter: &Delegate<CoinType>, timestamp: u64): u64 {
        let ckpts = &voter.checkpoints;

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
    /// TODO: Optional delegation?
    public entry fun delegate<CoinType>(coin_store: &mut CoinStore<CoinType>, delegatee: &mut Delegate<CoinType>, ctx: &mut TxContext) {
        // Get delegator locked balance
        let delegator_balance = coin::value(&coin_store.coin);
        
        // Update delegatee (removing old delegatee's votes)
        write_checkpoint<CoinType>(delegatee, true, delegator_balance, ctx);
        *&mut coin_store.delegatee = delegatee.delegatee;

        // Add votes to new delegatee
        write_checkpoint<CoinType>(delegatee, false, delegator_balance, ctx);
    }

    /// @dev Internal function to add a votes checkpoint.
    fun write_checkpoint<CoinType>(voter: &mut Delegate<CoinType>, subtract_not_add: bool, delta: u64, ctx: &mut TxContext): (u64, u64) {
        let ckpts = &mut voter.checkpoints;

        let pos = vector::length(ckpts);
        let last_ckpt = vector::borrow_mut(ckpts, pos - 1);
        let old_weight = if (pos == 0) 0 else last_ckpt.votes;
        let new_weight = if (subtract_not_add) old_weight - delta else old_weight + delta;
        let now = tx_context::epoch(ctx);

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
