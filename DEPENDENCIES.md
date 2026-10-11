# Vendored dependencies

Dependencies are checked in as ordinary source files, with no submodules or
package-install step. The included upstream sources are unmodified.

| Dependency | Version / commit | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/69c8def5f222ff96f2b5beff05dfba996368aa79) | v5.1.0 / `69c8def5f222ff96f2b5beff05dfba996368aa79` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol` | MIT, in `lib/openzeppelin-contracts/LICENSE` |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 / `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Complete `src/` tree, used by tests | MIT or Apache-2.0, in `lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE` |

`remappings.txt` resolves imports to these local copies. OpenZeppelin is the only
production dependency; forge-std is used only in tests. These versions support
the pinned Solidity 0.8.26 compiler.

`DEPENDENCIES.sha256` contains a SHA-256 checksum for every vendored source and
license. To check integrity from the project root, run:

```sh
shasum -a 256 -c DEPENDENCIES.sha256
```
