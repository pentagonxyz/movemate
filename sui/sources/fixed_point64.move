module movemate::fixed_point64 {
    use std::errors;
    use movemate::u256::{Self, U256};
    use std::vector;
    use std::debug;

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

}