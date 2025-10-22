// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { Unauthorized, InvalidAmount } from "./Errors.sol";
import { IPufferProtocol } from "./interface/IPufferProtocol.sol";
import { PufferModule } from "./PufferModule.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { RestakingOperator } from "./RestakingOperator.sol";
import { IPufferModuleManager } from "./interface/IPufferModuleManager.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IDelegationManagerTypes } from "../src/interface/Eigenlayer-Slashing/IDelegationManager.sol";
import { ISignatureUtils } from "../src/interface/Eigenlayer-Slashing/ISignatureUtils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RestakingOperator } from "./RestakingOperator.sol";
import { IAllocationManager } from "../src/interface/Eigenlayer-Slashing/IAllocationManager.sol";
import { PufferModule } from "./PufferModule.sol";

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

    modifier onlyPufferProtocol() {
        if (msg.sender != PUFFER_PROTOCOL) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address pufferModuleBeacon, address restakingOperatorBeacon, address pufferProtocol) {
        PUFFER_MODULE_BEACON = pufferModuleBeacon;
        RESTAKING_OPERATOR_BEACON = restakingOperatorBeacon;
        PUFFER_PROTOCOL = pufferProtocol;
        PUFFER_VAULT = payable(address(IPufferProtocol(PUFFER_PROTOCOL).PUFFER_VAULT()));
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
     * @param moduleName The name of the module
     * @param withdrawals The list of withdrawals to complete
     * @param tokens The list of tokens to withdraw
     * @param receiveAsTokens Whether to receive the tokens as ERC20 tokens
     * @dev Restricted to Puffer Paymaster
     */
    function callCompleteQueuedWithdrawals(
        bytes32 moduleName,
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        PufferModule(payable(moduleAddress)).completeQueuedWithdrawals({
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
     * @notice Create a new Puffer module
     * @dev This function creates a new Puffer module with the given module name
     * @param moduleName The name of the module
     * @return module The newly created Puffer module
     * @dev Restricted to Puffer Protocol
     */
    function createNewPufferModule(bytes32 moduleName) external virtual onlyPufferProtocol returns (PufferModule) {
        if (moduleName == bytes32("NO_VALIDATORS")) {
            revert ForbiddenModuleName();
        }
        // This called from the PufferProtocol and the event is emitted there
        return PufferModule(
            payable(
                Create2.deploy({
                    amount: 0,
                    salt: moduleName,
                    bytecode: abi.encodePacked(
                        type(BeaconProxy).creationCode,
                        abi.encode(PUFFER_MODULE_BEACON, abi.encodeCall(PufferModule.initialize, (moduleName, authority())))
                    )
                })
            )
        );
    }

    /**
     * @notice Transfers the unlocked rewards from the modules to the vault
     *
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
            (bool success,) = PufferModule(payable(modules[i])).call(address(this), rewardsAmounts[i], "");
            if (!success) {
                revert InvalidAmount();
            }
            totalRewardsAmount += rewardsAmounts[i];
        }

        PufferVaultV5(PUFFER_VAULT).depositRewards{ value: totalRewardsAmount }();
    }

    /**
     * @notice Queues the withdrawals for the given module
     * @param moduleName The name of the module
     * @param sharesAmount The amount of shares to withdraw
     * @dev Restricted to Puffer Paymaster
     */
    function callQueueWithdrawals(bytes32 moduleName, uint256 sharesAmount) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        bytes32[] memory withdrawalRoots = PufferModule(payable(moduleAddress)).queueWithdrawals(sharesAmount);
        emit WithdrawalsQueued(moduleName, sharesAmount, withdrawalRoots[0]);
    }

    /**
     * @notice Calls the `callSetClaimerFor` function on the target module or restaking operator contract
     * @param moduleOrReOp is the address of the target module or restaking operator contract
     * @param claimer is the address of the claimer to be set
     * @dev Restricted to the DAO
     */
    function callSetClaimerFor(address moduleOrReOp, address claimer) external virtual restricted {
        // We can cast `moduleOrReOp` to PufferModule/RestakingOperator, uses the same function signature.
        PufferModule(payable(moduleOrReOp)).callSetClaimerFor(claimer);
        emit ClaimerSet({ rewardsReceiver: moduleOrReOp, claimer: claimer });
    }

    /**
     * @notice Sets proof Submitter on the Puffer Module
     * @param moduleName The name of the module
     * @param proofSubmitter The address of the proof submitter
     * @dev Restricted to the DAO
     */
    function callSetProofSubmitter(bytes32 moduleName, address proofSubmitter) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        PufferModule(payable(moduleAddress)).setProofSubmitter(proofSubmitter);
        emit ProofSubmitterSet(moduleName, proofSubmitter);
    }

    /**
     * @notice Create a new Restaking Operator
     * @param metadataURI is a URI for the operator's metadata, i.e. a link providing more details on the operator.
     * @param allocationDelay is the delay in seconds before the operator can be used for allocation
     * @return restakingOperator The address of the newly created Restaking Operator
     * @dev Restricted to the DAO
     */
    function createNewRestakingOperator(string calldata metadataURI, uint32 allocationDelay)
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
                    abi.encodeCall(RestakingOperator.initialize, (authority(), metadataURI, allocationDelay))
                )
            )
        });

        emit RestakingOperatorCreated(restakingOperator);

        return RestakingOperator(restakingOperator);
    }

    /**
     * @notice Calls the callDelegateTo function on the target module
     * @param moduleName is the name of the module
     * @param operator is the address of the restaking operator
     * @param approverSignatureAndExpiry the signature of the delegation approver
     * @param approverSalt salt for the signature
     * @dev Restricted to the DAO
     */
    function callDelegateTo(
        bytes32 moduleName,
        address operator,
        ISignatureUtils.SignatureWithExpiry calldata approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external virtual restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        PufferModule(payable(moduleAddress)).callDelegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit PufferModuleDelegated(moduleName, operator);
    }

    /**
     * @notice Calls the callUndelegate function on the target module
     * @param moduleName is the name of the module
     * @dev Restricted to the DAO
     */
    function callUndelegate(bytes32 moduleName) external virtual restricted returns (bytes32[] memory withdrawalRoot) {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);

        withdrawalRoot = PufferModule(payable(moduleAddress)).callUndelegate();

        emit PufferModuleUndelegated(moduleName);
    }

    /**
     * @notice Triggers the validators exit for the given pubkeys
     * @param moduleName The name of the Puffer module
     * @param pubkeys The pubkeys of the validators to exit
     * @dev Restricted to the DAO
     * @dev According to EIP-7002 there is a fee for each validator exit request (See https://eips.ethereum.org/assets/eip-7002/fee_analysis)
     *      The fee is paid in the msg.value of this function. Since the fee is not fixed and might change, the excess amount will be kept in the PufferModule
     */
    function triggerValidatorsExit(bytes32 moduleName, bytes[] calldata pubkeys) external virtual payable restricted {
        address moduleAddress = IPufferProtocol(PUFFER_PROTOCOL).getModuleAddress(moduleName);
        PufferModule(payable(moduleAddress)).triggerValidatorsExit{value: msg.value}(pubkeys);

        emit ValidatorsExitTriggered(moduleName, pubkeys);
    }

    /**
     * @notice Calls the callRegisterOperatorToAVS function on the target restaking operator
     * @param restakingOperator is the address of the restaking operator
     * @param registrationParams is the struct with new operator details
     * @dev Restricted to the DAO
     */
    function callRegisterOperatorToAVS(
        RestakingOperator restakingOperator,
        IAllocationManager.RegisterParams calldata registrationParams
    ) external virtual restricted {
        restakingOperator.registerOperatorToAVS(registrationParams);
        emit RestakingOperatorRegisteredToAVS(
            address(restakingOperator),
            registrationParams.avs,
            registrationParams.operatorSetIds,
            registrationParams.data
        );
    }

    /**
     * @notice Calls the `target` contract with `customCalldata` from the Restaking Operator contract
     * @param restakingOperator is the Restaking Operator contract
     * @param target is the address of the target contract that ReOp will call
     * @param customCalldata is the calldata to be passed to the target contract
     * @dev Restricted to the DAO
     */
    function customExternalCall(RestakingOperator restakingOperator, address target, bytes calldata customCalldata)
        external
        payable
        virtual
        restricted
    {
        bytes memory response = restakingOperator.customCalldataCall{ value: msg.value }(target, customCalldata);

        emit CustomCallSucceeded(address(restakingOperator), target, customCalldata, response);
    }

    /**
     * @notice Calls the callDeregisterOperatorFromAVS function on the target restaking operator
     * @param restakingOperator is the address of the restaking operator
     * @param deregistrationParams is the struct with new operator details
     * @dev Restricted to the DAO
     */
    function callDeregisterOperatorFromAVS(
        RestakingOperator restakingOperator,
        IAllocationManager.DeregisterParams calldata deregistrationParams
    ) external virtual restricted {
        restakingOperator.deregisterOperatorFromAVS(deregistrationParams);

        emit RestakingOperatorDeregisteredFromAVS(
            address(restakingOperator), deregistrationParams.avs, deregistrationParams.operatorSetIds
        );
    }

    /**
     * @notice Updates AVS registration signature proof
     * @param restakingOperator is the address of the restaking operator
     * @param digestHash is the message hash
     * @param signer is the address of the signature signer
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
