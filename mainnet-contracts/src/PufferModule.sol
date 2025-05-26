// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IDelegationManager } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IEigenPodManager } from "../src/interface/Eigenlayer-Slashing/IEigenPodManager.sol";
import { ISignatureUtils } from "../src/interface/Eigenlayer-Slashing/ISignatureUtils.sol";
import { IStrategy } from "../src/interface/Eigenlayer-Slashing/IStrategy.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { IEigenPod, IEigenPodTypes } from "../src/interface/Eigenlayer-Slashing/IEigenPod.sol";
import { PufferModuleManager } from "./PufferModuleManager.sol";
import { Unauthorized } from "./Errors.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ModuleStorage } from "./struct/ModuleStorage.sol";
import { IDelegationManagerTypes } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IRewardsCoordinator } from "../src/interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";

/**
 * @title PufferModule
 * @author Puffer Finance
 * @notice PufferModule
 * @custom:security-contact security@puffer.fi
 */
contract PufferModule is Initializable, AccessManagedUpgradeable {
    using Address for address;
    using Address for address payable;

    IEigenPodManager public immutable EIGEN_POD_MANAGER;
    IRewardsCoordinator public immutable EIGEN_REWARDS_COORDINATOR;
    IDelegationManager public immutable EIGEN_DELEGATION_MANAGER;
    IPufferProtocol public immutable PUFFER_PROTOCOL;
    PufferModuleManager public immutable PUFFER_MODULE_MANAGER;
    /**
     * @dev Represents the Beacon Chain strategy in EigenLayer
     */
    address internal constant _BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
    /**
     * keccak256(abi.encode(uint256(keccak256("PufferModule.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _PUFFER_MODULE_BASE_STORAGE =
        0x501caad7d5b9c1542c99d193b659cbf5c57571609bcfc93d65f1e159821d6200;

    constructor(
        IPufferProtocol protocol,
        address eigenPodManager,
        IDelegationManager delegationManager,
        PufferModuleManager moduleManager,
        IRewardsCoordinator rewardsCoordinator
    ) payable {
        EIGEN_POD_MANAGER = IEigenPodManager(eigenPodManager);
        EIGEN_DELEGATION_MANAGER = delegationManager;
        PUFFER_PROTOCOL = protocol;
        PUFFER_MODULE_MANAGER = moduleManager;
        EIGEN_REWARDS_COORDINATOR = rewardsCoordinator;
        _disableInitializers();
    }

    function initialize(bytes32 moduleName, address initialAuthority) external initializer {
        __AccessManaged_init(initialAuthority);
        ModuleStorage storage $ = _getPufferModuleStorage();
        $.moduleName = moduleName;
        $.eigenPod = IEigenPod(address(EIGEN_POD_MANAGER.createPod()));
    }

    /**
     * @dev Calls PufferProtocol to check if it is paused
     */
    modifier whenNotPaused() {
        PUFFER_PROTOCOL.revertIfPaused();
        _;
    }

    modifier onlyPufferProtocol() {
        if (msg.sender != address(PUFFER_PROTOCOL)) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyPufferModuleManager() {
        if (msg.sender != address(PUFFER_MODULE_MANAGER)) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyPufferProtocolOrPufferModuleManager() {
        if (msg.sender != address(PUFFER_MODULE_MANAGER) && msg.sender != address(PUFFER_PROTOCOL)) {
            revert Unauthorized();
        }
        _;
    }

    receive() external payable { }

    /**
     * @notice Starts the validator
     */
    function callStake(bytes calldata pubKey, bytes calldata signature, bytes32 depositDataRoot)
        external
        payable
        onlyPufferProtocol
    {
        // EigenPod is deployed in this call
        EIGEN_POD_MANAGER.stake{ value: 32 ether }(pubKey, signature, depositDataRoot);
    }

    /**
     * @notice Sets the proof submitter on the EigenPod
     */
    function setProofSubmitter(address proofSubmitter) external onlyPufferModuleManager {
        ModuleStorage storage $ = _getPufferModuleStorage();

        $.eigenPod.setProofSubmitter(proofSubmitter);
    }

    /**
     * @notice Queues the withdrawal from EigenLayer for the Beacon Chain strategy
     */
    function queueWithdrawals(uint256 shareAmount)
        external
        virtual
        onlyPufferModuleManager
        returns (bytes32[] memory)
    {
        IDelegationManagerTypes.QueuedWithdrawalParams[] memory withdrawals =
            new IDelegationManagerTypes.QueuedWithdrawalParams[](1);

        uint256[] memory shares = new uint256[](1);
        shares[0] = shareAmount;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(_BEACON_CHAIN_STRATEGY);

        withdrawals[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: strategies,
            depositShares: shares,
            withdrawer: address(this)
        });

        return EIGEN_DELEGATION_MANAGER.queueWithdrawals(withdrawals);
    }

    /**
     * @notice Completes the queued withdrawals
     */
    function completeQueuedWithdrawals(
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external virtual whenNotPaused onlyPufferModuleManager {
        EIGEN_DELEGATION_MANAGER.completeQueuedWithdrawals({
            withdrawals: withdrawals,
            tokens: tokens,
            receiveAsTokens: receiveAsTokens
        });
    }

    /**
     * @notice the `to` with custom `value` and `data`
     * @return success the success of the call
     * @return returnData the return data of the call
     */
    function call(address to, uint256 amount, bytes calldata data)
        external
        onlyPufferProtocolOrPufferModuleManager
        returns (bool success, bytes memory)
    {
        // slither-disable-next-line arbitrary-send-eth
        // nosemgrep arbitrary-low-level-call
        return to.call{ value: amount }(data);
    }

    /**
     * @notice Calls the delegateTo function on the EigenLayer delegation manager
     * @param operator is the address of the restaking operator
     * @param approverSignatureAndExpiry the signature of the delegation approver
     * @param approverSalt salt for the signature
     */
    function callDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external virtual onlyPufferModuleManager {
        EIGEN_DELEGATION_MANAGER.delegateTo(operator, approverSignatureAndExpiry, approverSalt);
    }

    /**
     * @notice Calls the undelegate function on the EigenLayer delegation manager
     */
    function callUndelegate() external virtual onlyPufferModuleManager returns (bytes32[] memory withdrawalRoot) {
        return EIGEN_DELEGATION_MANAGER.undelegate(address(this));
    }

    /**
     * @notice Requests a withdrawal for the given validators. This withdrawal can be total or partial.
     *         If the amount is 0, the withdrawal is total and the validator will be fully exited.
     *         If it is a partial withdrawal, the validator should not be below 32 ETH or the request will be ignored.
     * @param pubkeys The pubkeys of the validators to exit
     * @param gweiAmounts The amounts of the validators to exit, in Gwei
     * @dev Only callable by the PufferModuleManager
     * @dev According to EIP-7002 there is a fee for each validator exit request (See https://eips.ethereum.org/assets/eip-7002/fee_analysis)
     *      The fee is paid in the msg.value of this function. Since the fee is not fixed and might change, the excess amount is refunded
     *      to the caller from the EigenPod
     */
    function requestWithdrawal(bytes[] calldata pubkeys, uint64[] calldata gweiAmounts)
        external
        payable
        virtual
        onlyPufferModuleManager
    {
        ModuleStorage storage $ = _getPufferModuleStorage();

        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](pubkeys.length);
        for (uint256 i = 0; i < pubkeys.length; i++) {
            requests[i] = IEigenPodTypes.WithdrawalRequest({ pubkey: pubkeys[i], amountGwei: gweiAmounts[i] });
        }
        uint256 oldBalance = address(this).balance - msg.value;
        $.eigenPod.requestWithdrawal{ value: msg.value }(requests);
        uint256 excessAmount = address(this).balance - oldBalance;
        if (excessAmount > 0) {
            Address.sendValue(payable(PUFFER_MODULE_MANAGER), excessAmount);
        }
    }

    /**
     * @notice Sets the rewards claimer to `claimer` for the PufferModule
     */
    function callSetClaimerFor(address claimer) external virtual onlyPufferModuleManager {
        EIGEN_REWARDS_COORDINATOR.setClaimerFor(claimer);
    }

    /**
     * @notice Returns the Withdrawal credentials for that module
     */
    function getWithdrawalCredentials() public view returns (bytes memory) {
        // Withdrawal credentials for EigenLayer modules are EigenPods
        ModuleStorage storage $ = _getPufferModuleStorage();
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), $.eigenPod);
    }

    /**
     * @notice Returns the EigenPod address owned by the module
     */
    function getEigenPod() external view returns (address) {
        ModuleStorage storage $ = _getPufferModuleStorage();
        return address($.eigenPod);
    }

    /**
     * @notice Returns the module name
     */
    // solhint-disable-next-line func-name-mixedcase
    function NAME() external view returns (bytes32) {
        ModuleStorage storage $ = _getPufferModuleStorage();
        return $.moduleName;
    }

    function _getPufferModuleStorage() internal pure returns (ModuleStorage storage $) {
        // solhint-disable-next-line
        assembly {
            $.slot := _PUFFER_MODULE_BASE_STORAGE
        }
    }
}
