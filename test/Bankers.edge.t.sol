// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Bankers} from "src/Bankers.sol";

/// @dev Complements the basic ERC-20 tests with boundaries and multi-call approval lifecycles.
/// forge-config: default.fuzz.runs = 1000
contract BankersEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Bankers internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new Bankers();
        alice = makeAddr("edge-alice");
        bob = makeAddr("edge-bob");
        spender = makeAddr("edge-spender");
    }

    function test_DelegatedFullSupplyTransferExhaustsBalanceAndAllowance() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);

        // Move the last wei separately; the fixed supply must be transferable down to its smallest unit.
        vm.startPrank(alice);
        assertTrue(token.transfer(bob, SUPPLY - 1));
        assertEq(token.balanceOf(alice), 1);
        assertTrue(token.transfer(bob, 1));
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_MaximumFiniteAllowanceIsNotTreatedAsInfinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_ApprovalFromEmptyOwnerRemainsUsableAfterFunding() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(spender), 0);

        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DirectAndSelfTransfersDoNotConsumeOrCopyApprovals() public {
        assertTrue(token.approve(spender, 7));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.allowance(alice, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferFromWithInfiniteApprovalStillRequiresBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfApprovalAllowsTransferFromButIsStillConsumed() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_MaximumTransferAmountCannotOverflowBalancesOrSpendAllowance() public {
        uint256 amount = type(uint256).max;
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromDoesNotChangeFiniteOrInfiniteAllowance() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            assertTrue(token.approve(spender, approvals[i]));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroRecipientRejectionDoesNotDestroyInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersMatchSingleTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        Bankers single = new Bankers();
        assertTrue(single.transfer(alice, amount));
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, amount - first));
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedRoundTripReturnsTokensWithoutRestoringAllowance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function testFuzz_FailedSpendCanBeRetriedWithoutReapproval(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReapprovalReplacesRemainderAndPreservesOtherSpenders(uint256 first, uint256 spent, uint256 next)
        public
    {
        first = bound(first, 0, SUPPLY);
        spent = bound(spent, 0, first);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(bob, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.allowance(address(this), spender), first - spent);

        assertTrue(token.approve(spender, next));
        assertEq(token.allowance(address(this), spender), next);
        assertEq(token.allowance(address(this), bob), type(uint256).max);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferSpendsApprovalWithoutCreatingTokens(uint256 balance, uint256 approved)
        public
    {
        balance = bound(balance, 1, SUPPLY);
        approved = bound(approved, 1, balance);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, approved));
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, alice, 1);
    }
}
