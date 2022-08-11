// SPDX-License-Identifier: Apache-2.0
// Based on: https://github.com/starcoinorg/starcoin-framework-commons/blob/main/sources/PseudoRandom.move

/// @title pseudorandom
/// @notice A pseudo random module on-chain.
/// @dev Warning: 
/// The random mechanism in smart contracts is different from 
/// that in traditional programming languages. The value generated 
/// by random is predictable to Miners, so it can only be used in 
/// simple scenarios where Miners have no incentive to cheat. If 
/// large amounts of money are involved, DO NOT USE THIS MODULE to 
/// generate random numbers; try a more secure way.
module movemate::pseudorandom {
    use std::bcs;
    use std::errors;
    use std::guid;
    use std::hash;
    use std::signer;
    use std::vector;

    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use movemate::bcd;

    const ENOT_ROOT: u64 = 0;
    const EHIGH_ARG_GREATER_THAN_LOW_ARG: u64 = 1;

    /// Resource that wraps an integer counter.
    struct Counter has key {
        value: u64
    }

    /// Publish a `Counter` resource with value `i` under the given `root` account.
    public fun init(root: &signer) {
        // "Pack" (create) a Counter resource. This is a privileged operation that
        // can only be done inside the module that declares the `Counter` resource
        assert!(signer::address_of(root) == @movemate, errors::requires_address(ENOT_ROOT));
        transfer::share_object(Counter { value: 0 });
    }

    /// Increment the value of the supplied `Counter` resource.
    fun increment(counter: &mut Counter): u64 {
        let c_ref = &mut counter.value;
        *c_ref = *c_ref + 1;
        *c_ref
    }

