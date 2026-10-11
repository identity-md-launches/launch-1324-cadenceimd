// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title CadenceIMD
/// @notice Fixed-supply ERC-20. The immediate deployer receives the entire supply once.
/// @dev During an IdentityMD launch the deployer is the factory. There are no admin powers.
contract CadenceIMD is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("CadenceIMD", "CADENCEIMD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
