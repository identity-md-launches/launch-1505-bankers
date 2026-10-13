// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Bankers} from "../src/Bankers.sol";

/// @dev All transfers stay within this closed set of actors, so balance conservation is measurable.
contract BankersHandler is Test {
    Bankers public immutable token;
    address[4] internal actors;
    uint256 public immutable initialBalance;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Bankers token_, address[4] memory actors_, uint256 initialBalance_) {
        token = token_;
        actors = actors_;
        // Seed the accounting from the fixture's promised allocation, never from token getters.
        initialBalance = initialBalance_;
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return initialBalance + received[actor] - sent[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(from));
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 available = expectedBalance(from);
        amount = bound(amount, 0, approved < available ? approved : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        _recordTransfer(from, to, amount);
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(token.allowance(from, spender), approved == type(uint256).max ? approved : approved - amount);
    }

    /// @dev Explicitly reach revocation, dust, exact balance, and both sides of the infinity sentinel.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, expectedBalance(owner), type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[mode % amounts.length]);
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        transfer(fromSeed, toSeed, expectedBalance(actors[fromSeed % actors.length]));
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, expectedBalance(from));
        transfer(fromSeed, toSeed, amount);
        transfer(toSeed, fromSeed, amount);
        assertEq(token.balanceOf(from), beforeFrom, "round trip changed sender wealth");
        assertEq(token.balanceOf(to), beforeTo, "round trip changed recipient wealth");
    }

    // Rejected calls must also be interleaved with successful calls. Ghosts remain unchanged
    // after rejection, so the invariants check every actor and approval for unintended changes.
    function rejectOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectOverAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 approved) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        approved = bound(approved, 0, expectedBalance(from));
        _approve(from, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, approved + 1);
    }

    function rejectTransferFromOverBalance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(from, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(from));
        if (delegated) _approve(from, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : from);
        if (delegated) token.transferFrom(from, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract BankersInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Bankers internal token;
    BankersHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new Bankers();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("actor-", vm.toString(i)));
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        handler = new BankersHandler(token, actors, SUPPLY / actors.length);
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = BankersHandler.transfer.selector;
        selectors[1] = BankersHandler.approve.selector;
        selectors[2] = BankersHandler.transferFrom.selector;
        selectors[3] = BankersHandler.approveBoundary.selector;
        selectors[4] = BankersHandler.transferAll.selector;
        selectors[5] = BankersHandler.roundTrip.selector;
        selectors[6] = BankersHandler.rejectOverBalance.selector;
        selectors[7] = BankersHandler.rejectOverAllowance.selector;
        selectors[8] = BankersHandler.rejectTransferFromOverBalance.selector;
        selectors[9] = BankersHandler.rejectZeroRecipient.selector;
        selectors[10] = BankersHandler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TotalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.name(), "Bankers");
        assertEq(token.symbol(), "BANKERS");
        assertEq(token.decimals(), 18);
    }

    function invariant_BalancesConserveEntireSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertLe(balance, SUPPLY);
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_EachBalanceMatchesTransferHistory() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "unexpected balance change");
        }
    }

    function invariant_AllAllowancesMatchOwnerInstructions() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            assertEq(token.allowance(actors[i], address(this)), 0, "deployer received an approval");
            assertEq(token.allowance(actors[i], address(handler)), 0, "handler received an approval");
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "unexpected allowance change"
                );
            }
        }
    }
}
