# Local validation

Validated with Foundry 1.8.3 and Solidity 0.8.26 using the repository's pinned
compiler, Cancun target, 200 optimizer runs, and `bytecode_hash = "none"`.

| Check | Result |
| --- | --- |
| `forge build` | Passed |
| `forge test` | 31 passed, 0 failed, 0 skipped |
| `forge fmt --check` | Passed |
| Three fuzz tests | 512 runs each |
| Stateful ledger invariant | 128 runs, 8,192 calls, 0 reverts |
| Vendored dependency SHA-256 checks | All 36 files matched |
| Creation bytecode | 2,645 bytes, no unresolved library links |
| Runtime bytecode | 1,752 bytes, below the 24,576-byte EIP-170 limit |
| Runtime opcode scan | No `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT` |
| Constructor ABI | No arguments, nonpayable |

A separate clean directory containing only the configuration, remappings, `src/`,
`test/`, and `lib/` also passed `forge build --offline`,
`forge test --offline --threads 4`, and `forge fmt --check` with an empty process
environment. It contained no previous build cache, supplied task inputs, or
scratch tests. The installed Foundry toolchain and cached pinned compiler were
available, as they are in the independent verification environment.

The local source and ABI review confirmed that the only public state-changing
functions are `transfer`, `approve`, and `transferFrom`. `_mint` is internal and
is called only by the constructor. No production external call, administrative
role, dynamic dependency, linked library, or upgrade mechanism is present.

The provided protected test was read to identify the admission requirements. Its
full Uniswap/launch integration was not run locally: the launch infrastructure,
manifest-resolved bytecode, and harness environment are supplied by the separate
admission stage. Local factory/allocation fixtures establish token transfer
behavior but do not substitute for those integration checks. Slither and Mythril
were not run. Deployment, explorer verification, and the independent release
review remain responsibilities of the launch process.
