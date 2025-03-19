// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { InvalidAddress, Unauthorized, InvalidInput } from "./Errors.sol";
import { IBeaconDepositContract } from "./interface/IBeaconDepositContract.sol";
import { PufferProtocol } from "./PufferProtocol.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { IPufferNoRestakingValidator } from "./interface/IPufferNoRestakingValidator.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title PufferNoRestakingValidator
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferNoRestakingValidator is IPufferNoRestakingValidator, AccessManaged {
    using Address for address payable;

    address public immutable BEACON_DEPOSIT_CONTRACT;
    address public immutable WITHDRAWAL_REQUEST_PREDEPLOY;

    PufferProtocol public immutable PUFFER_PROTOCOL;

    /**
     * The amount of ETH deposited to the Beacon Chain through this contract
     */
    uint256 public depositedToBeaconChain;

    /**
     * The amount of ETH queued for withdrawal from the Beacon Chain through this contract
     */
    uint256 public queuedWithdrawals;

    constructor(
        address protocol,
        address accessManager,
        address beaconDepositContract,
        address withdrawalRequestPredeploy
    ) AccessManaged(accessManager) {
        require(protocol != address(0), InvalidAddress());
        require(beaconDepositContract != address(0), InvalidAddress());
        require(withdrawalRequestPredeploy != address(0), InvalidAddress());
        PUFFER_PROTOCOL = PufferProtocol(payable(protocol));
        BEACON_DEPOSIT_CONTRACT = beaconDepositContract;
        WITHDRAWAL_REQUEST_PREDEPLOY = withdrawalRequestPredeploy;
    }

    modifier onlyPufferProtocol() {
        require(msg.sender == address(PUFFER_PROTOCOL), Unauthorized());
        _;
    }

    /**
     * @notice Receive function to allow the contract to receive ETH
     */
    receive() external payable { }

    /**
     * @notice Start non restaking compounding validator
     * @param pubKey The public key of the validator
     * @param signature The signature of the validator
     * @param depositDataRoot The deposit data root of the validator
     */
    function startNonRestakingValidators(bytes calldata pubKey, bytes calldata signature, bytes32 depositDataRoot)
        external
        payable
        onlyPufferProtocol
    {
        IBeaconDepositContract(BEACON_DEPOSIT_CONTRACT).deposit{ value: msg.value }({
            pubkey: pubKey,
            withdrawal_credentials: getWithdrawalCredentialsCompounding(),
            signature: signature,
            deposit_data_root: depositDataRoot
        });

        depositedToBeaconChain += msg.value;

        emit ValidatorDeposited(pubKey, msg.value);
    }

    /**
     * @notice Creates withdrawal requests for 0x02 validators
     * @param pubkeys The public keys of the validators
     * @param withdrawalAmounts The amounts of ETH to withdraw (in gwei) 0 = validator exit
     * @dev Restricted to Puffer Paymaster
     */
    function createWithdrawalRequest(bytes[] calldata pubkeys, uint256[] calldata withdrawalAmounts)
        external
        payable
        restricted
    {
        require(pubkeys.length == withdrawalAmounts.length, InvalidInput());
        require(pubkeys.length > 0, InvalidInput());

        // Ensure withdrawalAmount is in gwei (1 gwei = 10^9 wei)
        for (uint256 i = 0; i < withdrawalAmounts.length; i++) {
            if (withdrawalAmounts[i] % 1 gwei != 0) {
                revert WithdrawalAmountNotInGwei();
            }
        }

        // Read the withdrawal fee from the withdrawal request predeploy
        (bool feeReadOk, bytes memory feeData) = WITHDRAWAL_REQUEST_PREDEPLOY.staticcall("");
        require(feeReadOk, FailedToReadWithdrawalFee());

        // Create the withdrawal request
        for (uint256 i = 0; i < pubkeys.length; i++) {
            (bool withdrawalRequestOk,) = WITHDRAWAL_REQUEST_PREDEPLOY.call{
                value: uint256(bytes32(feeData)) * pubkeys.length
            }(abi.encodePacked(pubkeys[i], withdrawalAmounts[i]));
            require(withdrawalRequestOk, FailedToCreateWithdrawalRequest());
            // Convert from gwei to wei (1 gwei = 10^9 wei)
            queuedWithdrawals += withdrawalAmounts[i] * 1 gwei;

            emit WithdrawalRequested(pubkeys[i], withdrawalAmounts[i]);
        }
    }

    /**
     * @notice Exit the validators and send the ETH to the Puffer Vault
     * @param amount The amount of ETH to return to the Puffer Vault
     */
    function exitValidators(uint256 amount) external onlyPufferProtocol {
        queuedWithdrawals -= amount;
        payable(PUFFER_PROTOCOL.PUFFER_VAULT()).sendValue(amount);
    }

    /**
     * @notice Transfer ETH to an address
     * This function is used to transfer the earned rewards from this contract
     * restricted to Puffer Team
     * @param to The address to transfer the ETH to
     * @param amount The amount of ETH to transfer
     */
    function transferETH(address payable to, uint256 amount) external restricted {
        // Only allow transfers of the Rewards to `to` address
        require(amount > (address(this).balance - queuedWithdrawals), InvalidAmount());
        payable(to).sendValue(amount);
    }

    /**
     * @notice Get the withdrawal credentials for the compounding validators (this contract address)
     * @return The withdrawal credentials
     */
    function getWithdrawalCredentialsCompounding() public view returns (bytes memory) {
        return abi.encodePacked(bytes1(uint8(2)), bytes11(0), address(this));
    }
}
