// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { IEigenPodManager } from "eigenlayer/interfaces/IEigenPodManager.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { IStrategy } from "eigenlayer/interfaces/IStrategy.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { IEigenPod } from "eigenlayer/interfaces/IEigenPod.sol";
import { IPufferModuleManager } from "./interface/IPufferModuleManager.sol";
import { IPufferModule } from "./interface/IPufferModule.sol";
import { Unauthorized } from "./Errors.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ModuleStorage } from "./struct/ModuleStorage.sol";
import { IRewardsCoordinator } from "./interface/EigenLayer/IRewardsCoordinator.sol";

/**
 * @title PufferModule
 * @author Puffer Finance
 * @notice PufferModule
 * @custom:security-contact security@puffer.fi
 */
contract PufferModule is IPufferModule, Initializable, AccessManagedUpgradeable {
    using Address for address;
    using Address for address payable;

    /**
     * @dev Represents the Beacon Chain strategy in EigenLayer
     */
    address internal constant _BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

    /**
     * @dev Upgradeable contract from EigenLayer
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IEigenPodManager public immutable EIGEN_POD_MANAGER;

    /**
     * @dev Upgradeable contract from EigenLayer
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IRewardsCoordinator public immutable EIGEN_REWARDS_COORDINATOR;

    /**
     * @dev Upgradeable contract from EigenLayer
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IDelegationManager public immutable EIGEN_DELEGATION_MANAGER;

    /**
     * @dev Upgradeable PufferProtocol
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IPufferProtocol public immutable PUFFER_PROTOCOL;

    /**
     * @dev Upgradeable Puffer Module Manager
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IPufferModuleManager public immutable PUFFER_MODULE_MANAGER;

    /**
     * keccak256(abi.encode(uint256(keccak256("PufferModule.storage")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _PUFFER_MODULE_BASE_STORAGE =
        0x501caad7d5b9c1542c99d193b659cbf5c57571609bcfc93d65f1e159821d6200;

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(
        IPufferProtocol protocol,
        address eigenPodManager,
        IDelegationManager delegationManager,
        IPufferModuleManager moduleManager,
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
     * @inheritdoc IPufferModule
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
     * @inheritdoc IPufferModule
     */
    function setProofSubmitter(address proofSubmitter) external onlyPufferModuleManager {
        ModuleStorage storage $ = _getPufferModuleStorage();

        $.eigenPod.setProofSubmitter(proofSubmitter);
    }

    /**
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function queueWithdrawals(uint256 shareAmount)
        external
        virtual
        onlyPufferModuleManager
        returns (bytes32[] memory)
    {
        IDelegationManager.QueuedWithdrawalParams[] memory withdrawals =
            new IDelegationManager.QueuedWithdrawalParams[](1);

        uint256[] memory shares = new uint256[](1);
        shares[0] = shareAmount;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(_BEACON_CHAIN_STRATEGY);

        withdrawals[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: shares,
            withdrawer: address(this)
        });

        return EIGEN_DELEGATION_MANAGER.queueWithdrawals(withdrawals);
    }

    /**
     * @inheritdoc IPufferModule
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external virtual whenNotPaused onlyPufferModuleManager {
        EIGEN_DELEGATION_MANAGER.completeQueuedWithdrawals({
            withdrawals: withdrawals,
            tokens: tokens,
            middlewareTimesIndexes: middlewareTimesIndexes,
            receiveAsTokens: receiveAsTokens
        });
    }

    /**
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function startCheckpoint() external virtual onlyPufferModuleManager {
        ModuleStorage storage $ = _getPufferModuleStorage();
        $.eigenPod.startCheckpoint({ revertIfNoBalance: true });
    }

    /**
     * @dev Restricted to PufferProtocol
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
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function callDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external virtual onlyPufferModuleManager {
        EIGEN_DELEGATION_MANAGER.delegateTo(operator, approverSignatureAndExpiry, approverSalt);
    }

    /**
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function callUndelegate() external virtual onlyPufferModuleManager returns (bytes32[] memory withdrawalRoot) {
        return EIGEN_DELEGATION_MANAGER.undelegate(address(this));
    }

    /**
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function callSetClaimerFor(address claimer) external virtual onlyPufferModuleManager {
        EIGEN_REWARDS_COORDINATOR.setClaimerFor(claimer);
    }

    /**
     * @inheritdoc IPufferModule
     */
    function getWithdrawalCredentials() public view returns (bytes memory) {
        // Withdrawal credentials for EigenLayer modules are EigenPods
        ModuleStorage storage $ = _getPufferModuleStorage();
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), $.eigenPod);
    }

    /**
     * @inheritdoc IPufferModule
     */
    function getEigenPod() external view returns (address) {
        ModuleStorage storage $ = _getPufferModuleStorage();
        return address($.eigenPod);
    }

    /**
     * @inheritdoc IPufferModule
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
