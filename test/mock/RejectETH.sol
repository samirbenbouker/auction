// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title RejectETH
/// @notice Utility contract that always rejects incoming ETH transfers.
/// @dev
/// - Reverts on any ETH sent via `receive()`.
/// - Commonly used in tests to simulate:
///   • Failing ETH transfers
///   • Malicious or incompatible receivers
///   • DoS scenarios caused by push-based payments
///
/// This contract is especially useful for validating that a protocol
/// correctly uses the pull-payment pattern (`withdraw`) instead of
/// sending ETH directly during state-changing operations.
contract RejectETH {
    /// @notice Rejects any plain ETH transfer.
    /// @dev
    /// - Triggered when ETH is sent with empty calldata.
    /// - Always reverts, preventing ETH from being received.
    receive() external payable {
        revert("I reject ETH");
    }
}
