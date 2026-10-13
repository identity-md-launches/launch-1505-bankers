// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bankers
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract Bankers is ERC20 {
    /// @notice The entire supply, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the full supply once to the direct deployer (the factory at launch).
    constructor() ERC20("Bankers", "BANKERS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
