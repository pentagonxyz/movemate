# TODO

Ideas and improvements.

## Ideas

* Finance/economics library.
* Signed integers.
* Better fixed-point library.
* Ed25519 signature utils in Sui.
* Implement signatures in Sui [like (Aptos)](https://github.com/aptos-labs/aptos-core/blob/main/aptos-move/framework/aptos-stdlib/sources/signature.move).
* Data structures like double-ended queues, bitmaps, and (enumerable) sets? See [OpenZeppelin](https://docs.openzeppelin.com/contracts/4.x/api/utils#DoubleEndedQueue).
* Cross-chain messaging. See [Starcoin's `EthStateVerifier`](https://github.com/starcoinorg/starcoin-framework-commons/blob/main/sources/EthStateVerifier.move).
* Base 64 conversion library?

## Improvements

* `quadratic_vesting`: merge with `linear_vesting`?
* `quadratic_vesting`: better tests.
* `governance`: finish tests.
* `merkle_proof`: unit tests for multi-proof verification.
* `governance`: make delegation optional?
* `vector`, `merkle_proof`, etc.: fuzz testing?
