// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPermissionedOracle } from "../../src/interface/IPermissionedOracle.sol";

/**
 * @title MockPermissionedOracle
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract MockPermissionedOracle is IPermissionedOracle {
    function getLockedEthAmount() external view override returns (uint256) { }

    function getModuleLockedEth(bytes32 moduleName) external view override returns (uint256) { }

    function provisionValidator(bytes32 moduleName, uint256 amount) external override { }

    function exitValidator(bytes32 moduleName, uint256 amount) external override { }

    function adjustLockedEth(bytes32 moduleName, uint256 reductionAmount) external override { }
}
