// SPDX-License-Identifier: MIT

/// @title Math
/// @dev Standard math utilities missing in the Move language (for `u64`).
module movemate::Math {
    const ROUNDING_DOWN: u8 = 0; // Toward negative infinity
    const ROUNDING_UP: u8 = 0; // Toward infinity
    const ROUNDING_ZERO: u8 = 0; // Toward zero

    /// @dev Returns the largest of two numbers.
    public fun max(a: u64, b: u64): u64 {
        if (a >= b) a else b
    }

    /// @dev Returns the smallest of two numbers.
    public fun min(a: u64, b: u64): u64 {
        if (a < b) a else b
    }

    /// @dev Returns the average of two numbers. The result is rounded towards zero.
    public fun average(a: u64, b: u64): u64 {
        // (a + b) / 2 can overflow.
        (a & b) + (a ^ b) / 2
    }

    /// @dev Returns the ceiling of the division of two numbers.
    /// This differs from standard division with `/` in that it rounds up instead of rounding down.
    public fun ceil_div(a: u64, b: u64): u64 {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        if (a == 0) 0 else (a - 1) / b + 1
    }

    /// @dev Returns a to the power of b.
    public fun exp(a: u64, b: u64): u64 {
        let c = 1;

        while (b > 0) {
            if (b & 1 > 0) c = c * a;
            b = b >> 1;
            a = a * a;
        };

        c
    }

    /// @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
    /// Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
    /// Costs only 9 gas in comparison to the 16 gas `sui::math::sqrt` costs (tested on Aptos).
    public fun sqrt(a: u64): u64 {
        if (a == 0) {
            return 0
        };

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`.
        // We also know that `k`, the position of the most significant bit, is such that `msb(a) = 2**k`.
        // This gives `2**k < a <= 2**(k+1)` => `2**(k/2) <= sqrt(a) < 2 ** (k/2+1)`.
        // Using an algorithm similar to the msb computation, we are able to compute `result = 2**(k/2)` which is a
        // good first approximation of `sqrt(a)` with at least 1 correct bit.
        let result = 1;
        let x = a;
        if (x >> 32 > 0) {
            x = x >> 32;
            result = result << 16;
        };
        if (x >> 16 > 0) {
            x = x >> 16;
            result = result << 8;
        };
        if (x >> 8 > 0) {
            x = x >> 8;
            result = result << 4;
        };
        if (x >> 4 > 0) {
            x = x >> 4;
            result = result << 2;
        };
        if (x >> 2 > 0) {
            result = result << 1;
        };

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        result = (result + a / result) >> 1;
        min(result, a / result)
    }

    /// @notice Calculates sqrt(a), following the selected rounding direction.
    public fun sqrt_rounding(a: u64, rounding: u8): u64 {
        let result = sqrt(a);
        if (rounding == ROUNDING_UP && result * result < a) {
            result = result + 1;
        };
        result
    }
}
