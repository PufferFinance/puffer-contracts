// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IAeraVault, AssetValue } from "src/interface/Other/IAeraVault.sol";

contract MockAeraVault is IAeraVault {
    function deposit(AssetValue[] memory amounts) external { }

    function withdraw(AssetValue[] memory amounts) external { }

    function setGuardianAndFeeRecipient(address, address) external { }

    function setHooks(address hooks) external { }

    function finalize() external { }

    function pause() external { }

    function resume() external { }

    function claim() external { }

    function guardian() external view returns (address) { }

    function feeRecipient() external view returns (address) { }

    function fee() external view returns (uint256) { }

    function holdings() external view returns (AssetValue[] memory) { }

    function value() external view returns (uint256) { }
}
