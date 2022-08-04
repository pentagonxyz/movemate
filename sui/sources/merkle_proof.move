// SPDX-License-Identifier: MIT
// Based on: OpenZeppelin Contracts (last updated v4.7.0) (utils/cryptography/MerkleProof.sol)

/// @title: merkle_proof
/// @dev These functions deal with verification of Merkle Tree proofs.
/// The proofs can be generated using the JavaScript library
/// https://github.com/miguelmota/merkletreejs[merkletreejs].
/// Note: the hashing algorithm should be keccak256 and pair sorting should be enabled.
/// See `test/utils/cryptography/MerkleProof.test.js` for some examples.
/// WARNING: You should avoid using leaf values that are 64 bytes long prior to
/// hashing, or use a hash function other than keccak256 for hashing leaves.
/// This is because the concatenation of a sorted pair of internal nodes in
/// the merkle tree could be reinterpreted as a leaf value.
module movemate::merkle_proof {
    use std::errors;
    use std::hash;
    use std::vector;

    use movemate::vectors;

    /// @dev When an invalid multi-proof is supplied. Proof flags length must equal proof length + leaves length - 1.
    const EINVALID_MULTI_PROOF: u64 = 0;

    /// @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
    /// defined by `root`. For this, a `proof` must be provided, containing
    /// sibling hashes on the branch from the leaf to the root of the tree. Each
    /// pair of leaves and each pair of pre-images are assumed to be sorted.
    public fun verify(
        proof: &vector<vector<u8>>,
        root: vector<u8>,
        leaf: vector<u8>
    ): bool {
        process_proof(proof, leaf) == root
    }

    /// @dev Returns the rebuilt hash obtained by traversing a Merkle tree up
    /// from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
    /// hash matches the root of the tree. When processing the proof, the pairs
    /// of leafs & pre-images are assumed to be sorted.
    fun process_proof(proof: &vector<vector<u8>>, leaf: vector<u8>): vector<u8> {
        let computed_hash = leaf;
        let proof_length = vector::length(proof);
        let i = 0;

        loop {
            if (i >= proof_length) break;
            computed_hash = hash_pair(computed_hash, *vector::borrow(proof, i));
            i = i + 1;
        };

        computed_hash
    }

    /// @dev Returns true if the `leaves` can be proved to be a part of a Merkle tree defined by
    /// `root`, according to `proof` and `proofFlags` as described in {processMultiProof}.
    public fun multi_proof_verify(
        proof: &vector<vector<u8>>,
        proof_flags: &vector<bool>,
        root: vector<u8>,
        leaves: &vector<vector<u8>>
    ): bool {
        process_multi_proof(proof, proof_flags, leaves) == root
    }

    /// @dev Returns the root of a tree reconstructed from `leaves` and the sibling nodes in `proof`,
    /// consuming from one or the other at each step according to the instructions given by
    /// `proofFlags`.
    fun process_multi_proof(
        proof: &vector<vector<u8>>,
        proof_flags: &vector<bool>,
        leaves: &vector<vector<u8>>,
    ): vector<u8> {
        // This function rebuild the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the merkle tree.
        let leaves_len = vector::length(leaves);
        let total_hashes = vector::length(proof_flags);

        // Check proof validity.
        assert!(leaves_len + vector::length(proof) - 1 == total_hashes, errors::invalid_argument(EINVALID_MULTI_PROOF));

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        let hashes = vector::empty<vector<u8>>();
        let leaf_pos = 0;
        let hash_pos = 0;
        let proof_pos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value for the "main queue" (merging branches) or an element from the
        //   `proof` array.
        let i = 0;

        loop {
            if (i >= total_hashes) break;

            let a = if (leaf_pos < leaves_len) {
                leaf_pos = leaf_pos + 1;
                *vector::borrow(leaves, leaf_pos)
            } else {
                hash_pos = hash_pos + 1;
                *vector::borrow(&hashes, hash_pos)
            };

            let b = if (*vector::borrow(proof_flags, i)) {
                if (leaf_pos < leaves_len) {
                    leaf_pos = leaf_pos + 1;
                    *vector::borrow(leaves, leaf_pos)
                } else {
                    hash_pos = hash_pos + 1;
                    *vector::borrow(&hashes, hash_pos)
                }
            } else {
                proof_pos = proof_pos + 1;
                *vector::borrow(proof, proof_pos)
            };

            vector::push_back(&mut hashes, hash_pair(a, b));
            i = i + 1;
        };

        if (total_hashes > 0) {
            *vector::borrow(&hashes, total_hashes - 1)
        } else if (leaves_len > 0) {
            *vector::borrow(leaves, 0)
        } else {
            *vector::borrow(proof, 0)
        }
    }

    fun hash_pair(a: vector<u8>, b: vector<u8>): vector<u8> {
        if (vectors::lt(&a, &b)) efficient_hash(a, b) else efficient_hash(b, a)
    }

    fun efficient_hash(a: vector<u8>, b: vector<u8>): vector<u8> {
        vector::append(&mut a, b);
        hash::sha2_256(a)
    }
}
