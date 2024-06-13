// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title IMigrator
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IMigrator {
    function migrate(address depositor, address destination, uint256 amount) external;
}
