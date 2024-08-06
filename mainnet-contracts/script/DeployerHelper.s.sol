// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title Deployer Helper script
 * @notice Contains the addresses of the contracts that are already deployed
 */
abstract contract DeployerHelper is Script {
    AccessManager accessManager;
    address pufferVault;
    address validatorTicket;
    address pufferProtocol;
    address xPufETH;
    address lockbox;

    // Chain IDs
    uint256 mainnet = 1;
    uint256 holesky = 1700;
    uint256 binance = 56;
    uint256 base = 8453;

    function _loadExistingContractsAddresses() internal {
        _getAccessManager();
        _getPufferVault();
        _getValidatorTicket();
        _getPufferProtocol();
        _getXPufETH();
    }

    function _getAccessManager() internal returns (AccessManager) {
        if (block.chainid == base) {
            accessManager = AccessManager(0x6f62c8647b7cD3830F21BF0741BAD6f4b838Cb37);
        } else if (block.chainid == mainnet) {
            accessManager = AccessManager(0x8c1686069474410E6243425f4a10177a94EBEE11);
        } else if (block.chainid == holesky) {
            accessManager = AccessManager(0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e);
        } else if (block.chainid == binance) {
            accessManager = AccessManager(0x8849e9eB8bb27c1916AfB17ee4dEcAd375916474);
        } else {
            (, address msgSender,) = vm.readCallers();
            // Some fork / other network
            console.log("Deploying new access manager", block.chainid, msgSender);
            accessManager = new AccessManager(msgSender);
        }

        return accessManager;
    }

    function _getPufferVault() internal returns (address) {
        if (block.chainid == mainnet) {
            pufferVault = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        } else if (block.chainid == holesky) {
            pufferVault = 0x9196830bB4c05504E0A8475A0aD566AceEB6BeC9;
        }
        return pufferVault;
    }

    function _getValidatorTicket() internal returns (address) {
        if (block.chainid == mainnet) {
            validatorTicket = 0x7D26AD6F6BA9D6bA1de0218Ae5e20CD3a273a55A;
        } else if (block.chainid == holesky) {
            validatorTicket = 0xB028194785178a94Fe608994A4d5AD84c285A640;
        }
        return validatorTicket;
    }

    function _getPufferProtocol() internal returns (address) {
        if (block.chainid == mainnet) {
            pufferProtocol = 0xf7b6B32492c2e13799D921E84202450131bd238B;
        } else if (block.chainid == holesky) {
            pufferProtocol = 0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD;
        }
        return pufferProtocol;
    }

    function _getXPufETH() internal returns (address) {
        if (block.chainid == mainnet) {
            lockbox = 0xF78461CF59683af98dBec13C81dd064f4d77De48;
            xPufETH = 0xD7D2802f6b19843ac4DfE25022771FD83b5A7464;
        } else if (block.chainid == base) {
            xPufETH = 0x23dA5F2d509cb43A59d43C108a43eDf34510eff1;
        } else if (block.chainid == binance) {
            xPufETH = 0x64274835D88F5c0215da8AADd9A5f2D2A2569381;
        }
        return xPufETH;
    }
}
