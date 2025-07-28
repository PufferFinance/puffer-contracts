// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IPufferProtocolManagement
 * @author Puffer Finance
 * @notice This interface contains the functions that are restricted to the DAO
 */
interface IPufferProtocolManagement {
    /**
     * @dev Restricted to the DAO
     */
    function changeMinimumVTAmount(uint256 newMinimumVTAmount) external;

    /**
     * @dev Restricted to the DAO
     */
    function setModuleWeights(bytes32[] calldata newModuleWeights) external;

    /**
     * @dev Restricted to the DAO
     */
    function setValidatorLimitPerModule(bytes32 moduleName, uint128 limit) external;

    /**
     * @dev Restricted to the DAO
     */
    function setVTPenalty(uint256 newPenaltyAmount) external;

    /**
     * @dev Restricted to the DAO
     */
    function setPufferProtocolLogic(address newPufferProtocolLogic) external;
}
