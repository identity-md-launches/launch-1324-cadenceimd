# CadenceIMD

A fixed-supply ERC-20 for the IdentityMD custom-token launch on Ethereum (chain ID 1).

| Deployment parameter | Value |
| --- | --- |
| Solidity contract | `src/CadenceIMD.sol:CadenceIMD` |
| Token name | `CadenceIMD` |
| Symbol | `CADENCEIMD` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Compiler | Solidity `0.8.26` |
| EVM / optimizer | Cancun / enabled, 200 runs |
| Bytecode metadata hash | `none` |
| Application contracts | None |

## Behavior and assumptions

The constructor mints the full supply once, emitting `Transfer` from the zero
address to the deployer. In the launch flow, the deploying factory receives all
tokens. A direct deployment instead gives all tokens to the account creating the
contract. There are no external calls or address configuration in the constructor.

The implementation inherits the vendored OpenZeppelin ERC-20 without modifying
its transfer or allowance logic. Transfers deliver the exact requested amount;
there are no taxes, rebases, burns, transfer limits, or special address exemptions.
There is no owner, mint entry point, pause, blacklist, seizure, proxy, or upgrade
mechanism. Total supply remains constant after construction.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
OpenZeppelin's ERC-6093 errors on failure. Zero-value transfers to valid addresses
are supported and emit `Transfer`. Self-transfers preserve balances. Transfers to
the zero address and approvals to a zero spender revert. Finite allowances are
spent by `transferFrom`; a maximum `uint256` allowance remains unchanged. `approve`
emits `Approval`, while spending an allowance does not emit an additional
`Approval` event in this OpenZeppelin version. Integrations should read `allowance`.

## Build and check

Install Foundry and make Solidity 0.8.26 available in its compiler cache. From the
repository root:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`.
No dependency installation, network, environment variables, FFI, or filesystem
cheatcodes are needed by the build or tests once the pinned compiler is available.
`DEPENDENCIES.md` records provenance and `DEPENDENCIES.sha256` records file hashes.

Tests cover constructor metadata, mint events, the entire supply, direct and
CREATE2 factory deployment, exact allocation and claim transfers, transfer and
approval events, full-balance/zero/self transfers, allowance spending and
revocation, invalid recipients, insufficient funds/allowances, atomic rollback,
and unavailable administrative entry points. Fuzz tests exercise arbitrary
transfer amounts and recipients. A stateful invariant compares balances and
allowances against a separate ledger across sequences of transfers, approvals,
and delegated transfers (128 sequences of 64 calls by default).

The allocation fixture checks token movements corresponding to the 10% swarm,
80% pool, and 10% remainder split. Its pool address is a local test actor; it does
not simulate Uniswap price formation or execute swaps. The supplied protected
launch harness additionally exercises the actual PoolManager and launch contracts
in the separate admission environment. That environment and its contracts are
not part of this token project.

## Deployment and operational responsibilities

Deploy the compiled `CadenceIMD` creation bytecode directly with no arguments and
no ETH. The factory supports this constructor without any initialization call or
linked libraries. Using a deployment helper makes that helper the initial holder;
the operator must ensure the intended factory is the immediate deployer. Do not
deploy this constructor-based contract behind a proxy.

The launch operator is responsible for selecting the correct build artifact,
reviewing the creation bytecode and compiler settings, and having the factory
distribute its supply. The token itself does not allocate balances to the swarm,
pool, or requester. Per the assignment, the factory sends 10% to its distributor,
uses 80% for pool seeding, and forwards 10% to the specified remainder recipient.
Those addresses and pool economics belong to the launch system and its later
manifest step. This repository does not create `launch.json` or broadcast any
transaction.

### After launch

- No token settings, owner setup, keeper, oracle, or ongoing administrative action
  is required or available.
- The launch operator verifies the deployed source and compiler settings on the
  explorer, confirms the token's metadata and `10^27` supply, and checks the mint
  and distribution events against the launch configuration.
- Holders protect their keys and manage spender approvals. Prefer bounded
  allowances. To replace an existing allowance, revoke it to zero, wait for
  confirmation, and then set the new amount; ordinary ERC-20 approvals can be
  spent before a pending update is mined.
- Transfers cannot be reversed. Tokens sent to a contract without a withdrawal
  mechanism, including this token contract, cannot be recovered by an admin.

## Security review scope

The task's supplied security reference was checked against the implementation.
The only production state changes are the constructor mint and ERC-20 balance
and allowance operations. Runtime transfers make no external calls; there are no
oracles, randomness, signatures, payable entry points, or privileged operations.
The runtime opcode test checks for `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT`
and enforces the EIP-170 code-size limit. See `VALIDATION.md` for executed checks
and their limits. Tests and a local review do not replace the launch's independent
security review.
