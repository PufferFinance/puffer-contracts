// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { IEigenPodManager } from "eigenlayer/interfaces/IEigenPodManager.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { IStrategy } from "eigenlayer/interfaces/IStrategy.sol";
import { BeaconChainProofs } from "eigenlayer/libraries/BeaconChainProofs.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { IEigenPod } from "eigenlayer/interfaces/IEigenPod.sol";
import { IGuardianModule } from "./interface/IGuardianModule.sol";
import { IPufferModuleManager } from "./interface/IPufferModuleManager.sol";
import { IDelayedWithdrawalRouter } from "eigenlayer/interfaces/IDelayedWithdrawalRouter.sol";
import { IPufferModule } from "./interface/IPufferModule.sol";
import { Unauthorized } from "./Errors.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { LibGuardianMessages } from "./LibGuardianMessages.sol";
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
     */
    IEigenPodManager public immutable EIGEN_POD_MANAGER;

    /**
     * @dev Upgradeable contract from EigenLayer
     */
    IRewardsCoordinator public immutable EIGEN_REWARDS_COORDINATOR;

    /**
     * @dev Upgradeable contract from EigenLayer
     */
    IDelayedWithdrawalRouter public immutable EIGEN_WITHDRAWAL_ROUTER;

    /**
     * @dev Upgradeable contract from EigenLayer
     */
    IDelegationManager public immutable EIGEN_DELEGATION_MANAGER;

    /**
     * @dev Upgradeable PufferProtocol
     */
    IPufferProtocol public immutable PUFFER_PROTOCOL;

    /**
     * @dev Upgradeable Puffer Module Manager
     */
    IPufferModuleManager public immutable PUFFER_MODULE_MANAGER;

    // keccak256(abi.encode(uint256(keccak256("PufferModule.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PUFFER_MODULE_BASE_STORAGE =
        0x501caad7d5b9c1542c99d193b659cbf5c57571609bcfc93d65f1e159821d6200;

    constructor(
        IPufferProtocol protocol,
        address eigenPodManager,
        IDelayedWithdrawalRouter eigenWithdrawalRouter,
        IDelegationManager delegationManager,
        IPufferModuleManager moduleManager,
        IRewardsCoordinator rewardsCoordinator
    ) payable {
        EIGEN_POD_MANAGER = IEigenPodManager(eigenPodManager);
        EIGEN_WITHDRAWAL_ROUTER = eigenWithdrawalRouter;
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
    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    ) external virtual whenNotPaused onlyPufferModuleManager {
        ModuleStorage storage $ = _getPufferModuleStorage();

        $.eigenPod.verifyAndProcessWithdrawals({
            oracleTimestamp: oracleTimestamp,
            stateRootProof: stateRootProof,
            withdrawalProofs: withdrawalProofs,
            validatorFieldsProofs: validatorFieldsProofs,
            validatorFields: validatorFields,
            withdrawalFields: withdrawalFields
        });
    }

    /**
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external virtual onlyPufferModuleManager {
        ModuleStorage storage $ = _getPufferModuleStorage();

        $.eigenPod.verifyWithdrawalCredentials({
            oracleTimestamp: oracleTimestamp,
            stateRootProof: stateRootProof,
            validatorIndices: validatorIndices,
            withdrawalCredentialProofs: validatorFieldsProofs,
            validatorFields: validatorFields
        });
    }

    /**
     * @inheritdoc IPufferModule
     * @dev Restricted to PufferModuleManager
     */
    function withdrawNonBeaconChainETHBalanceWei(uint256 amountToWithdraw) external virtual onlyPufferModuleManager {
        ModuleStorage storage $ = _getPufferModuleStorage();

        $.eigenPod.withdrawNonBeaconChainETHBalanceWei(address(this), amountToWithdraw);
    }

    /**
     * @dev Restricted to PufferProtocol
     */
    function call(address to, uint256 amount, bytes calldata data)
        external
        onlyPufferProtocol
        returns (bool success, bytes memory)
    {
        // slither-disable-next-line arbitrary-send-eth
        return to.call{ value: amount }(data);
    }

    /**
     * @notice Submit a valid MerkleProof all their validators' staking rewards will be sent to node operator
     * @dev Anybody can trigger a claim of the rewards for any node operator as long as the proofs submitted are valid
     *
     * @param node is a node operator's wallet address
     * @param blockNumbers is the array of block numbers for which the sender is claiming the rewards
     * @param amounts is the array of amounts to claim
     * @param merkleProofs is the array of Merkle proofs
     */
    function collectRewards(
        address node,
        uint256[] calldata blockNumbers,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs
    ) external virtual whenNotPaused {
        ModuleStorage storage $ = _getPufferModuleStorage();

        // Anybody can submit a valid proof and the ETH will be sent to the node operator
        uint256 ethToSend = 0;

        for (uint256 i = 0; i < amounts.length; ++i) {
            if ($.claimedRewards[blockNumbers[i]][node]) {
                revert AlreadyClaimed(blockNumbers[i], node);
            }

            bytes32 rewardsRoot = $.rewardsRoots[blockNumbers[i]];
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(node, amounts[i]))));

            if (MerkleProof.verifyCalldata(merkleProofs[i], rewardsRoot, leaf)) {
                $.claimedRewards[blockNumbers[i]][node] = true;
                ethToSend += amounts[i];
            }
        }

        if (ethToSend == 0) {
            revert NothingToClaim(node);
        }

        payable(node).sendValue(ethToSend);
        emit RewardsClaimed(node, ethToSend);
    }

    /**
     * @notice Posts the rewards root for this module
     * @param root is the Merkle Root hash
     * @param blockNumber is the block number for when the Merkle Proof was generated
     */
    function postRewardsRoot(bytes32 root, uint256 blockNumber, bytes[] calldata guardianSignatures)
        external
        virtual
        whenNotPaused
    {
        ModuleStorage storage $ = _getPufferModuleStorage();

        if (blockNumber <= $.lastProofOfRewardsBlockNumber) {
            revert InvalidBlockNumber(blockNumber);
        }

        IGuardianModule guardianModule = PUFFER_PROTOCOL.GUARDIAN_MODULE();

        bytes32 signedMessageHash = LibGuardianMessages._getModuleRewardsRootMessage($.moduleName, root, blockNumber);

        bool validSignatures = guardianModule.validateGuardiansEOASignatures(guardianSignatures, signedMessageHash);
        if (!validSignatures) {
            revert Unauthorized();
        }

        $.lastProofOfRewardsBlockNumber = blockNumber;
        $.rewardsRoots[blockNumber] = root;
        emit RewardsRootPosted(blockNumber, root);
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
     * @notice Returns the block number of when the latest rewards proof was posted
     */
    function getLastProofOfRewardsBlock() external view returns (uint256) {
        ModuleStorage storage $ = _getPufferModuleStorage();
        return $.lastProofOfRewardsBlockNumber;
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
