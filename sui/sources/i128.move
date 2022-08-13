/// @title i128
/// @notice Signed 128-bit integers in Move.
/// @dev TODO: Pass in params by value instead of by ref to make usage easier?
module movemate::i128 {
    use std::errors;

    /// @dev Maximum I128 value as a u128.
    const MAX_I128_AS_U128: u128 = (1 << 127) - 1;

    /// @dev u128 with the first bit set. An `I128` is negative if this bit is set.
    const U128_WITH_FIRST_BIT_SET: u128 = 1 << 127;

    /// When both `U256` equal.
    const EQUAL: u8 = 0;

    /// When `a` is less than `b`.
    const LESS_THAN: u8 = 1;

    /// When `b` is greater than `b`.
    const GREATER_THAN: u8 = 2;

    /// @dev When trying to convert from a u128 > MAX_I128_AS_U128 to an I128.
    const ECONVERSION_FROM_U128_OVERFLOW: u64 = 0;

    /// @dev When trying to convert from an negative I128 to a u128.
    const ECONVERSION_TO_U128_UNDERFLOW: u64 = 1;

    /// @notice Struct representing a signed 128-bit integer.
    struct I128 has copy, drop, store {
        bits: u128
    }

    /// @notice Casts a `u128` to an `I128`.
    public fun from(x: u128): I128 {
        assert!(x <= MAX_I128_AS_U128, errors::invalid_argument(ECONVERSION_FROM_U128_OVERFLOW));
        I128 { bits: x }
    }

    /// @notice Creates a new `I128` with value 0.
    public fun zero(): I128 {
        I128 { bits: 0 }
    }

    /// @notice Casts an `I128` to a `u128`.
    public fun as_u128(x: &I128): u128 {
        assert!(x.bits < U128_WITH_FIRST_BIT_SET, errors::invalid_argument(ECONVERSION_TO_U128_UNDERFLOW));
        x.bits
    }

    /// @notice Whether or not `x` is equal to 0.
    public fun is_zero(x: &I128): bool {
        x.bits == 0
    }

    /// @notice Whether or not `x` is negative.
    public fun is_neg(x: &I128): bool {
        x.bits > U128_WITH_FIRST_BIT_SET
    }

    /// @notice Flips the sign of `x`.
    public fun neg(x: &I128): I128 {
        if (x.bits == 0) return *x;
        I128 { bits: if (x.bits < U128_WITH_FIRST_BIT_SET) x.bits | (1 << 127) else x.bits - (1 << 127) }
    }

    /// @notice Flips the sign of `x`.
    public fun neg_from(x: u128): I128 {
        let ret = from(x);
        *&mut ret.bits = ret.bits | (1 << 127);
        ret
    }

    /// @notice Absolute value of `x`.
    public fun abs(x: &I128): I128 {
        if (x.bits < U128_WITH_FIRST_BIT_SET) *x else I128 { bits: x.bits - (1 << 127) }
    }

    /// @notice Compare `a` and `b`.
    public fun compare(a: &I128, b: &I128): u8 {
        if (a.bits == b.bits) return EQUAL;
        if (a.bits < U128_WITH_FIRST_BIT_SET) {
            // A is positive
            if (b.bits < U128_WITH_FIRST_BIT_SET) {
                // B is positive
                return if (a.bits > b.bits) GREATER_THAN else LESS_THAN
            } else {
                // B is negative
                return GREATER_THAN
            }
        } else {
            // A is negative
            if (b.bits < U128_WITH_FIRST_BIT_SET) {
                // B is positive
                return LESS_THAN
            } else {
                // B is negative
                return if (a.bits > b.bits) LESS_THAN else GREATER_THAN
            }
        }
    }

    /// @notice Add `a + b`.
    public fun add(a: &I128, b: &I128): I128 {
        if (a.bits >> 127 == 0) {
            // A is positive
            if (b.bits >> 127 == 0) {
                // B is positive
                return I128 { bits: a.bits + b.bits }
            } else {
                // B is negative
                if (b.bits - (1 << 127) <= a.bits) return I128 { bits: a.bits - (b.bits - (1 << 127)) }; // Return positive
                return I128 { bits: b.bits - a.bits } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 127 == 0) {
                // B is positive
                if (a.bits - (1 << 127) <= b.bits) return I128 { bits: b.bits - (a.bits - (1 << 127)) }; // Return positive
                return I128 { bits: a.bits - b.bits } // Return negative
            } else {
                // B is negative
                return I128 { bits: a.bits + (b.bits - (1 << 127)) }
            }
        }
    }

