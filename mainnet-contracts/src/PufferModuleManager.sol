// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferModule } from "./interface/IPufferModule.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { Unauthorized, InvalidAmount } from "./Errors.sol";
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
import { IDelegationManager } from "../src/interface/EigenLayer-Slashing/IDelegationManager.sol";
import { IDelegationManagerTypes } from "../src/interface/EigenLayer-Slashing/IDelegationManager.sol";
import { ISignatureUtils } from "../src/interface/EigenLayer-Slashing/ISignatureUtils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AVSContractsRegistry } from "./AVSContractsRegistry.sol";
import { RestakingOperator } from "./RestakingOperator.sol";
import { IAllocationManager } from "../src/interface/EigenLayer-Slashing/IAllocationManager.sol";

/**
 * @title PufferModuleManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferModuleManager is IPufferModuleManager, AccessManagedUpgradeable, UUPSUpgradeable {
    address public immutable PUFFER_MODULE_BEACON;
    address public immutable RESTAKING_OPERATOR_BEACON;
    address public immutable PUFFER_PROTOCOL;
    address payable public immutable PUFFER_VAULT;

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
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        IPufferModule(moduleAddress).completeQueuedWithdrawals({
            withdrawals: withdrawals,
            tokens: tokens,
            receiveAsTokens: receiveAsTokens
        });

        uint256 sharesWithdrawn;

        for (uint256 i = 0; i < withdrawals.length; ++i) {
            // nosemgrep array-length-outside-loop
            for (uint256 j = 0; j < withdrawals[i].scaledShares.length; ++j) {
                sharesWithdrawn += withdrawals[i].scaledShares[j];
            }
        }

        emit CompletedQueuedWithdrawals(moduleName, sharesWithdrawn);
    }

    /**
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
     * @dev Restricted to Puffer Paymaster
     */
    function callQueueWithdrawals(bytes32 moduleName, uint256 sharesAmount) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        bytes32[] memory withdrawalRoots = IPufferModule(moduleAddress).queueWithdrawals(sharesAmount);
        emit WithdrawalsQueued(moduleName, sharesAmount, withdrawalRoots[0]);
    }

    /**
     * @dev Restricted to the DAO
     */
    function callSetClaimerFor(address moduleOrReOp, address claimer) external virtual restricted {
        // We can cast `moduleOrReOp` to IPufferModule/RestakingOperator, uses the same function signature.
        IPufferModule(moduleOrReOp).callSetClaimerFor(claimer);
        emit ClaimerSet({ rewardsReceiver: moduleOrReOp, claimer: claimer });
    }

    /**
     * @dev Restricted to the DAO
     */
    function callSetProofSubmitter(bytes32 moduleName, address proofSubmitter) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        IPufferModule(moduleAddress).setProofSubmitter(proofSubmitter);
        emit ProofSubmitterSet(moduleName, proofSubmitter);
    }

    /**
     * @dev Restricted to the DAO
     */
    function createNewRestakingOperator(string calldata metadataURI, address delegationApprover, uint32 allocationDelay)
        external
        virtual
        restricted
        returns (RestakingOperator)
    {
        address restakingOperator = Create2.deploy({
            amount: 0,
            salt: keccak256(abi.encode(metadataURI)),
            bytecode: abi.encodePacked(
                type(BeaconProxy).creationCode,
                abi.encode(
                    RESTAKING_OPERATOR_BEACON,
                    abi.encodeCall(
                        RestakingOperator.initialize, (authority(), delegationApprover, metadataURI, allocationDelay)
                    )
                )
            )
        });

        emit RestakingOperatorCreated(restakingOperator, delegationApprover);

        return RestakingOperator(restakingOperator);
    }

    /**
     * @dev Restricted to the DAO
     */
    function callModifyOperatorDetails(RestakingOperator restakingOperator, address newDelegationApprover)
        external
        virtual
        restricted
    {
        restakingOperator.modifyOperatorDetails(newDelegationApprover);
        emit RestakingOperatorModified(address(restakingOperator), newDelegationApprover);
    }

    /**
     * @dev Restricted to the DAO
     */
    function callUpdateMetadataURI(RestakingOperator restakingOperator, string calldata metadataURI)
        external
        virtual
        restricted
    {
        restakingOperator.updateOperatorMetadataURI(metadataURI);
        emit RestakingOperatorMetadataURIUpdated(address(restakingOperator), metadataURI);
    }

    /**
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
     * @dev Restricted to the DAO
     */
    function callUndelegate(bytes32 moduleName) external virtual restricted returns (bytes32[] memory withdrawalRoot) {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        withdrawalRoot = IPufferModule(moduleAddress).callUndelegate();

        emit PufferModuleUndelegated(moduleName);
    }

    /**
     * @dev Restricted to the DAO
     */
    function callRegisterOperatorToAVS(
        RestakingOperator restakingOperator,
        IAllocationManager.RegisterParams calldata registrationParams
    ) external virtual restricted {
        restakingOperator.registerOperatorToAVS(registrationParams);
    }

    /**
     * @dev Restricted to the DAO
     */
    function customExternalCall(RestakingOperator restakingOperator, address target, bytes calldata customCalldata)
        external
        virtual
        restricted
    {
        bytes memory response = restakingOperator.customCalldataCall(target, customCalldata);

        emit CustomCallSucceeded(address(restakingOperator), target, customCalldata, response);
    }

    /**
     * @dev Restricted to the DAO
     */
    function callStartCheckpoint(address[] calldata moduleAddresses) external virtual restricted {
        for (uint256 i = 0; i < moduleAddresses.length; ++i) {
            // reverts if supplied with a duplicate module address
            IPufferModule(moduleAddresses[i]).startCheckpoint();
        }
    }

    /**
     * @dev Restricted to the DAO
     */
    function callDeregisterOperatorFromAVS(
        RestakingOperator restakingOperator,
        IAllocationManager.DeregisterParams calldata deregistrationParams
    ) external virtual restricted {
        restakingOperator.deregisterOperatorFromAVS(deregistrationParams);
    }

    /**
     * @dev Restricted to the DAO
     */
    function updateAVSRegistrationSignatureProof(
        RestakingOperator restakingOperator,
        bytes32 digestHash,
        address signer
    ) external virtual restricted {
        restakingOperator.updateSignatureProof(digestHash, signer);

        emit AVSRegistrationSignatureProofUpdated(address(restakingOperator), digestHash, signer);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
