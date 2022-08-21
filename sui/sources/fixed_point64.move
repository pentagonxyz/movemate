module movemate::fixed_point64 {
    use std::errors;
    use movemate::u256::{Self, U256};
    use std::vector;
    use std::debug;

    // 64 fractional bits
    struct FixedPoint64 has copy, drop, store {
        value: u128
    }

    // future reference: implement all the following.
    // +	sum	uint	Sum LHS and RHS
    // -	sub	uint	Subtract RHS from LHS
    // /	div	uint	Divide LHS by RHS
    // *	mul	uint	Multiply LHS times RHS
    // %	mod	uint	Division remainder (LHS by RHS)
    // <<	lshift	uint	Left bit shift LHS by RHS
    // >>	rshift	uint	Right bit shift LHS by RHS
    // &	and	uint	Bitwise AND
    // ^	xor	uint	Bitwise XOR
    // |	or	uint	Bitwise OR

    const U128_MAX: u128 = 340282366920938463463374607431768211455;

    /// demoninator provided was zero
    const EDENOMINATOR:u64 = 0;
    /// quotient value would be too large to be held in a `u128`
    const EDIVISION: u64 = 1;
    /// multiplicated value would be too lrage to be held in a `u128`
    const EMULTIPLICATION: u64 = 2;
    /// division by zero error
    const EDIVISION_BY_ZERO: u64 = 3;
    /// computed ratio when converting to a `FixedPoint64` would be unrepresentable
    const ERATIO_OUT_OF_RANGE: u64 = 4;


    public fun create_from_rational(numerator: u128, denominator: u128): FixedPoint64 {
        let cast_numerator = u256::from_u128(numerator);
        let cast_denominator = u256::from_u128(denominator);

        let scaled_numerator = u256::shl(cast_numerator, 128);
        let scaled_denominator = u256::shl(cast_denominator, 64);

        // U256 module handles overflow. 
        let quotient = u256::as_u128(u256::div(scaled_numerator, scaled_denominator));

        assert!(quotient != 0 || numerator == 0, errors::invalid_argument(ERATIO_OUT_OF_RANGE));

        FixedPoint64 { value: quotient }
    }
}