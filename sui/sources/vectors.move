/// @title vectors
/// @notice Vector utilities.
module movemate::vectors {
    use std::errors;
    use std::vector;

    use movemate::math;

    /// @dev When you supply vectors of different lengths to a function requiring equal-length vectors.
    /// TODO: Support variable length vectors?
    const EVECTOR_LENGTH_MISMATCH: u64 = 0;

    /// @dev Searches a sorted `vec` and returns the first index that contains
    /// a value greater or equal to `element`. If no such index exists (i.e. all
    /// values in the vector are strictly less than `element`), the vector length is
    /// returned. Time complexity O(log n).
    /// `vec` is expected to be sorted in ascending order, and to contain no
    /// repeated elements.
    public fun find_upper_bound(vec: &vector<u64>, element: u64): u64 {
        if (vector::length(vec) == 0) {
            return 0
        };

        let low = 0;
        let high = vector::length(vec);

        while (low < high) {
            let mid = math::average(low, high);

            // Note that mid will always be strictly less than high (i.e. it will be a valid vector index)
            // because Math::average rounds down (it does integer division with truncation).
            if (*vector::borrow(vec, mid) > element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        };

        // At this point `low` is the exclusive upper bound. We will return the inclusive upper bound.
        if (low > 0 && *vector::borrow(vec, low - 1) == element) {
            low - 1
        } else {
            low
        }
    }

    public fun lt(a: &vector<u8>, b: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(a);
        assert!(len == vector::length(b), errors::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        loop {
            if (i >= len) break;
            let aa = *vector::borrow(a, i);
            let bb = *vector::borrow(b, i);
            if (aa < bb) return true;
            if (aa > bb) return false;
            i = i + 1;
        };

        false
    }

    public fun gt(a: &vector<u8>, b: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(a);
        assert!(len == vector::length(b), errors::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        loop {
            if (i >= len) break;
            let aa = *vector::borrow(a, i);
            let bb = *vector::borrow(b, i);
            if (aa > bb) return true;
            if (aa < bb) return false;
            i = i + 1;
        };

        false
    }

    public fun lte(a: &vector<u8>, b: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(a);
        assert!(len == vector::length(b), errors::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        loop {
            if (i >= len) break;
            let aa = *vector::borrow(a, i);
            let bb = *vector::borrow(b, i);
            if (aa <= bb) return true;
            if (aa > bb) return false;
            i = i + 1;
        };

        true
    }

    public fun gte(a: &vector<u8>, b: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(a);
        assert!(len == vector::length(b), errors::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        loop {
            if (i >= len) break;
            let aa = *vector::borrow(a, i);
            let bb = *vector::borrow(b, i);
            if (aa >= bb) return true;
            if (aa < bb) return false;
            i = i + 1;
        };

        true
    }
}
