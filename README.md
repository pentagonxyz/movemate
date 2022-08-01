# Movemate

Movemate is the [Solmate](https://github.com/transmissions11/solmate) of Move (i.e., smart contract building blocks) built for Aptos and Sui. Movemate aims to provide all the standard libraries and modules that Move developers will commonly be using. Movemate aims for maximum efficiency, composability, and ease of implementation.

## Modules

* `CritBit`: [Crit-bit trees](https://cr.yp.to/critbit.html) data structure.
* `Escrow` (Sui only): Very basic object escrow module on Sui.
* `EscrowShared` (Sui only): Basic object escrow module with refunds and arbitration on Sui.
* `Governance`: On-chain tokenholder governance using coins.
* `LinearVesting`: Linear vesting of coins for a given beneficiary.
* `Math`: Standard math utilities missing in the Move language (for `u64`).
* `MathU128`: Standard math utilities missing in the Move language (for `u128`).
* `MerkleProof`: Merkle proof verification utilities.
* `Vectors`: Vector utilities--specifically, comparison operators and a binary search function.
* `VirtualBlock`: Replace latency auctions with gas auctions (with control over MEV rewards) via virtual blocks.
