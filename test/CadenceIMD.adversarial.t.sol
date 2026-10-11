// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CadenceIMD} from "../src/CadenceIMD.sol";

/// @dev Regression cases and algebraic properties supplement the existing token tests.
/// All funds come from the real constructor mint; balances and allowances are never patched.
/// forge-config: default.fuzz.runs = 1000
contract CadenceIMDAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CadenceIMD internal token;
    address internal holder = makeAddr("adversarial holder");
    address internal spender = makeAddr("adversarial spender");
    address internal recipient = makeAddr("adversarial recipient");

    function setUp() public {
        token = new CadenceIMD();
    }

    function test_oneWeiCannotBeSpentTwice() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transfer(recipient, 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        token.transfer(holder, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(holder);
        token.transfer(holder, 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerUsingTransferFromNeedsAndConsumesSelfApproval() public {
        token.transfer(holder, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);

        vm.startPrank(holder);
        assertTrue(token.approve(holder, 1));
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.stopPrank();
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_approvalInOppositeDirectionGrantsNoSpendingRights() public {
        token.transfer(holder, 1);
        vm.prank(spender);
        assertTrue(token.approve(holder, type(uint256).max));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(spender, holder), type(uint256).max);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferFromCannotBypassBalanceWithInfiniteApproval() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferCannotExceedBalance() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(spender);
        token.transferFrom(holder, holder, 2);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.balanceOf(holder), 1);
    }

    function test_infiniteApprovalCanBeReducedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 2);
        assertEq(token.allowance(address(this), spender), 1);

        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_exhaustedAllowanceDoesNotReviveWhenHolderIsRefunded() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroIsRejected() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalToZeroSpenderIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_insufficientAllowanceFailsEvenWhenFullyFunded(uint256 value, uint256 approved) public {
        value = bound(value, 1, SUPPLY);
        approved = bound(approved, 0, value - 1);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, value)
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, value);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedTransferFromCanRetryAfterFunding(
        uint256 balance,
        uint256 value,
        uint256 approved,
        bool infinite
    ) public {
        balance = bound(balance, 0, SUPPLY - 1);
        value = bound(value, balance + 1, SUPPLY);
        approved = infinite ? type(uint256).max : bound(approved, value, type(uint256).max - 1);
        token.transfer(holder, balance);
        vm.prank(holder);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, value));
        vm.prank(spender);
        token.transferFrom(holder, recipient, value);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        // Retry exactly the failed request without renewing its approval.
        assertTrue(token.transfer(holder, value - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, value));
        assertEq(token.allowance(holder, spender), infinite ? approved : approved - value);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), value);
        assertEq(token.balanceOf(address(this)), SUPPLY - value);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        token.approve(spender, first);
        token.approve(recipient, first);
        vm.prank(holder);
        token.approve(spender, first);

        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), recipient), first);
        assertEq(token.allowance(holder, spender), first);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroTransferFromPreservesExistingApproval(uint256 approved) public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingDelegatedTransferMatchesSingleTransfer(uint256 value, uint256 firstPart) public {
        value = bound(value, 0, SUPPLY);
        firstPart = bound(firstPart, 0, value);
        CadenceIMD single = new CadenceIMD();
        single.approve(spender, value);
        token.approve(spender, value);

        vm.startPrank(spender);
        assertTrue(single.transferFrom(address(this), recipient, value));
        assertTrue(token.transferFrom(address(this), recipient, firstPart));
        assertTrue(token.transferFrom(address(this), recipient, value - firstPart));
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.balanceOf(recipient), value);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }
}
