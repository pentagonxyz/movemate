module Movemate::Vectors {
    use Std::Vector;

    use Movemate::Math;

    /// @dev Searches a sorted `vec` and returns the first index that contains
    /// a value greater or equal to `element`. If no such index exists (i.e. all
    /// values in the vector are strictly less than `element`), the vector length is
    /// returned. Time complexity O(log n).
    /// `vec` is expected to be sorted in ascending order, and to contain no
    /// repeated elements.
    public fun find_upper_bound(vec: &vector<u64>, element: u64): u64 {
        if (Vector::length(vec) == 0) {
            return 0;
        };

        let low = 0;
        let high = Vector::length(vec);

        while (low < high) {
            let mid = Math::average(low, high);

            // Note that mid will always be strictly less than high (i.e. it will be a valid vector index)
            // because Math::average rounds down (it does integer division with truncation).
            if (*Vector::borrow(vec, mid) > element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        };

        // At this point `low` is the exclusive upper bound. We will return the inclusive upper bound.
        if (low > 0 && *Vector::borrow(vec, low - 1) == element) {
            low - 1
        } else {
            low
        }
    }
}
