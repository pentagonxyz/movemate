/// @title vectors
/// @notice Vector utilities.
/// @dev TODO: Fuzz testing?
module movemate::vectors {
    use std::error;
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
            // because math::average rounds down (it does integer division with truncation).
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
        assert!(len == vector::length(b), error::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        while (i < len) {
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
        assert!(len == vector::length(b), error::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        while (i < len) {
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
        assert!(len == vector::length(b), error::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        while (i < len) {
            let aa = *vector::borrow(a, i);
            let bb = *vector::borrow(b, i);
            if (aa < bb) return true;
            if (aa > bb) return false;
            i = i + 1;
        };

        true
    }

    public fun gte(a: &vector<u8>, b: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(a);
        assert!(len == vector::length(b), error::invalid_argument(EVECTOR_LENGTH_MISMATCH));

        while (i < len) {
            let aa = *vector::borrow(a, i);
            let bb = *vector::borrow(b, i);
            if (aa > bb) return true;
            if (aa < bb) return false;
            i = i + 1;
        };

        true
    }

    #[test]
    fun test_find_upper_bound() {
        let vec = vector::empty<u64>();
        vector::push_back(&mut vec, 33);
        vector::push_back(&mut vec, 66);
        vector::push_back(&mut vec, 99);
        vector::push_back(&mut vec, 100);
        vector::push_back(&mut vec, 123);
        vector::push_back(&mut vec, 222);
        vector::push_back(&mut vec, 233);
        vector::push_back(&mut vec, 244);
        assert!(find_upper_bound(&vec, 223) == 6, 0);
    }

    #[test]
    fun test_lt() {
        assert!(lt(&x"19853428", &x"19853429"), 0);
        assert!(lt(&x"32432023", &x"32432323"), 1);
        assert!(!lt(&x"83975792", &x"83975492"), 2);
        assert!(!lt(&x"83975492", &x"83975492"), 3);
    }

    #[test]
    fun test_gt() {
        assert!(gt(&x"17432844", &x"17432843"), 0);
        assert!(gt(&x"79847429", &x"79847329"), 1);
        assert!(!gt(&x"19849334", &x"19849354"), 2);
        assert!(!gt(&x"19849354", &x"19849354"), 3);
    }

    #[test]
    fun test_not_gt() {
        assert!(lte(&x"23789179", &x"23789279"), 0);
        assert!(lte(&x"23789279", &x"23789279"), 1);
        assert!(!lte(&x"13258445", &x"13258444"), 2);
        assert!(!lte(&x"13258454", &x"13258444"), 3);
    }

    #[test]
    fun test_lte() {
        assert!(lte(&x"23789179", &x"23789279"), 0);
        assert!(lte(&x"23789279", &x"23789279"), 1);
        assert!(!lte(&x"13258445", &x"13258444"), 2);
        assert!(!lte(&x"13258454", &x"13258444"), 3);
    }

    #[test]
    fun test_gte() {
        assert!(gte(&x"14329932", &x"14329832"), 0);
        assert!(gte(&x"14329832", &x"14329832"), 1);
        assert!(!gte(&x"12654586", &x"12654587"), 2);
        assert!(!gte(&x"12654577", &x"12654587"), 3);
    }
}
