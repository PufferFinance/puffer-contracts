// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferModule } from "./interface/IPufferModule.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { Unauthorized, InvalidAmount } from "./Errors.sol";
import { IRestakingOperator } from "./interface/IRestakingOperator.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { PufferModule } from "./PufferModule.sol";
import { PufferVaultV3 } from "./PufferVaultV3.sol";
import { RestakingOperator } from "./RestakingOperator.sol";
import { IPufferModuleManager } from "./interface/IPufferModuleManager.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IDelegationManager } from "eigenlayer/interfaces/IDelegationManager.sol";
import { ISignatureUtils } from "eigenlayer/interfaces/ISignatureUtils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRegistryCoordinator, IBLSApkRegistry } from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import { AVSContractsRegistry } from "./AVSContractsRegistry.sol";

/**
 * @title PufferModuleManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferModuleManager is IPufferModuleManager, AccessManagedUpgradeable, UUPSUpgradeable {
    /**
     * @inheritdoc IPufferModuleManager
     */
    address public immutable override PUFFER_MODULE_BEACON;

    /**
     * @inheritdoc IPufferModuleManager
     */
    address public immutable override RESTAKING_OPERATOR_BEACON;

    /**
     * @inheritdoc IPufferModuleManager
     */
    address public immutable override PUFFER_PROTOCOL;

    /**
     * @inheritdoc IPufferModuleManager
     */
    address payable public immutable override PUFFER_VAULT;

    /**
     * @dev AVS contracts registry
     */
    AVSContractsRegistry public immutable AVS_CONTRACTS_REGISTRY;

    modifier onlyPufferProtocol() {
        if (msg.sender != PUFFER_PROTOCOL) {
            revert Unauthorized();
        }
        _;
    }

    constructor(
        address pufferModuleBeacon,
        address restakingOperatorBeacon,
        address pufferProtocol,
        AVSContractsRegistry avsContractsRegistry
    ) {
        PUFFER_MODULE_BEACON = pufferModuleBeacon;
        RESTAKING_OPERATOR_BEACON = restakingOperatorBeacon;
        PUFFER_PROTOCOL = pufferProtocol;
        PUFFER_VAULT = payable(address(IPufferProtocol(PUFFER_PROTOCOL).PUFFER_VAULT()));
        AVS_CONTRACTS_REGISTRY = avsContractsRegistry;
        _disableInitializers();
    }

    receive() external payable { }

    /**
     * @notice Initializes the contract
     */
    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
    }

    /**
     * @notice Completes queued withdrawals
     * @dev Restricted to Puffer Paymaster
     */
    function callCompleteQueuedWithdrawals(
        bytes32 moduleName,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        IPufferModule(moduleAddress).completeQueuedWithdrawals({
            withdrawals: withdrawals,
            tokens: tokens,
            middlewareTimesIndexes: middlewareTimesIndexes,
            receiveAsTokens: receiveAsTokens
        });

        uint256 sharesWithdrawn;

        for (uint256 i = 0; i < withdrawals.length; ++i) {
            // nosemgrep array-length-outside-loop
            for (uint256 j = 0; j < withdrawals[i].shares.length; ++j) {
                sharesWithdrawn += withdrawals[i].shares[j];
            }
        }

        emit CompletedQueuedWithdrawals(moduleName, sharesWithdrawn);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the PufferProtocol
     * @param moduleName The name of the module
     */
    function createNewPufferModule(bytes32 moduleName) external virtual onlyPufferProtocol returns (IPufferModule) {
        if (moduleName == bytes32("NO_VALIDATORS")) {
            revert ForbiddenModuleName();
        }
        // This called from the PufferProtocol and the event is emitted there
        return IPufferModule(
            Create2.deploy({
                amount: 0,
                salt: moduleName,
                bytecode: abi.encodePacked(
                    type(BeaconProxy).creationCode,
                    abi.encode(PUFFER_MODULE_BEACON, abi.encodeCall(PufferModule.initialize, (moduleName, authority())))
                )
            })
        );
    }

    /**
     * @notice Transfers the unlocked rewards from the modules to the vault
     * @dev Restricted to Puffer Paymaster
     */
    function transferRewardsToTheVault(address[] calldata modules, uint256[] calldata rewardsAmounts)
        external
        virtual
        restricted
    {
        uint256 totalRewardsAmount;

        for (uint256 i = 0; i < modules.length; ++i) {
            //solhint-disable-next-line avoid-low-level-calls
            (bool success,) = IPufferModule(modules[i]).call(address(this), rewardsAmounts[i], "");
            if (!success) {
                revert InvalidAmount();
            }
            totalRewardsAmount += rewardsAmounts[i];
        }

        PufferVaultV3(PUFFER_VAULT).depositRewards{ value: totalRewardsAmount }();
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to Puffer Paymaster
     */
    function callQueueWithdrawals(bytes32 moduleName, uint256 sharesAmount) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        bytes32[] memory withdrawalRoots = IPufferModule(moduleAddress).queueWithdrawals(sharesAmount);
        emit WithdrawalsQueued(moduleName, sharesAmount, withdrawalRoots[0]);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callSetClaimerFor(address moduleOrReOp, address claimer) external virtual restricted {
        // We can cast `moduleOrReOp` to IPufferModule/IRestakingOperator, uses the same function signature.
        IPufferModule(moduleOrReOp).callSetClaimerFor(claimer);
        emit ClaimerSet({ rewardsReceiver: moduleOrReOp, claimer: claimer });
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callSetProofSubmitter(bytes32 moduleName, address proofSubmitter) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        IPufferModule(moduleAddress).setProofSubmitter(proofSubmitter);
        emit ProofSubmitterSet(moduleName, proofSubmitter);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function createNewRestakingOperator(
        string calldata metadataURI,
        address delegationApprover,
        uint32 stakerOptOutWindowBlocks
    ) external virtual restricted returns (IRestakingOperator) {
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            __deprecated_earningsReceiver: address(this),
            delegationApprover: delegationApprover,
            stakerOptOutWindowBlocks: stakerOptOutWindowBlocks
        });

        address restakingOperator = Create2.deploy({
            amount: 0,
            salt: keccak256(abi.encode(metadataURI)),
            bytecode: abi.encodePacked(
                type(BeaconProxy).creationCode,
                abi.encode(
                    RESTAKING_OPERATOR_BEACON,
                    abi.encodeCall(RestakingOperator.initialize, (authority(), operatorDetails, metadataURI))
                )
            )
        });

        emit RestakingOperatorCreated(restakingOperator, operatorDetails);

        return IRestakingOperator(restakingOperator);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callModifyOperatorDetails(
        IRestakingOperator restakingOperator,
        IDelegationManager.OperatorDetails calldata newOperatorDetails
    ) external virtual restricted {
        restakingOperator.modifyOperatorDetails(newOperatorDetails);
        emit RestakingOperatorModified(address(restakingOperator), newOperatorDetails);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callUpdateMetadataURI(IRestakingOperator restakingOperator, string calldata metadataURI)
        external
        virtual
        restricted
    {
        restakingOperator.updateOperatorMetadataURI(metadataURI);
        emit RestakingOperatorMetadataURIUpdated(address(restakingOperator), metadataURI);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callOptIntoSlashing(IRestakingOperator restakingOperator, address slasher) external virtual restricted {
        restakingOperator.optIntoSlashing(slasher);
        emit RestakingOperatorOptedInSlasher(address(restakingOperator), slasher);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callDelegateTo(
        bytes32 moduleName,
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        IPufferModule(moduleAddress).callDelegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit PufferModuleDelegated(moduleName, operator);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callUndelegate(bytes32 moduleName) external virtual restricted returns (bytes32[] memory withdrawalRoot) {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        withdrawalRoot = IPufferModule(moduleAddress).callUndelegate();

        emit PufferModuleUndelegated(moduleName);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callRegisterOperatorToAVS(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external virtual restricted {
        restakingOperator.registerOperatorToAVS({
            avsRegistryCoordinator: avsRegistryCoordinator,
            quorumNumbers: quorumNumbers,
            socket: socket,
            params: params,
            operatorSignature: operatorSignature
        });

        emit RestakingOperatorRegisteredToAVS(restakingOperator, avsRegistryCoordinator, quorumNumbers, socket);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callRegisterOperatorToAVSWithChurn(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        IRegistryCoordinator.OperatorKickParam[] calldata operatorKickParams,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata churnApproverSignature,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external virtual restricted {
        restakingOperator.registerOperatorToAVSWithChurn({
            avsRegistryCoordinator: avsRegistryCoordinator,
            quorumNumbers: quorumNumbers,
            socket: socket,
            params: params,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature,
            operatorSignature: operatorSignature
        });

        emit RestakingOperatorRegisteredToAVSWithChurn({
            restakingOperator: restakingOperator,
            avsRegistryCoordinator: avsRegistryCoordinator,
            quorumNumbers: quorumNumbers,
            socket: socket,
            operatorKickParams: operatorKickParams
        });
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function customExternalCall(IRestakingOperator restakingOperator, address target, bytes calldata customCalldata)
        external
        virtual
        restricted
    {
        // Custom external calls are only allowed to whitelisted registry coordinators
        if (!AVS_CONTRACTS_REGISTRY.isAllowedRegistryCoordinator(target, customCalldata)) {
            revert Unauthorized();
        }

        bytes memory response = restakingOperator.customCalldataCall(target, customCalldata);

        emit CustomCallSucceeded(address(restakingOperator), target, customCalldata, response);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callStartCheckpoint(address[] calldata moduleAddresses) external virtual restricted {
        for (uint256 i = 0; i < moduleAddresses.length; ++i) {
            // reverts if supplied with a duplicate module address
            IPufferModule(moduleAddresses[i]).startCheckpoint();
        }
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callDeregisterOperatorFromAVS(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        bytes calldata quorumNumbers
    ) external virtual restricted {
        restakingOperator.deregisterOperatorFromAVS(avsRegistryCoordinator, quorumNumbers);

        emit RestakingOperatorDeregisteredFromAVS(restakingOperator, avsRegistryCoordinator, quorumNumbers);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function callUpdateOperatorAVSSocket(
        IRestakingOperator restakingOperator,
        address avsRegistryCoordinator,
        string calldata socket
    ) external virtual restricted {
        restakingOperator.updateOperatorAVSSocket(avsRegistryCoordinator, socket);

        emit RestakingOperatorAVSSocketUpdated(restakingOperator, avsRegistryCoordinator, socket);
    }

    /**
     * @inheritdoc IPufferModuleManager
     * @dev Restricted to the DAO
     */
    function updateAVSRegistrationSignatureProof(
        IRestakingOperator restakingOperator,
        bytes32 digestHash,
        address signer
    ) external virtual restricted {
        restakingOperator.updateSignatureProof(digestHash, signer);

        emit AVSRegistrationSignatureProofUpdated(address(restakingOperator), digestHash, signer);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