    /// Acquire a seed using: the hash of the counter, epoch, sender address, new GUID, and new object ID.
    fun seed(account: &signer, counter: &mut Counter, ctx: &mut TxContext): vector<u8> {
        let counter_val = increment(counter);
        let counter_bytes = bcs::to_bytes(&counter_val);

        let epoch: u64 = tx_context::epoch(ctx);
        let epoch_bytes: vector<u8> = bcs::to_bytes(&epoch);

        let sender_bytes: vector<u8> = bcs::to_bytes(&signer::address_of(account));

        let guid_id = guid::id(&guid::create(account));
        let guid_id_bytes = bcs::to_bytes(&guid_id);

        let uid = object::new(ctx);
        let object_id_bytes: vector<u8> = object::id_to_bytes(object::uid_as_inner(&uid));
        object::delete(uid);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, counter_bytes);
        vector::append<u8>(&mut info, sender_bytes);
        vector::append<u8>(&mut info, guid_id_bytes);
        vector::append<u8>(&mut info, epoch_bytes);
        vector::append<u8>(&mut info, object_id_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Acquire a seed using: the hash of the epoch, sender address, new GUID, and new object ID.
    fun seed_no_counter(account: &signer, ctx: &mut TxContext): vector<u8> {
        let epoch: u64 = tx_context::epoch(ctx);
        let epoch_bytes: vector<u8> = bcs::to_bytes(&epoch);

        let sender_bytes: vector<u8> = bcs::to_bytes(&signer::address_of(account));

        let guid_id = guid::id(&guid::create(account));
        let guid_id_bytes = bcs::to_bytes(&guid_id);

        let uid = object::new(ctx);
        let object_id_bytes: vector<u8> = object::id_to_bytes(object::uid_as_inner(&uid));
        object::delete(uid);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, sender_bytes);
        vector::append<u8>(&mut info, guid_id_bytes);
        vector::append<u8>(&mut info, epoch_bytes);
        vector::append<u8>(&mut info, object_id_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Acquire a seed using: the hash of the counter, epoch, sender address, and new object ID.
    fun seed_no_signer(counter: &mut Counter, ctx: &mut TxContext): vector<u8> {
        let counter_val = increment(counter);
        let counter_bytes = bcs::to_bytes(&counter_val);

        let epoch: u64 = tx_context::epoch(ctx);
        let epoch_bytes: vector<u8> = bcs::to_bytes(&epoch);

        let sender_bytes: vector<u8> = bcs::to_bytes(&tx_context::sender(ctx));

        let uid = object::new(ctx);
        let object_id_bytes: vector<u8> = object::id_to_bytes(object::uid_as_inner(&uid));
        object::delete(uid);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, counter_bytes);
        vector::append<u8>(&mut info, sender_bytes);
        vector::append<u8>(&mut info, epoch_bytes);
        vector::append<u8>(&mut info, object_id_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Acquire a seed using: the hash of the counter, sender address, and new GUID.
    fun seed_no_ctx(account: &signer, counter: &mut Counter): vector<u8> {
        let counter_val = increment(counter);
        let counter_bytes = bcs::to_bytes(&counter_val);

        let sender_bytes: vector<u8> = bcs::to_bytes(&signer::address_of(account));

        let guid_id = guid::id(&guid::create(account));
        let guid_id_bytes = bcs::to_bytes(&guid_id);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, counter_bytes);
        vector::append<u8>(&mut info, sender_bytes);
        vector::append<u8>(&mut info, guid_id_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Acquire a seed using: the hash of the counter.
    fun seed_with_counter_and_address(counter: &mut Counter, sender: &address): vector<u8> {
        let counter_val = increment(counter);
        let counter_bytes = bcs::to_bytes(&counter_val);

        let sender_bytes = bcs::to_bytes(sender);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, counter_bytes);
        vector::append<u8>(&mut info, sender_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Acquire a seed using: the hash of the counter.
    fun seed_with_counter(counter: &mut Counter): vector<u8> {
        let counter_val = increment(counter);
        let counter_bytes = bcs::to_bytes(&counter_val);

        let hash: vector<u8> = hash::sha3_256(counter_bytes);
        hash
    }

    /// Acquire a seed using: the sender address and a new GUID.
    fun seed_with_signer(account: &signer): vector<u8> {
        let sender_bytes: vector<u8> = bcs::to_bytes(&signer::address_of(account));

        let guid_id = guid::id(&guid::create(account));
        let guid_id_bytes = bcs::to_bytes(&guid_id);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, sender_bytes);
        vector::append<u8>(&mut info, guid_id_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Acquire a seed using: the hash of the epoch, sender address, and a new object ID.
    fun seed_with_ctx(ctx: &mut TxContext): vector<u8> {
        let epoch: u64 = tx_context::epoch(ctx);
        let epoch_bytes: vector<u8> = bcs::to_bytes(&epoch);

        let sender_bytes: vector<u8> = bcs::to_bytes(&tx_context::sender(ctx));

        let uid = object::new(ctx);
        let object_id_bytes: vector<u8> = object::id_to_bytes(object::uid_as_inner(&uid));
        object::delete(uid);

        let info: vector<u8> = vector::empty<u8>();
        vector::append<u8>(&mut info, sender_bytes);
        vector::append<u8>(&mut info, epoch_bytes);
        vector::append<u8>(&mut info, object_id_bytes);

        let hash: vector<u8> = hash::sha3_256(info);
        hash
    }

    /// Generate a random u128
    public fun rand_u128_with_seed(_seed: vector<u8>): u128 {
        bcd::bytes_to_u128(_seed)
    }

    /// Generate a random integer range in [low, high).
    public fun rand_u128_range_with_seed(_seed: vector<u8>, low: u128, high: u128): u128 {
        assert!(high > low, errors::invalid_argument(EHIGH_ARG_GREATER_THAN_LOW_ARG));
        let value = rand_u128_with_seed(_seed);
        (value % (high - low)) + low
    }

    /// Generate a random u64
    public fun rand_u64_with_seed(_seed: vector<u8>): u64 {
        bcd::bytes_to_u64(_seed)
    }

    /// Generate a random integer range in [low, high).
    public fun rand_u64_range_with_seed(_seed: vector<u8>, low: u64, high: u64): u64 {
        assert!(high > low, errors::invalid_argument(EHIGH_ARG_GREATER_THAN_LOW_ARG));
        let value = rand_u64_with_seed(_seed);
        (value % (high - low)) + low
    }

    public fun rand_u128(account: &signer, counter: &mut Counter, ctx: &mut TxContext): u128 { rand_u128_with_seed(seed(account, counter, ctx)) }
    public fun rand_u128_range(account: &signer, counter: &mut Counter, low: u128, high: u128, ctx: &mut TxContext): u128 { rand_u128_range_with_seed(seed(account, counter, ctx), low, high) }
    public fun rand_u64(account: &signer, counter: &mut Counter, ctx: &mut TxContext): u64 { rand_u64_with_seed(seed(account, counter, ctx)) }
    public fun rand_u64_range(account: &signer, counter: &mut Counter, low: u64, high: u64, ctx: &mut TxContext): u64 { rand_u64_range_with_seed(seed(account, counter, ctx), low, high) }

    public fun rand_u128_no_counter(account: &signer, ctx: &mut TxContext): u128 { rand_u128_with_seed(seed_no_counter(account, ctx)) }
    public fun rand_u128_range_no_counter(account: &signer, low: u128, high: u128, ctx: &mut TxContext): u128 { rand_u128_range_with_seed(seed_no_counter(account, ctx), low, high) }
    public fun rand_u64_no_counter(account: &signer, ctx: &mut TxContext): u64 { rand_u64_with_seed(seed_no_counter(account, ctx)) }
    public fun rand_u64_range_no_counter(account: &signer, low: u64, high: u64, ctx: &mut TxContext): u64 { rand_u64_range_with_seed(seed_no_counter(account, ctx), low, high) }

    public fun rand_u128_no_signer(counter: &mut Counter, ctx: &mut TxContext): u128 { rand_u128_with_seed(seed_no_signer(counter, ctx)) }
    public fun rand_u128_range_no_signer(counter: &mut Counter, low: u128, high: u128, ctx: &mut TxContext): u128 { rand_u128_range_with_seed(seed_no_signer(counter, ctx), low, high) }
    public fun rand_u64_no_signer(counter: &mut Counter, ctx: &mut TxContext): u64 { rand_u64_with_seed(seed_no_signer(counter, ctx)) }
    public fun rand_u64_range_no_signer(counter: &mut Counter, low: u64, high: u64, ctx: &mut TxContext): u64 { rand_u64_range_with_seed(seed_no_signer(counter, ctx), low, high) }

    public fun rand_u128_no_ctx(account: &signer, counter: &mut Counter): u128 { rand_u128_with_seed(seed_no_ctx(account, counter)) }
    public fun rand_u128_range_no_ctx(account: &signer, counter: &mut Counter, low: u128, high: u128): u128 { rand_u128_range_with_seed(seed_no_ctx(account, counter), low, high) }
    public fun rand_u64_no_ctx(account: &signer, counter: &mut Counter): u64 { rand_u64_with_seed(seed_no_ctx(account, counter)) }
    public fun rand_u64_range_no_ctx(account: &signer, counter: &mut Counter, low: u64, high: u64): u64 { rand_u64_range_with_seed(seed_no_ctx(account, counter), low, high) }

    public fun rand_u128_with_counter_and_address(counter: &mut Counter, sender: &address): u128 { rand_u128_with_seed(seed_with_counter_and_address(counter, sender)) }
    public fun rand_u128_range_with_counter_and_address(counter: &mut Counter, sender: &address, low: u128, high: u128): u128 { rand_u128_range_with_seed(seed_with_counter_and_address(counter, sender), low, high) }
    public fun rand_u64_with_counter_and_address(counter: &mut Counter, sender: &address): u64 { rand_u64_with_seed(seed_with_counter_and_address(counter, sender)) }
    public fun rand_u64_range_with_counter_and_address(counter: &mut Counter, sender: &address, low: u64, high: u64): u64 { rand_u64_range_with_seed(seed_with_counter_and_address(counter, sender), low, high) }

    public fun rand_u128_with_counter(counter: &mut Counter): u128 { rand_u128_with_seed(seed_with_counter(counter)) }
    public fun rand_u128_range_with_counter(counter: &mut Counter, low: u128, high: u128): u128 { rand_u128_range_with_seed(seed_with_counter(counter), low, high) }
    public fun rand_u64_with_counter(counter: &mut Counter): u64 { rand_u64_with_seed(seed_with_counter(counter)) }
    public fun rand_u64_range_with_counter(counter: &mut Counter, low: u64, high: u64): u64 { rand_u64_range_with_seed(seed_with_counter(counter), low, high) }

    public fun rand_u128_with_signer(account: &signer): u128 { rand_u128_with_seed(seed_with_signer(account)) }
    public fun rand_u128_range_with_signer(account: &signer, low: u128, high: u128): u128 { rand_u128_range_with_seed(seed_with_signer(account), low, high) }
    public fun rand_u64_with_signer(account: &signer): u64 { rand_u64_with_seed(seed_with_signer(account)) }
    public fun rand_u64_range_with_signer(account: &signer, low: u64, high: u64): u64 { rand_u64_range_with_seed(seed_with_signer(account), low, high) }

    public fun rand_u128_with_ctx(ctx: &mut TxContext): u128 { rand_u128_with_seed(seed_with_ctx(ctx)) }
    public fun rand_u128_range_with_ctx(low: u128, high: u128, ctx: &mut TxContext): u128 { rand_u128_range_with_seed(seed_with_ctx(ctx), low, high) }
    public fun rand_u64_with_ctx(ctx: &mut TxContext): u64 { rand_u64_with_seed(seed_with_ctx(ctx)) }
    public fun rand_u64_range_with_ctx(low: u64, high: u64 ,ctx: &mut TxContext): u64 { rand_u64_range_with_seed(seed_with_ctx(ctx), low, high) }
}
