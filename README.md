# Bankers (BANKERS)

Bankers is an immutable, fixed-supply ERC-20. Its constructor mints **1,000,000,000 BANKERS**, with **18 decimals**, to the address that directly deploys it. The complete supply in base units is **1000000000000000000000000000** (`10^27`).

## Contract and assumptions

The deployable contract is [`src/Bankers.sol:Bankers`](src/Bankers.sol). It uses the vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation and adds only the fixed supply and constructor mint.

- `name()` is `Bankers`; `symbol()` is `BANKERS`; `decimals()` is `18`.
- The direct deployer receives the entire supply in one mint, with one `Transfer` event from the zero address. When deployed through a factory, the factory receives it; the transaction origin receives nothing automatically.
- Transfers deliver the exact requested amount. There are no taxes, fees, rebases, transfer limits, address exemptions, or recipient callbacks.
- There is no owner, minter, initializer, pause, blacklist, seizure, external burn function, proxy, or upgrade mechanism. Supply cannot increase or decrease after construction.
- Standard ERC-20 transfers and approvals return `true` on success and revert on failure using OpenZeppelin's ERC-6093 errors. Zero-amount transfers to valid recipients are allowed; transfers to the zero address and approvals to the zero spender are rejected.
- `approve` replaces an allowance. `transferFrom` requires allowance even when the caller is the source address. Finite allowances decrease when spent; `type(uint256).max` is treated as unlimited and does not decrease. A reverted transfer does not consume allowance.
- `approve` emits `Approval`; successful transfers emit `Transfer`. In this dependency version, spending an allowance through `transferFrom` does not emit an additional `Approval`. Integrations should query `allowance` for the current value.

The brief requests a plain token, so there are no application contracts or integrations with outside contracts. The token uses no oracles, block numbers, timestamps, randomness, or chain-specific precompiles.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

[`foundry.toml`](foundry.toml) pins `solc = "0.8.26"`, optimization at 200 runs, the Paris EVM target, and `bytecode_hash = "none"`. Paris avoids requiring newer EVM opcodes. FFI and filesystem permissions are not enabled. All imported Solidity dependencies are ordinary files in `lib/`; no network, package installation, git submodule, or environment variable is needed for the tests. The verification worker supplies the pinned compiler; no compiler executable is included here.

The test suites cover:

- Metadata, exact initial supply, mint events, and CREATE2 factory deployment.
- Exact token movements for the factory's 10%/88%/2% distribution, distributor claims, and transfers into and out of a pool-manager address.
- Direct transfers, approvals, finite and unlimited allowances, zero amounts, full balances, self-transfers, and transfers to contracts.
- Insufficient balances and allowances, zero-address inputs, allowance isolation and revocation, atomic rollback, and rejected administrative calls.
- Fuzzed balance/allowance boundaries (512 cases per fuzz test) and stateful balance/supply conservation (128 runs of 64 actions per invariant).
- Runtime size and absence of `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT` opcodes.

The distribution test exercises token-side settlement, not a Uniswap deployment or a priced swap. The separate pinned admission harness is responsible for the actual pool seed and buy/sell checks with its launch configuration. It is an input to the assignment, not a dependency of this project's standalone tests.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity artifact | `src/Bankers.sol:Bankers` |
| Contract identifier | `Bankers` |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` |
| Supply recipient | Direct deployer (`msg.sender`); the launch factory at launch |
| Total supply, base units | `1000000000000000000000000000` |
| Decimals | `18` |
| Initialization calls / library linking | None |
| Intended launch chain | Robinhood Chain, chain ID `4663`, as supplied in the task |

Inspect the creation bytecode and ABI locally with:

```sh
forge inspect src/Bankers.sol:Bankers bytecode
forge inspect src/Bankers.sol:Bankers abi
```

The token constructor does not call any other contract. It can be deployed on an empty chain. Its behavior is independent of chain ID. No keys, RPCs, owner addresses, or recipient addresses need to be supplied to the token constructor.

The supplied launch policy assigns the factory responsibility for distributing 10% of the supply to its Merkle distributor, using 88% for the pool allocation, and forwarding the 2% remainder. None of these allocations is pre-minted or reserved by the token. The supplied launch settings are the IMD pair at `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, pool fee `12500`, tick spacing `60`, initial-price provenance `79228162514264337593543950336`, and economics `{"poolBps":8800,"initialMarketCapWei":"2500000000000000000000","remainderTo":"0xbdd848d77af9e2a9c8def8fbfa6fd3a36c7dfde7"}`. These are task-provided settings for the external launch process, not token constructor inputs or independently verified chain observations. The deployer derives the actual opening price from the launch economics and currency ordering.

The separate launch step creates `launch.json`, verifies the build, and deploys through the factory. This project does not include a manifest or broadcasting script and has not deployed a contract.

## After launch

There are **no owner settings or maintenance transactions**. The launch operator is responsible for distributing the factory's supply, establishing liquidity, checking the deployed code and metadata against the accepted artifact, and publishing the deployed address and verified source. Independent adversarial review remains a release responsibility; passing these tests is not a security audit. Slither and Mythril have not been run.

Holders are responsible for their keys, recipient addresses, and spender approvals. Use allowances appropriate to the intended spend, revoke unused approvals, and account for transaction ordering when replacing a nonzero allowance (a spender may consume an existing allowance before a change confirms). Native-currency transfers to the token revert. ERC-20 transfers to the token contract itself are possible, but there is no recovery function; accidental assets sent there cannot be rescued by an administrator. Chain availability and finality are external to this token.

## Vendored dependencies

[`dependencies.lock.json`](dependencies.lock.json) records exact upstream commits, archive URLs, and SHA-256 hashes for every vendored file.

- [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3): the unmodified ERC-20 implementation and its four source dependencies, plus the MIT license.
- [forge-std v1.9.6](https://github.com/foundry-rs/forge-std/tree/3b20d60d14b343ee4f908cb8079495c07f5e8981): unmodified `src/` files for local tests, plus the Apache-2.0 and MIT licenses.

The new contract and tests are MIT licensed; upstream files retain their own license notices.
