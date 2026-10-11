// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CadenceIMD} from "../src/CadenceIMD.sol";

/// @dev Test-only factory; demonstrates that CREATE2 mints to the immediate creator.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (CadenceIMD) {
        return new CadenceIMD{salt: salt}();
    }

    function move(CadenceIMD token, address to, uint256 value) external {
        require(token.transfer(to, value));
    }
}

contract CadenceIMDTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CadenceIMD internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new CadenceIMD();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "CadenceIMD");
        assertEq(token.symbol(), "CADENCEIMD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsMintAndMintsToImmediateDeployer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        CadenceIMD deployed = new CadenceIMD();
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_create2FactoryReceivesEntireSupply() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        CadenceIMD deployed = factory.deploy(keccak256("cadence-launch"));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(tx.origin), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
    }

    function test_launchAllocationsClaimsAndRoundTripTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        CadenceIMD deployed = factory.deploy(keccak256("cadence-launch"));
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool balance fixture");
        address remainder = makeAddr("remainder fixture");

        factory.move(deployed, distributor, SUPPLY / 10);
        factory.move(deployed, pool, SUPPLY * 8 / 10);
        factory.move(deployed, remainder, SUPPLY / 10);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), SUPPLY / 10);
        assertEq(deployed.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(deployed.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, SUPPLY / 10));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), SUPPLY / 10);

        vm.prank(pool);
        assertTrue(deployed.transfer(bob, 100 ether));
        assertEq(deployed.balanceOf(bob), 100 ether);
        vm.prank(bob);
        assertTrue(deployed.transfer(pool, 100 ether));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferEmitsAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25 ether);
        assertTrue(token.transfer(alice, 25 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMove() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWithoutBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferMaximumUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approvalEmitsCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 25 ether);
        assertTrue(token.approve(spender, 25 ether));
        assertEq(token.allowance(address(this), spender), 25 ether);
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromSpendsFiniteAllowanceAndEmits() public {
        token.approve(spender, 25 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.allowance(address(this), spender), 15 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 15 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 15 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceIsNotReduced() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_transferFromToSelfStillSpendsAllowance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromInsufficientAllowanceRevertsAtomically() public {
        token.approve(spender, 9 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 9 ether, 10 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10 ether);
        assertEq(token.allowance(address(this), spender), 9 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromZeroRecipientRestoresAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroOwnerReverts() public {
        // Spending even a zero allowance validates its owner before the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_spenderCannotUseAnotherSpendersApproval() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_revocationPreventsFurtherSpending() public {
        token.approve(spender, SUPPLY);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_deployerCannotSpendHoldersTokensWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_noMintBurnFreezeOrUpgradeEntryPoints() public {
        token.transfer(alice, 10 ether);
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess, "deployer reached unexpected entry point");
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess, "stranger reached unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 10 ether);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_runtimeHasNoForbiddenOpcodesAndFitsDeploymentLimit() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            }
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 value) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        value = bound(value, 0, SUPPLY);
        assertTrue(token.transfer(recipient, value));
        assertEq(token.balanceOf(recipient), value);
        assertEq(token.balanceOf(address(this)), SUPPLY - value);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromSpendsOnlyApprovedAmount(uint256 approved, uint256 value) public {
        approved = bound(approved, 0, SUPPLY);
        value = bound(value, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, value));
        assertEq(token.allowance(address(this), spender), approved - value);
        assertEq(token.balanceOf(address(this)), SUPPLY - value);
        assertEq(token.balanceOf(alice), value);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceAlwaysReverts(uint256 value) public {
        value = bound(value, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, value)
        );
        token.transfer(alice, value);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
