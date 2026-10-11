// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CadenceIMD} from "../src/CadenceIMD.sol";

/// @dev A separate ledger models successful and rejected calls among four holders.
/// Inputs come from this ledger, never from the token's reported balances/allowances.
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

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value) public {
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

    /// @dev Exercise revocation and the finite/infinite boundary often, even late in a sequence.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 mode) external {
        uint256 value;
        if (mode % 3 == 1) value = type(uint256).max - 1;
        if (mode % 3 == 2) value = type(uint256).max;
        approve(ownerSeed, spenderSeed, value);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 value) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        value = bound(value, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, value));
        vm.prank(from);
        token.transfer(to, value);
        // No ledger update: the invariant verifies that every actor and allowance stayed intact.
    }

    function transferFromOverAllowance(uint256 fromSeed, uint256 approved, uint256 value) external {
        // Pick a funded owner so a missing allowance check cannot hide behind a balance revert.
        uint256 ownerIndex = fromSeed % actors.length;
        while (expectedBalance[actors[ownerIndex]] == 0) {
            ownerIndex = (ownerIndex + 1) % actors.length;
        }
        address from = actors[ownerIndex];
        uint256 spenderIndex = (ownerIndex + 1) % actors.length;
        address spender = actors[spenderIndex];
        address to = actors[(ownerIndex + 2) % actors.length];
        approved = bound(approved, 0, expectedBalance[from] - 1);
        value = bound(value, approved + 1, expectedBalance[from]);
        approve(ownerIndex, spenderIndex, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, value)
        );
        vm.prank(spender);
        token.transferFrom(from, to, value);
    }

    function transferFromOverBalance(
        uint256 fromSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 value,
        bool infinite
    ) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        value = bound(value, balance + 1, type(uint256).max - 1);
        approve(fromSeed, spenderSeed, infinite ? type(uint256).max : value);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, value));
        vm.prank(spender);
        token.transferFrom(from, to, value);
        // In particular, a finite allowance spent before the balance check must be restored.
    }

    function transferToZero(uint256 fromSeed, uint256 spenderSeed, uint256 value, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        value = bound(value, 0, expectedBalance[from]);
        if (delegated) {
            approve(fromSeed, spenderSeed, value);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(from, address(0), value);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(from);
            token.transfer(address(0), value);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), value);
    }

    /// @dev An inverse property: the two transfers must restore all balances and allowances.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 value) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        value = bound(value, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
        vm.prank(to);
        assertTrue(token.transfer(from, value));
        // Deliberately leave the reference ledger unchanged.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CadenceIMDInvariantTest is Test {
    CadenceHandler internal handler;
    CadenceIMD internal token;

    function setUp() public {
        handler = new CadenceHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = CadenceHandler.transfer.selector;
        selectors[1] = CadenceHandler.approve.selector;
        selectors[2] = CadenceHandler.transferFrom.selector;
        selectors[3] = CadenceHandler.approveBoundary.selector;
        selectors[4] = CadenceHandler.transferOverBalance.selector;
        selectors[5] = CadenceHandler.transferFromOverAllowance.selector;
        selectors[6] = CadenceHandler.transferFromOverBalance.selector;
        selectors[7] = CadenceHandler.transferToZero.selector;
        selectors[8] = CadenceHandler.approveZeroSpender.selector;
        selectors[9] = CadenceHandler.roundTrip.selector;
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
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(totalBalances, token.totalSupply());
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.name(), "CadenceIMD");
        assertEq(token.symbol(), "CADENCEIMD");
        assertEq(token.decimals(), 18);
    }
}
