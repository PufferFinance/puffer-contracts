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
     * @notice Event emitted when a validator is requested to be switched to compounding withdrawal credentials
     * @param pubkey The public key of the validator
     */
    event SwitchToCompoundingWithdrawalCredentials(bytes pubkey);

    /**
     * @notice Event emitted when a withdrawal request is made
     * @param pubkey The public key of the validator
     * @param amountGwei The amount of ETH to withdraw (in Gwei)
     */
    event WithdrawalRequested(bytes pubkey, uint256 indexed amountGwei);

    /**
     * @notice Event emitted when a consolidation request is made
     * @param srcPubkey The public key of the source validator
     * @param targetPubkey The public key of the target validator
     */
    event ConsolidationRequested(bytes srcPubkey, bytes targetPubkey);

    /**
     * @notice Thrown if the sender did not send enough ETH to cover the fee
     */
    error NotEnoughETH();

    /**
     * @notice Thrown if the withdrawal request fails
     */
    error WithdrawalRequestFailed();

    /**
     * @notice Thrown if the consolidation request fails
     */
    error ConsolidationRequestFailed();

    /**
     * @notice Thrown if the fee query fails
     */
    error FeeQueryFailed();

    // https://eips.ethereum.org/EIPS/eip-7002
    address internal constant WITHDRAWAL_REQUEST_ADDRESS = 0x00000961Ef480Eb55e80D19ad83579A64c007002;
    // https://eips.ethereum.org/EIPS/eip-7251
    address internal constant CONSOLIDATION_REQUEST_ADDRESS = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;

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
     * @notice Request consolidation of validators via EIP-7251
     * It is possible to consolidate a validator to itself, which will switch the withdrawal credentials to compounding withdrawal credentials (0x01 -> 0x02)
     * It is also possible to consolidate a validator from this withdrawal credentials to another withdrawal credentials
     * @dev We do not validate if the source validator belongs to this contract
     * @param requests The requests to consolidate
     */
    function requestConsolidation(IEigenPodTypes.ConsolidationRequest[] calldata requests)
        external
        payable
        restricted
    {
        uint256 fee = getConsolidationRequestFee();
        // The remainder is donated and not refunded to the caller
        if (msg.value < fee * requests.length) {
            revert NotEnoughETH();
        }

        for (uint256 i = 0; i < requests.length; ++i) {
            IEigenPodTypes.ConsolidationRequest calldata request = requests[i];
            // We don't need to validate the length of the pubkeys as the precompile will revert if the pubkeys are invalid
            // The precompile just checks for the keys length, it doesn't check if it is an active validator

            bytes memory callData = bytes.concat(request.srcPubkey, request.targetPubkey);
            (bool ok,) = CONSOLIDATION_REQUEST_ADDRESS.call{ value: fee }(callData);
            if (!ok) {
                revert ConsolidationRequestFailed();
            }

            // Emit event depending on whether this is a switch to 0x02, or a regular consolidation
            if (keccak256(request.srcPubkey) == keccak256(request.targetPubkey)) {
                emit SwitchToCompoundingWithdrawalCredentials(request.srcPubkey);
            } else {
                emit ConsolidationRequested(request.srcPubkey, request.targetPubkey);
            }
        }
    }

    /**
     * @notice Get the fee for a consolidation request
     * @return The fee for a consolidation request
     */
    function getConsolidationRequestFee() public view returns (uint256) {
        return _getFee(CONSOLIDATION_REQUEST_ADDRESS);
    }

    /**
     * @notice Get the fee for a withdrawal request
     * @return The fee for a withdrawal request
     */
    function getWithdrawalRequestFee() public view returns (uint256) {
        return _getFee(WITHDRAWAL_REQUEST_ADDRESS);
    }

    /**
     * @notice Get the fee for a request
     * @param predeploy The address of the predeploy
     * @return The fee for a request
     */
    function _getFee(address predeploy) internal view returns (uint256) {
        (bool success, bytes memory result) = predeploy.staticcall("");
        if (!success || result.length != 32) {
            revert FeeQueryFailed();
        }
        return uint256(bytes32(result));
    }
}
