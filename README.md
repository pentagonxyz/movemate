# Movemate

Movemate is the [Solmate](https://github.com/transmissions11/solmate) of Move (i.e., smart contract building blocks) built for Aptos and Sui. Movemate aims to provide all the standard libraries and modules that Move developers will commonly be using. Movemate aims for maximum efficiency, composability, and ease of implementation.

## Modules

* `crit_bit`: [Crit-bit trees](https://cr.yp.to/critbit.html) data structure.
* `escrow` (Sui only): Very basic object escrow module on Sui.
* `escrow_shared` (Sui only): Basic object escrow module with refunds and arbitration on Sui.
* `governance`: On-chain tokenholder governance using coins.
* `linear_vesting`: Linear vesting of coins for a given beneficiary.
* `math`: Standard math utilities missing in the Move language (for `u64`).
* `math_u128`: Standard math utilities missing in the Move language (for `u128`).
* `merkle_proof`: Merkle proof verification utilities.
* `vectors`: Vector utilities--specifically, comparison operators and a binary search function.
* `virtual_block`: Replace latency auctions with gas auctions (with control over MEV rewards) via virtual blocks.

### Outside the repo

* [`multisig_wallet`: Multisignature wallet for coins and arbitrary objects.](https://github.com/pentagonxyz/multisig-wallet-move)
* [`oracle_factory` (Sui only): Create and share custom oracles, aggregating data across validator sets.](https://github.com/pentagonxyz/move-oracles)
* [`xyk_amm`: Constant product (XY=K) AMM (like Uniswap V2).](https://github.com/pentagonxyz/xyk-amm-move)