    /// @notice Subtract `a - b`.
    public fun sub(a: &I128, b: &I128): I128 {
        if (a.bits >> 127 == 0) {
            // A is positive
            if (b.bits >> 127 == 0) {
                // B is positive
                if (a.bits >= b.bits) return I128 { bits: a.bits - b.bits }; // Return positive
                return I128 { bits: (1 << 127) | (b.bits - a.bits) } // Return negative
            } else {
                // B is negative
                return I128 { bits: a.bits + (b.bits - (1 << 127)) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 127 == 0) {
                // B is positive
                return I128 { bits: a.bits + b.bits } // Return negative
            } else {
                // B is negative
                if (b.bits >= a.bits) return I128 { bits: b.bits - a.bits }; // Return positive
                return I128 { bits: a.bits - (b.bits - (1 << 127)) } // Return negative
            }
        }
    }

    /// @notice Multiply `a * b`.
    public fun mul(a: &I128, b: &I128): I128 {
        if (a.bits >> 127 == 0) {
            // A is positive
            if (b.bits >> 127 == 0) {
                // B is positive
                return I128 { bits: a.bits * b.bits } // Return positive
            } else {
                // B is negative
                return I128 { bits: (1 << 127) | (a.bits * (b.bits - (1 << 127))) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 127 == 0) {
                // B is positive
                return I128 { bits: (1 << 127) | (b.bits * (a.bits - (1 << 127))) } // Return negative
            } else {
                // B is negative
                return I128 { bits: (a.bits - (1 << 127)) * (b.bits - (1 << 127)) } // Return positive
            }
        }
    }

    /// @notice Divide `a / b`.
    public fun div(a: &I128, b: &I128): I128 {
        if (a.bits >> 127 == 0) {
            // A is positive
            if (b.bits >> 127 == 0) {
                // B is positive
                return I128 { bits: a.bits / b.bits } // Return positive
            } else {
                // B is negative
                return I128 { bits: (1 << 127) | (a.bits / (b.bits - (1 << 127))) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 127 == 0) {
                // B is positive
                return I128 { bits: (1 << 127) | ((a.bits - (1 << 127)) / b.bits) } // Return negative
            } else {
                // B is negative
                return I128 { bits: (a.bits - (1 << 127)) / (b.bits - (1 << 127)) } // Return positive
            }
        }
    }

    #[test]
    fun test_compare() {
        assert!(compare(&from(123), &from(123)) == EQUAL, 0);
        assert!(compare(&neg_from(123), &neg_from(123)) == EQUAL, 0);
        assert!(compare(&from(234), &from(123)) == GREATER_THAN, 0);
        assert!(compare(&from(123), &from(234)) == LESS_THAN, 0);
        assert!(compare(&neg_from(234), &neg_from(123)) == LESS_THAN, 0);
        assert!(compare(&neg_from(123), &neg_from(234)) == GREATER_THAN, 0);
        assert!(compare(&from(123), &neg_from(234)) == GREATER_THAN, 0);
        assert!(compare(&neg_from(123), &from(234)) == LESS_THAN, 0);
        assert!(compare(&from(234), &neg_from(123)) == GREATER_THAN, 0);
        assert!(compare(&neg_from(234), &from(123)) == LESS_THAN, 0);
    }

    #[test]
    fun test_add() {
        assert!(add(&from(123), &from(234)) == from(357), 0);
        assert!(add(&from(123), &neg_from(234)) == neg_from(111), 0);
        assert!(add(&from(234), &neg_from(123)) == from(111), 0);
        assert!(add(&neg_from(123), &from(234)) == from(111), 0);
        assert!(add(&neg_from(123), &neg_from(234)) == neg_from(357), 0);
        assert!(add(&neg_from(234), &neg_from(123)) == neg_from(357), 0);

        assert!(add(&from(123), &neg_from(123)) == zero(), 0);
        assert!(add(&neg_from(123), &from(123)) == zero(), 0);
    }

    #[test]
    fun test_sub() {
        assert!(sub(&from(123), &from(234)) == neg_from(111), 0);
        assert!(sub(&from(234), &from(123)) == from(111), 0);
        assert!(sub(&from(123), &neg_from(234)) == from(357), 0);
        assert!(sub(&neg_from(123), &from(234)) == neg_from(357), 0);
        assert!(sub(&neg_from(123), &neg_from(234)) == from(111), 0);
        assert!(sub(&neg_from(234), &neg_from(123)) == neg_from(111), 0);

        assert!(sub(&from(123), &from(123)) == zero(), 0);
        assert!(sub(&neg_from(123), &neg_from(123)) == zero(), 0);
    }

    #[test]
    fun test_mul() {
        assert!(mul(&from(123), &from(234)) == from(28782), 0);
        assert!(mul(&from(123), &neg_from(234)) == neg_from(28782), 0);
        assert!(mul(&neg_from(123), &from(234)) == neg_from(28782), 0);
        assert!(mul(&neg_from(123), &neg_from(234)) == from(28782), 0);
    }

    #[test]
    fun test_div() {
        assert!(div(&from(28781), &from(123)) == from(233), 0);
        assert!(div(&from(28781), &neg_from(123)) == neg_from(233), 0);
        assert!(div(&neg_from(28781), &from(123)) == neg_from(233), 0);
        assert!(div(&neg_from(28781), &neg_from(123)) == from(233), 0);
    }
}
