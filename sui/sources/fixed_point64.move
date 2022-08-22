module movemate::fixed_point64 {
    use std::errors;
    use movemate::u256::{Self};
    //use std::vector;
    // use std::debug;

    // 64 fractional bits
    struct FixedPoint64 has copy, drop, store {
        value: u128
    } 

    // future reference
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

    // todo this spec schema stuff? in https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/deps/move-stdlib/sources/fixed_point32.move
    // cant find this stuff in docs so not priority

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
        // make both u256 to ensure no overflow when dividing.
        let cast_numerator = u256::from_u128(numerator);
        let cast_denominator = u256::from_u128(denominator);
     
        // shift bits left
        let scaled_numerator = u256::shl(cast_numerator, 128);
        let scaled_denominator = u256::shl(cast_denominator, 64);

        // U256 module handles overflow. 
        let result = u256::div(scaled_numerator, scaled_denominator);

        let quotient = u256::as_u128(result);

        assert!(quotient != 0 || numerator == 0, errors::invalid_argument(ERATIO_OUT_OF_RANGE));

        FixedPoint64 { value: quotient }
    }

    // multiply a u128 integer by a fixed_point number
    public fun multiply_u128(val: u128, multiplier: FixedPoint64): u128 {
        let unscaled_product = u256::mul(
            u256::from_u128(val), 
            u256::from_u128(multiplier.value)
        );

        // unscaled product has 128 fractional bits, so need to rescale by rshifting
        let product = u256::as_u128(u256::shr(unscaled_product, 64));
        
        product
    }

    public fun divide_u128(val: u128, divisor: FixedPoint64): u128 {
        let scaled_div = u256::shl(u256::from_u128(val), 32);
        let quotient = u256::as_u128(u256::div(scaled_div, u256::from_u128(divisor.value)));

        quotient
    }

    public fun create_from_raw_value(value: u128): FixedPoint64 {
        FixedPoint64 { value }
    }

    // raw value getter
    public fun get_raw_value(num: FixedPoint64): u128 {
        num.value
    }

    // true if value is zero 
    public fun is_zero(num: FixedPoint64): bool {
        num.value == 0
    }

    #[test]
    fun test_create_raw(){
        let test_fixed = create_from_raw_value(1099494850560);
        assert!(get_raw_value(test_fixed) == 1099494850560, 0)
    }

    #[test]
    fun test_create_rational() {
        // 1/2 is 0.5, so the hex should look like [0000 0000 0000 0000].[8000 0000 0000 0000]  
        // since 8000 = 1000 0000 0000 0000 => 1/2 + 0/4 + 0/8 + ... = 0.5
        assert!(get_raw_value(create_from_rational(1, 2)) == 0x8000000000000000, 4);
        assert!(get_raw_value(create_from_rational(1, 3)) == 0x5555555555555555, 4);
        assert!(get_raw_value(create_from_rational(2, 4)) == 0x8000000000000000, 4);
        assert!(get_raw_value(create_from_rational(0x10000000000000000, 0x20000000000000000)) == 0x8000000000000000, 4);
    }

    #[test]
    fun test_create_big_rational() {
        // should be 1.0, ie 1 0000 0000 0000 0000
        assert!(get_raw_value(create_from_rational(U128_MAX, U128_MAX)) == 0x10000000000000000, 4);
    }

    #[test]
    #[expected_failure(abort_code = 3)]
    fun test_rational_zero_denom() {
        create_from_rational(1, 0);
    }

    #[test]
    fun test_zero_mul(){
        let multiplier = create_from_rational(0, 1);
        assert!(multiply_u128(5, multiplier) == 0, 2);

    }

    #[test] 
    fun test_multiplication() {
        let multiplier = create_from_rational(5, 1);
        assert!(multiply_u128(5, multiplier) == 25, 2);

        // note 5 * 1/5 rounds down to zero since its represented as 0000 0000 0000 0000 1111 1111 1111 1111 or 0.9999....
        assert!(multiply_u128(5, create_from_rational(1, 5)) == 0, 2);
        assert!(multiply_u128(5, create_from_rational(1, 2)) == 2, 2);
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_multiplication_overflow() {
        assert!(multiply_u128(U128_MAX, create_from_rational(2, 1)) == 0, 2);
    }
}