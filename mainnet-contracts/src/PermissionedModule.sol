// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IDelegationManager, IDelegationManagerTypes } from "./interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { IEigenPodManager } from "./interface/Eigenlayer-Slashing/IEigenPodManager.sol";
import { ISignatureUtils } from "./interface/Eigenlayer-Slashing/ISignatureUtils.sol";
import { IStrategy } from "./interface/Eigenlayer-Slashing/IStrategy.sol";
import { IEigenPod, IEigenPodTypes } from "./interface/Eigenlayer-Slashing/IEigenPod.sol";
import { IRewardsCoordinator } from "./interface/Eigenlayer-Slashing/IRewardsCoordinator.sol";
import { IBeaconDepositContract } from "./interface/IBeaconDepositContract.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { IPermissionedModule } from "./interface/IPermissionedModule.sol";
import { PufferModuleManager } from "./PufferModuleManager.sol";
import { NonRestakingWithdrawalCredentials } from "./NonRestakingWithdrawalCredentials.sol";
import { Unauthorized } from "./Errors.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PermissionedModule
 * @author Puffer Finance
 * @notice Module that supports both restaked and non-restaked permissioned validators
 * @custom:security-contact security@puffer.fi
 */
contract PermissionedModule is Initializable, AccessManagedUpgradeable, IPermissionedModule {
    using Address for address;
    using Address for address payable;

    /**
     * @dev Represents the Beacon Chain strategy in EigenLayer
     */
    address internal constant _BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

    /**
     * @dev Storage struct for PermissionedModule
     * @custom:storage-location erc7201:PermissionedModule.storage
     */
    struct PermissionedModuleStorage {
        bytes32 moduleName;
        IEigenPod eigenPod;
        NonRestakingWithdrawalCredentials nonRestakingWithdrawalCredentials;
    }

    /**
     * keccak256(abi.encode(uint256(keccak256("PermissionedModule.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _PERMISSIONED_MODULE_STORAGE =
        0x7410446085c160ccc4c2b0e41801f8ac5004a5bf87d0402533c18d1e95927d00;

    IEigenPodManager public immutable EIGEN_POD_MANAGER;
    IRewardsCoordinator public immutable EIGEN_REWARDS_COORDINATOR;
    IDelegationManager public immutable EIGEN_DELEGATION_MANAGER;
    IBeaconDepositContract public immutable BEACON_DEPOSIT_CONTRACT;
    IPufferProtocol public immutable PUFFER_PROTOCOL;
    PufferModuleManager public immutable PUFFER_MODULE_MANAGER;

    constructor(
        IPufferProtocol protocol,
        address eigenPodManager,
        IDelegationManager delegationManager,
        PufferModuleManager moduleManager,
        IRewardsCoordinator rewardsCoordinator,
        IBeaconDepositContract beaconDepositContract
    ) payable {
        EIGEN_POD_MANAGER = IEigenPodManager(eigenPodManager);
        EIGEN_DELEGATION_MANAGER = delegationManager;
        PUFFER_PROTOCOL = protocol;
        PUFFER_MODULE_MANAGER = moduleManager;
        EIGEN_REWARDS_COORDINATOR = rewardsCoordinator;
        BEACON_DEPOSIT_CONTRACT = beaconDepositContract;
        _disableInitializers();
    }

    /**
     * @notice Initializes the module, creates EigenPod and NonRestakingWithdrawalCredentials
     * @param moduleName The name of this module
     * @param initialAuthority The access manager address
     */
    function initialize(bytes32 moduleName, address initialAuthority) external initializer {
        __AccessManaged_init(initialAuthority);
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        $.moduleName = moduleName;
        // Create EigenPod for restaked validators
        $.eigenPod = IEigenPod(address(EIGEN_POD_MANAGER.createPod()));
        // Deploy NonRestakingWithdrawalCredentials for non-restaked validators
        $.nonRestakingWithdrawalCredentials = new NonRestakingWithdrawalCredentials(address(this), initialAuthority);

        emit NonRestakingWithdrawalCredentialsSet(address($.nonRestakingWithdrawalCredentials));
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
     * @inheritdoc IPermissionedModule
     */
    function callStakeRestaked(bytes calldata pubKey, bytes calldata signature, bytes32 depositDataRoot)
        external
        payable
        onlyPufferProtocol
    {
        EIGEN_POD_MANAGER.stake{ value: 32 ether }(pubKey, signature, depositDataRoot);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function callStakeNonRestaked(
        bytes calldata pubKey,
        bytes calldata signature,
        bytes32 depositDataRoot,
        uint256 amount
    ) external payable onlyPufferProtocol {
        BEACON_DEPOSIT_CONTRACT.deposit{ value: amount }(
            pubKey, getNonRestakingWithdrawalCredentials(), signature, depositDataRoot
        );
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function setProofSubmitter(address proofSubmitter) external onlyPufferModuleManager {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        $.eigenPod.setProofSubmitter(proofSubmitter);
    }

    /**
     * @inheritdoc IPermissionedModule
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
     * @inheritdoc IPermissionedModule
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
     * @inheritdoc IPermissionedModule
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
     * @inheritdoc IPermissionedModule
     */
    function callDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external virtual onlyPufferModuleManager {
        EIGEN_DELEGATION_MANAGER.delegateTo(operator, approverSignatureAndExpiry, approverSalt);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function callUndelegate() external virtual onlyPufferModuleManager returns (bytes32[] memory withdrawalRoot) {
        return EIGEN_DELEGATION_MANAGER.undelegate(address(this));
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function triggerRestakedValidatorsExit(bytes[] calldata pubkeys) external payable virtual onlyPufferModuleManager {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();

        IEigenPodTypes.WithdrawalRequest[] memory requests = new IEigenPodTypes.WithdrawalRequest[](pubkeys.length);
        for (uint256 i = 0; i < pubkeys.length; i++) {
            requests[i] = IEigenPodTypes.WithdrawalRequest({
                pubkey: pubkeys[i],
                amountGwei: 0 // Full exit
             });
        }
        $.eigenPod.requestWithdrawal{ value: msg.value }(requests);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function withdrawNonRestakedETH() external onlyPufferModuleManager {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        $.nonRestakingWithdrawalCredentials.withdrawETH();
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function triggerNonRestakedValidatorWithdrawals(IEigenPodTypes.WithdrawalRequest[] calldata requests)
        external
        payable
        virtual
        onlyPufferModuleManager
    {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        $.nonRestakingWithdrawalCredentials.requestWithdrawal{ value: msg.value }(requests);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function callSetClaimerFor(address claimer) external virtual onlyPufferModuleManager {
        EIGEN_REWARDS_COORDINATOR.setClaimerFor(claimer);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function getRestakingWithdrawalCredentials() public view returns (bytes memory) {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), $.eigenPod);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function getNonRestakingWithdrawalCredentials() public view returns (bytes memory) {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        return abi.encodePacked(bytes1(uint8(2)), bytes11(0), $.nonRestakingWithdrawalCredentials);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function getEigenPod() external view returns (address) {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        return address($.eigenPod);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    function getNonRestakingWithdrawalCredentialsContract() external view returns (address) {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        return address($.nonRestakingWithdrawalCredentials);
    }

    /**
     * @inheritdoc IPermissionedModule
     */
    // solhint-disable-next-line func-name-mixedcase
    function NAME() external view returns (bytes32) {
        PermissionedModuleStorage storage $ = _getPermissionedModuleStorage();
        return $.moduleName;
    }

    function _getPermissionedModuleStorage() internal pure returns (PermissionedModuleStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _PERMISSIONED_MODULE_STORAGE
        }
    }
}
