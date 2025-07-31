// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferProtocolManagement
 * @author Puffer Finance
 * @notice This interface contains the functions that are restricted to the DAO
 */
interface IPufferProtocolManagement {
    /**
     * @notice Change the minimum amount of VT that can be deposited
     * @param newMinimumVTAmount The new minimum amount of VT that can be deposited
     * @dev Restricted to the DAO
     */
    function changeMinimumVTAmount(uint256 newMinimumVTAmount) external;

    /**
     * @notice Change the weights of the modules
     * @param newModuleWeights The new weights of the modules
     * @dev Restricted to the DAO
     */
    function setModuleWeights(bytes32[] calldata newModuleWeights) external;

    /**
     * @notice Change the number of batches that can be registered for a module
     * @param moduleName The name of the module
     * @param limit The new number of batches that can be registered for a module
     * @dev Restricted to the DAO
     */
    function setBatchesLimitPerModule(bytes32 moduleName, uint128 limit) external;

    /**
     * @notice Change the penalty amount for a module
     * @param newPenaltyAmount The new penalty amount for a module
     * @dev Restricted to the DAO
     */
    function setVTPenalty(uint256 newPenaltyAmount) external;

    /**
     * @notice Change the PufferProtocolLogic contract
     * @param newPufferProtocolLogic The new PufferProtocolLogic contract
     * @dev Restricted to the DAO
     */
    function setPufferProtocolLogic(address newPufferProtocolLogic) external;

    /**
     * @notice Set the number of batches that are currently active for a module
     * @param moduleNames The names of the modules
     * @param newCurrentNumBatches The new number of batches that are currently active for a module
     * @dev Restricted to the DAO
     * @dev This function should only be called once, after the PufferProtocol contract is upgraded to the Pectra version.
     *      This is because the limit used to be the number of validators, and now it is the number of batches.
     */
    function setCurrentNumBatches(bytes32[] calldata moduleNames, uint128[] calldata newCurrentNumBatches) external;
}
