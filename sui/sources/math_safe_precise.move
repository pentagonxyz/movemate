// SPDX-License-Identifier: MIT

/// @title math_safe_precise
/// @dev Overflow-avoidant and precise math utilities missing in the Move language (for `u64`).
/// Specifically:
/// 1) `mul_div` calculates `a * b / c` but converts to `u128`s during calculations to avoid overflow.
/// 2) `quadratic` is the same as `math::quadratic` but uses `2**32` as a scalar instead of `2**16` for more precise math (converting to `u128`s during calculations for safety).
module movemate::math_safe_precise {
    use movemate::math_u128;

    const SCALAR: u64 = 1 << 32;
    const SCALAR_U128: u128 = 1 << 32;

    /// @notice Calculates `a * b / c` but converts to `u128`s for calculations to avoid overflow.
    public fun mul_div(a: u64, b: u64, c: u64): u64 {
        ((a as u128) * (b as u128) / (c as u128) as u64)
    }

    /// @notice Calculates `ax^2 + bx + c` assuming all variables are scaled by `2**32`.
    public fun quadratic(x: u64, a: u64, b: u64, c: u64): u64 {
        (
            (math_u128::exp((x as u128), 2) / SCALAR_U128 * (a as u128) / SCALAR_U128)
                + ((b as u128) * (x as u128) / SCALAR_U128)
                + (c as u128)
        as u64)
    }
}
