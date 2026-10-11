// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CadenceIMD} from "../src/CadenceIMD.sol";

/// @dev A separate ledger models arbitrary sequences among four funded holders.
contract CadenceHandler is Test {
    CadenceIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new CadenceIMD();
        uint256 allocation = 250_000_000 * 10 ** 18;
        for (uint256 i; i < actors.length; ++i) {
            address actor = makeAddr(string.concat("invariant holder ", vm.toString(i)));
            actors[i] = actor;
            expectedBalance[actor] = allocation;
            assertTrue(token.transfer(actor, allocation));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 value) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        value = bound(value, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        expectedAllowance[owner][spender] = value;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 value) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < approved ? expectedBalance[from] : approved;
        value = bound(value, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, value));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= value;
    }
}

contract CadenceIMDInvariantTest is Test {
    CadenceHandler internal handler;
    CadenceIMD internal token;

    function setUp() public {
        handler = new CadenceHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = CadenceHandler.transfer.selector;
        selectors[1] = CadenceHandler.approve.selector;
        selectors[2] = CadenceHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyBalancesAndAllowancesMatchLedger() public view {
        uint256 totalBalances;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner));
            totalBalances += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(totalBalances, token.totalSupply());
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
