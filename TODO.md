# TODO

Ideas and improvements.

## Ideas

* Finance/economics library.
* Better fixed-point library.
* Ed25519 signature utils in Sui.
* Implement signatures in Sui [like (Aptos)](https://github.com/aptos-labs/aptos-core/blob/main/aptos-move/framework/aptos-stdlib/sources/signature.move).
* Data structures like double-ended queues, bitmaps, and (enumerable) sets? See [OpenZeppelin](https://docs.openzeppelin.com/contracts/4.x/api/utils#DoubleEndedQueue).
* Cross-chain messaging. See [Starcoin's `EthStateVerifier`](https://github.com/starcoinorg/starcoin-framework-commons/blob/main/sources/EthStateVerifier.move).
* `math_i64` and `math_i128` library.
* `math_u256` library.
* `i256` library.
* Base 64 conversion library?

## Improvements

* `i64` and `i128`: finish tests.
* `math` and `math_u128`: add `abs` function, among others.
* `quadratic_vesting`: merge with `linear_vesting`?
* `quadratic_vesting`: better tests.
* `governance`: finish tests.
* `merkle_proof`: unit tests for multi-proof verification.
* `governance`: make delegation optional?
* `vector`, `merkle_proof`, etc.: fuzz testing?
* `to_string`: support `u64`?
* `to_string`: support `U256`?
