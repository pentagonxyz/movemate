# Movemate

**A library of module building blocks for Move on Aptos and Sui.**

Movemate provides an advanced standard library of common modules in the Move ecosystem (working in tandem with the native frameworks), focusing on security, efficiency, composability, and ease of implementation.

## Modules

* `acl`: Multi-role access control list (ACL).
* `bcd`: Binary canonical DEserialization. Convert `vector<u8>` to `u64` and `u128`.
* `bloom_filter`: Space-efficient probabilistic data structure for checking if an element is part of a set.
* `box`: On Aptos, send objects without the recipient having to set up a store for themselves beforehand. On Sui, transfer objects with the `store` ability but not the `key` ability.
* `crit_bit`: [Crit-bit trees](https://cr.yp.to/critbit.html) data structure. (Thanks to Econia.)
* `date`: Date conversion library in Move.
* `escrow` (Sui only): Very basic object escrow module on Sui.
* `escrow_shared` (Sui only): Basic object escrow module with refunds and arbitration on Sui.
* `governance`: On-chain coinholder governance (store coins and other objects; on Aptos, retrieve a `signer` for special actions like upgrading packages).
* `i64`: Signed 64-bit integers.
* `i128`: Signed 128-bit integers.
* `linear_vesting`: Linear vesting of coins for a given beneficiary.
* `math`: Standard math utilities missing in the Move language (for `u64`).
* `math_safe_precise`: `mul_div` for `u64`s while avoiding overflow and a more precise `quadratic` function.
* `math_u128`: Standard math utilities missing in the Move language (for `u128`).
* `merkle_proof`: Merkle proof verification utilities.
* `pseudorandom`: Pseudorandom number generator.
* `to_string`: `u128` to `String` conversion utilities.
* `u256`: Unsigned 256-bit integer implementation in Move. (Thanks to Pontem.) Includes bitwise operations and `vector<u8>` conversion.
* `vectors`: Vector utilities--specifically, comparison operators and a binary search function.
* `virtual_block`: Replace latency auctions with gas auctions (with control over MEV rewards) via virtual blocks.

### Outside the repo

* [`multisig_wallet`: Multisignature wallet for coins and arbitrary objects.](https://github.com/pentagonxyz/multisig-wallet-move)
* [`oracle_factory` (Sui only): Create and share custom oracles, aggregating data across validator sets.](https://github.com/pentagonxyz/move-oracles)
* [`xyk_amm`: Constant product (XY=K) AMM (like Uniswap V2).](https://github.com/pentagonxyz/xyk-amm-move)

## Usage

### Sui

Add the following to your `Move.toml`:

```
[dependencies.Movemate]
git = "https://github.com/pentagonxyz/movemate.git"
subdir = "sui"
rev = "devnet"
```

### Aptos

Add the following to your `Move.toml`:

```
[dependencies.Movemate]
git = "https://github.com/pentagonxyz/movemate.git"
subdir = "aptos"
rev = "devnet"
```

## Testing

### Sui

```
cd movemate/sui
sui move test --instructions 100000
```

### Aptos

```
cd movemate/aptos
aptos move test
```

## Publishing

### Sui

```
sui client publish --path ./movemate/sui --gas-budget 30000
```

### Aptos

```
aptos move publish --package-dir ./movemate/aptos
aptos move run --function-id 0x3953993C1D8DFB8BAC2DA2F4DBA6521BA3E705299760FBEE6695E38BCE712A82::pseudorandom::init
```
