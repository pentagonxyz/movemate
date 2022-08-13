// SPDX-License-Identifier: Apache-2.0
// Based on: https://github.com/wanseob/solidity-bloom-filter/blob/master/contracts/BloomFilter.sol

/// @title bloom_filter
/// @dev Probabilistic data structure for checking if an element is part of a set.
module movemate::bloom_filter {
    use std::error;
    use std::hash;
    use std::vector;

    use movemate::u256::{Self, U256};

    const EHASH_COUNT_IS_ZERO: u64 = 0;
    const EVECTOR_LENGTH_NOT_32: u64 = 1;

    struct Filter has copy, drop, store {
        bitmap: U256,
        hash_count: u8
    }
   
    /// @dev It returns how many times it should be hashed, when the expected number of input items is `_item_num`.
    /// @param _item_num Expected number of input items
    public fun get_hash_count(_item_num: u64): u8 {
        let num_of_hash = (256 * 144) / (_item_num * 100) + 1;
        if (num_of_hash < 256) (num_of_hash as u8) else 255
    }

    /// @dev It returns updated bitmap when a new item is added into the bitmap
    /// @param _bitmap Original bitmap
    /// @param _hash_count How many times to hash. You should use the same value with the one which is used for the original bitmap.
    /// @param _item Hash value of an item
    public fun add_to_bitmap(_bitmap: U256, _hash_count: u8, _item: vector<u8>): U256 {
        assert!(_hash_count > 0, error::invalid_argument(EHASH_COUNT_IS_ZERO));
        assert!(vector::length(&_item) == 32, error::invalid_argument(EVECTOR_LENGTH_NOT_32));
        let i: u8 = 0;
        vector::push_back(&mut _item, 0);
        while (i < _hash_count) {
            *vector::borrow_mut(&mut _item, 32) = i;
            let position = vector::pop_back(&mut hash::sha2_256(_item));
            let digest = u256::shl(u256::from_u128(1), position);
            _bitmap = u256::or(&_bitmap, &digest);
            i = i + 1;
        };
        _bitmap
    }

    /// @dev It returns it may exist or definitely not exist.
    /// @param _bitmap Original bitmap
    /// @param _hash_count How many times to hash. You should use the same value with the one which is used for the original bitmap.
    /// @param _item Hash value of an item
    public fun false_positive(_bitmap: U256, _hash_count: u8, _item: vector<u8>): bool {
        assert!(_hash_count > 0, error::invalid_argument(EHASH_COUNT_IS_ZERO));
        assert!(vector::length(&_item) == 32, error::invalid_argument(EVECTOR_LENGTH_NOT_32));
        let i: u8 = 0;
        vector::push_back(&mut _item, 0);
        while (i < _hash_count) {
            *vector::borrow_mut(&mut _item, 32) = i;
            let position = vector::pop_back(&mut hash::sha2_256(_item));
            let digest = u256::shl(u256::from_u128(1), position);
            if (_bitmap != u256::or(&_bitmap, &digest)) return false;
            i = i + 1;
        };
        true
    }

    /// @dev It initialize the Filter struct. It sets the appropriate hash count for the expected number of item
    /// @param _itemNum Expected number of items to be added
    public fun new(_item_num: u64): Filter {
        Filter {
            bitmap: u256::zero(),
            hash_count: get_hash_count(_item_num)
        }
    }

    /// @dev It updates the bitmap of the filter using the given item value
    /// @param _item Hash value of an item
    public fun add(_filter: &mut Filter, _item: vector<u8>) {
        *&mut _filter.bitmap = add_to_bitmap(_filter.bitmap, _filter.hash_count, _item);
    }

    /// @dev It returns the filter may include the item or definitely now include it.
    /// @param _item Hash value of an item
    public fun check(_filter: &Filter, _item: vector<u8>): bool {
        false_positive(_filter.bitmap, _filter.hash_count, _item)
    }

    #[test]
    public fun test_end_to_end() {
        // Test init: check hash count
        let filter = new(10);
        assert!(filter.hash_count == 37, 0); // Hash count should equal 37
        
        // Test adding elements
        add(&mut filter, b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        let bitmap_a = filter.bitmap;
        add(&mut filter, b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        let bitmap_b = filter.bitmap;
        assert!(bitmap_b == bitmap_a, 1); // Adding same item should not update the bitmap
        add(&mut filter, b"cccccccccccccccccccccccccccccccc");
        let bitmap_c = filter.bitmap;
        assert!(bitmap_c != bitmap_b, 2); // Adding different item should update the bitmap

        // Test checking for inclusion
        let included = b"abcdefghij";
        let not_included = b"klmnopqrst";
        let i = 0;
        while (i < 10) {
            let key = hash::sha2_256(vector::singleton(*vector::borrow(&included, i)));
            add(&mut filter, key);
            i = i + 1;
        };
        let j = 0;
        while (j < 10) {
            let key = hash::sha2_256(vector::singleton(*vector::borrow(&included, j)));
            let false_positive = check(&filter, key);
            // It may exist or not
            assert!(false_positive, 3); // Should return false positive
            j = j + 1;
        };
        let k = 0;
        while (k < 10) {
            let key = hash::sha2_256(vector::singleton(*vector::borrow(&not_included, k)));
            let false_positive = check(&filter, key);
            // It definitely does not exist
            assert!(!false_positive, 4); // Should return definitely not exist
            k = k + 1;
        }
    }
}
