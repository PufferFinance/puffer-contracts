// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IEigenPodTypes } from "./interface/Eigenlayer-Slashing/IEigenPod.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Unauthorized } from "./Errors.sol";

/**
 * @title NonRestakingWithdrawalCredentials
 * @author Puffer Finance
 * @notice Non-restaked validators should point the withdrawal credentials to this contract
 * @custom:security-contact security@puffer.fi
 */
contract NonRestakingWithdrawalCredentials is AccessManaged {
    using Address for address payable;

    /**
     * @notice Event emitted when a withdrawal request is made
     * @param pubkey The public key of the validator
     * @param amountGwei The amount of ETH to withdraw (in Gwei)
     */
    event WithdrawalRequested(bytes pubkey, uint256 indexed amountGwei);

    /**
     * @notice Thrown if the sender did not send enough ETH to cover the fee
     */
    error NotEnoughETH();

    /**
     * @notice Thrown if the withdrawal request fails
     */
    error WithdrawalRequestFailed();

    /**
     * @notice Thrown if the fee query fails
     */
    error FeeQueryFailed();

    // https://eips.ethereum.org/EIPS/eip-7002
    address internal constant WITHDRAWAL_REQUEST_ADDRESS = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    /**
     * @notice The address of the PermissionedModule that owns this contract
     */
    address public immutable PERMISSIONED_MODULE;

    constructor(address permissionedModule, address accessManager) AccessManaged(accessManager) {
        PERMISSIONED_MODULE = permissionedModule;
    }

    /**
     * @notice Allow contract to receive ETH from Beacon Chain withdrawals
     */
    receive() external payable { }

    /**
     * @notice Withdraw accumulated ETH to the PermissionedModule
     * @dev Only callable by the PermissionedModule
     */
    function withdrawETH() external {
        if (msg.sender != PERMISSIONED_MODULE) {
            revert Unauthorized();
        }
        payable(PERMISSIONED_MODULE).sendValue(address(this).balance);
    }

    /**
     * @notice Request a withdrawal of validators via EIP-7002
     * @param requests The requests to withdraw
     * @dev Restricted to authorized callers via AccessManager
     */
    function requestWithdrawal(IEigenPodTypes.WithdrawalRequest[] calldata requests) external payable restricted {
        uint256 fee = getWithdrawalRequestFee();
        // The remainder is donated and not refunded to the caller
        if (msg.value < fee * requests.length) {
            revert NotEnoughETH();
        }

        for (uint256 i = 0; i < requests.length; ++i) {
            // We don't need to validate the length of the pubkeys as the precompile will revert if the pubkeys are of invalid length
            bytes memory callData = abi.encodePacked(requests[i].pubkey, requests[i].amountGwei);
            (bool ok,) = WITHDRAWAL_REQUEST_ADDRESS.call{ value: fee }(callData);
            if (!ok) {
                revert WithdrawalRequestFailed();
            }
            emit WithdrawalRequested(requests[i].pubkey, requests[i].amountGwei);
        }
    }

    /**
     * @notice Get the fee for a withdrawal request
     * @return The fee for a withdrawal request
     */
    function getWithdrawalRequestFee() public view returns (uint256) {
        (bool success, bytes memory result) = WITHDRAWAL_REQUEST_ADDRESS.staticcall("");
        if (!success || result.length != 32) {
            revert FeeQueryFailed();
        }
        return uint256(bytes32(result));
    }
}
