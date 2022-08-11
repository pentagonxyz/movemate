# TODO

Ideas and improvements.

## Ideas

* Signed integers.
* Better fixed-point library.
* Ed25519 signature utils in Sui.
* Implement signatures in Sui [like (Aptos)](https://github.com/aptos-labs/aptos-core/blob/main/aptos-move/framework/aptos-stdlib/sources/signature.move).
* Data structures like double-ended queues, bitmaps, and (enumerable) sets? See [OpenZeppelin](https://docs.openzeppelin.com/contracts/4.x/api/utils#DoubleEndedQueue).

## Improvements

* `quadratic_vesting`: merge with `linear_vesting`?
* `quadratic_vesting`: better tests.
* `linear_vesting`: clawback capability.
* `governance`: finish tests.
* `merkle_proof`: unit tests for multi-proof verification.
* `governance`: make delegation optional?
* `vector`, `merkle_proof`, etc.: fuzz testing?
