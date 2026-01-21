// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IPermissionedOracle } from "./interface/IPermissionedOracle.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title PermissionedOracle
 * @notice Oracle for tracking ETH locked by permissioned validators
 * @dev Tracks actual ETH amounts per module to support Pectra variable stake (32-2048 ETH)
 * @custom:security-contact security@puffer.fi
 */
contract PermissionedOracle is IPermissionedOracle, AccessManaged {
    /**
     * @notice Locked ETH per module
     */
    mapping(bytes32 moduleName => uint256 lockedEth) public moduleLockedEth;

    /**
     * @notice Total locked ETH across all permissioned validators
     */
    uint256 public totalLockedEth;

    constructor(address accessManager) AccessManaged(accessManager) { }

    /**
     * @inheritdoc IPermissionedOracle
     */
    function getLockedEthAmount() external view returns (uint256) {
        return totalLockedEth;
    }

    /**
     * @inheritdoc IPermissionedOracle
     */
    function getModuleLockedEth(bytes32 moduleName) external view returns (uint256) {
        return moduleLockedEth[moduleName];
    }

    /**
     * @inheritdoc IPermissionedOracle
     */
    function provisionValidator(bytes32 moduleName, uint256 amount) external restricted {
        moduleLockedEth[moduleName] += amount;
        totalLockedEth += amount;
        emit PermissionedValidatorProvisioned(moduleName, amount);
    }

    /**
     * @inheritdoc IPermissionedOracle
     */
    function exitValidator(bytes32 moduleName, uint256 amount) external restricted {
        moduleLockedEth[moduleName] -= amount;
        totalLockedEth -= amount;
        emit PermissionedValidatorExited(moduleName, amount);
    }
}
