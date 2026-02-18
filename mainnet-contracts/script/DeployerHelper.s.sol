// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @notice Contains the addresses of the contracts that are already deployed
 *
 * https://github.com/PufferFinance/Deployments-and-ACL?tab=readme-ov-file
 */
abstract contract DeployerHelper is Script {
    // Chain IDs
    uint256 public mainnet = 1;
    uint256 public holesky = 17000;
    uint256 public hoodi = 560048;
    uint256 public binance = 56;
    uint256 public base = 8453;
    uint256 public sepolia = 11155111;
    uint256 public opSepolia = 11155420;
    uint256 public ape = 33139;

    function _getDeployer() internal returns (address) {
        (, address msgSender,) = vm.readCallers();
        console.log("Deployer:", block.chainid, msgSender);
        return msgSender;
    }

    function _getPufferDeployer() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xb7d83623906AC3fa577F45B7D2b9D4BD26BC5d76
            return 0xb7d83623906AC3fa577F45B7D2b9D4BD26BC5d76;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0
            return 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE
            return 0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE;
        } else if (block.chainid == ape) {
            // https://apescan.io/address/0xb7d83623906AC3fa577F45B7D2b9D4BD26BC5d76
            return 0xb7d83623906AC3fa577F45B7D2b9D4BD26BC5d76;
        }

        revert("PufferDeployer not available for this chain");
    }

    function _getDAO() internal view returns (address) {
        // ATM Ops multisig is the DAO
        return _getOPSMultisig();
    }

    /**
     * @dev Upgrade the implementation of the `proxyTarget` to `newImplementation` if on Holesky,
     * otherwise log the call data.
     */
    function _consoleLogOrUpgradeUUPS(
        address proxyTarget,
        address implementation,
        bytes memory data,
        string memory contractName
    ) internal {
        vm.label(implementation, contractName);
        console.log("Deployed", contractName, "at", implementation);

        if (block.chainid == holesky) {
            AccessManager(_getAccessManager()).execute(
                proxyTarget, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(implementation), data))
            );
        } else {
            bytes memory upgradeCallData =
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(implementation), data));
            console.log("Queue TX From Timelock to -> ", proxyTarget);
            console.logBytes(upgradeCallData);
            console.log("================================================");
        }
    }

    function _getCARROT() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x282A69142bac47855C3fbE1693FcC4bA3B4d5Ed6
            return 0x282A69142bac47855C3fbE1693FcC4bA3B4d5Ed6;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x82a44a6489936FFF841eecAF650Aa4D9708E4312
            return 0x82a44a6489936FFF841eecAF650Aa4D9708E4312;
        }

        revert("CARROT not available for this chain");
    }
    /**
     * @dev Used only for testnet deployment and fork tests, where the _paymaster is the deployer
     */

    function _consoleLogOrUpgradeUUPSPrank(
        address proxyTarget,
        address implementation,
        bytes memory data,
        string memory contractName
    ) internal {
        vm.startPrank(_getPaymaster());
        vm.label(implementation, contractName);
        console.log("Deployed", contractName, "at", implementation);

        if (block.chainid == holesky) {
            // @DEPRECATED
            AccessManager(_getAccessManager()).execute(
                proxyTarget, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(implementation), data))
            );
        } else {
            bytes memory upgradeCallData =
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(implementation), data));
            console.log("Queue TX From Timelock to -> ", proxyTarget);
            console.logBytes(upgradeCallData);
            console.log("================================================");
        }
    }

    function _getBeaconChainStrategy() internal view returns (address) {
        if (block.chainid == holesky) {
            return 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
        }

        revert("BEACON_CHAIN_STRATEGY not available for this chain");
    }

    function _getTreasury() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x946Ae7b21de3B0793Bb469e263517481B74A6950
            return 0x946Ae7b21de3B0793Bb469e263517481B74A6950;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x61A44645326846F9b5d9c6f91AD27C3aD28EA390
            return 0x61A44645326846F9b5d9c6f91AD27C3aD28EA390;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x61A44645326846F9b5d9c6f91AD27C3aD28EA390
            return 0x61A44645326846F9b5d9c6f91AD27C3aD28EA390;
        }

        revert("Treasury not available for this chain");
    }

    function _getAllocationManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x948a420b8CC1d6BFd0B6087C2E7c344a2CD0bc39
            return 0x948a420b8CC1d6BFd0B6087C2E7c344a2CD0bc39;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xcAe751b75833ef09627549868A04E32679386e7C
            return 0xcAe751b75833ef09627549868A04E32679386e7C;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x95a7431400F362F3647a69535C5666cA0133CAA0
            return 0x95a7431400F362F3647a69535C5666cA0133CAA0;
        }

        revert("AllocationManager not available for this chain");
    }

    function _getRestakingOperatorBeacon() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x6756B856Dd3843C84249a6A31850cB56dB824c4B
            return 0x6756B856Dd3843C84249a6A31850cB56dB824c4B;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x99c3E46E575df251149866285DdA7DAEba875B71
            return 0x99c3E46E575df251149866285DdA7DAEba875B71;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x6a5c73AB3e5Bc3675A2e1CCcc46aF6796db36BC8
            return 0x6a5c73AB3e5Bc3675A2e1CCcc46aF6796db36BC8;
        }

        revert("RestakingOperatorBeacon not available for this chain");
    }

    function _getBeaconDepositContract() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x00000000219ab540356cBB839Cbe05303d7705Fa
            return 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x4242424242424242424242424242424242424242
            return 0x4242424242424242424242424242424242424242;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x00000000219ab540356cBB839Cbe05303d7705Fa
            return 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        }

        revert("BeaconDepositContract not available for this chain");
    }

    function _getGuardianModule() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x628b183F248a142A598AA2dcCCD6f7E480a7CcF2
            return 0x628b183F248a142A598AA2dcCCD6f7E480a7CcF2;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x0910310130d1c062DEF8B807528bdac80203BC66
            return 0x0910310130d1c062DEF8B807528bdac80203BC66;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x57bC9fDcd05bD53bCe1B2db3a50Eb5948Bd4e5c7
            return 0x57bC9fDcd05bD53bCe1B2db3a50Eb5948Bd4e5c7;
        }

        revert("GuardianModule not available for this chain");
    }

    function _getPufferModuleBeacon() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xdd38A5a7789C74fc7F64556fc772343658EEBb04
            return 0xdd38A5a7789C74fc7F64556fc772343658EEBb04;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x4B0542470935ed4b085C3AD1983E85f5623ABf89
            return 0x4B0542470935ed4b085C3AD1983E85f5623ABf89;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x6899d0dE991458929b43e3DE4fC2d4A9ca7E4673
            return 0x6899d0dE991458929b43e3DE4fC2d4A9ca7E4673;
        }

        revert("PufferModuleBeacon not available for this chain");
    }

    function _getEigenPodManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338
            return 0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x30770d7E3e71112d7A6b7259542D1f680a70e315
            return 0x30770d7E3e71112d7A6b7259542D1f680a70e315;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xcd1442415Fc5C29Aa848A49d2e232720BE07976c
            return 0xcd1442415Fc5C29Aa848A49d2e232720BE07976c;
        }

        revert("EigenPodManager not available for this chain");
    }

    function _getDelegationManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A
            return 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xA44151489861Fe9e3055d95adC98FbD462B948e7
            return 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x867837a9722C512e0862d8c2E15b8bE220E8b87d
            return 0x867837a9722C512e0862d8c2E15b8bE220E8b87d;
        }

        revert("DelegationManager not available for this chain");
    }

    function _getAVSContractsRegistry() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x1565E55B63675c703fcC3778BD33eA97F7bE882F
            return 0x1565E55B63675c703fcC3778BD33eA97F7bE882F;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x09BE86B01c1e32dCa2ebdEDb01cD5A3F798b80C5
            return 0x09BE86B01c1e32dCa2ebdEDb01cD5A3F798b80C5;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x5150F12A6f5a3D071A84442a671a4B234B53beC4
            return 0x5150F12A6f5a3D071A84442a671a4B234B53beC4;
        }

        revert("AVSContractsRegistry not available for this chain");
    }

    function _getTimelock() internal view returns (address) {
        if (block.chainid == mainnet) {
            // Mainnet Timelock: https://etherscan.io/address/0x3C28B7c7Ba1A1f55c9Ce66b263B33B204f2126eA
            return 0x3C28B7c7Ba1A1f55c9Ce66b263B33B204f2126eA;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // Holesky Timelock: https://explorer.pops.one/address/0x829aF0B3d099a12F0aE1b806f466EF771E2C07F8
            return 0x829aF0B3d099a12F0aE1b806f466EF771E2C07F8;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xD256D160598ba8e068fC62C7fED46694CdD48762
            return 0xD256D160598ba8e068fC62C7fED46694CdD48762;
        }

        revert("Timelock not available for this chain");
    }

    function _getRewardsCoordinator() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x7750d328b314EfFa365A0402CcfD489B80B0adda
            return 0x7750d328b314EfFa365A0402CcfD489B80B0adda;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xAcc1fb458a1317E886dB376Fc8141540537E68fE
            return 0xAcc1fb458a1317E886dB376Fc8141540537E68fE;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x29e8572678e0c272350aa0b4B8f304E47EBcd5e7
            return 0x29e8572678e0c272350aa0b4B8f304E47EBcd5e7;
        }

        revert("RewardsCoordinator not available for this chain");
    }

    function _getStETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
            return 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034
            return 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x3508A952176b3c15387C97BE809eaffB1982176a
            return 0x3508A952176b3c15387C97BE809eaffB1982176a;
        }

        revert("stETH not available for this chain");
    }

    function _getWstETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
        }
        if (block.chainid == hoodi) {
            return 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4;
        }

        revert("WstETH not available for this chain");
    }

    function _getStETHStrategy() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x93c4b944D05dfe6df7645A86cd2206016c51564D
            return 0x93c4b944D05dfe6df7645A86cd2206016c51564D;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3
            return 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xF8a1a66130D614c7360e868576D5E59203475FE0
            return 0xF8a1a66130D614c7360e868576D5E59203475FE0;
        }

        revert("stETH strategy not available for this chain");
    }

    function _getEigenLayerStrategyManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x858646372CC42E1A627fcE94aa7A7033e7CF075A
            return 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
            return 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xeE45e76ddbEDdA2918b8C7E3035cd37Eab3b5D41
            return 0xeE45e76ddbEDdA2918b8C7E3035cd37Eab3b5D41;
        }

        revert("strategy manager not available for this chain");
    }

    function _getPufferOracle() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x0BE2aE0edbeBb517541DF217EF0074FC9a9e994f
            return 0x0BE2aE0edbeBb517541DF217EF0074FC9a9e994f;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x8e043ed3F06720615685D4978770Cd5C8fe90fe3
            return 0x8e043ed3F06720615685D4978770Cd5C8fe90fe3;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xF232Df3a714c99C05100571644b6d4AA1000ee4E
            return 0xF232Df3a714c99C05100571644b6d4AA1000ee4E;
        }

        revert("puffer oracle not available for this chain");
    }

    function _getEigenDelegationManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A
            return 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xA44151489861Fe9e3055d95adC98FbD462B948e7
            return 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x867837a9722C512e0862d8c2E15b8bE220E8b87d
            return 0x867837a9722C512e0862d8c2E15b8bE220E8b87d;
        }

        revert("eigen delegation manager not available for this chain");
    }

    function _getWETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x1d181cBd1825e9eBC6AD966878D555A7215FF4F0
            return 0x1d181cBd1825e9eBC6AD966878D555A7215FF4F0;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x06EDa6073b3dE1B1Dfd58cb5615fD8188C114a88
            return 0x06EDa6073b3dE1B1Dfd58cb5615fD8188C114a88;
        }

        revert("WETH not available for this chain");
    }

    function _getLidoWithdrawalQueue() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1
            return 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50
            return 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xfe56573178f1bcdf53F01A6E9977670dcBBD9186
            return 0xfe56573178f1bcdf53F01A6E9977670dcBBD9186;
        }

        revert("lido withdrawal queue not available for this chain");
    }

    function _getAccessManager() internal view returns (address) {
        if (block.chainid == base) {
            // https://basescan.org/address/0x6f62c8647b7cD3830F21BF0741BAD6f4b838Cb37
            return 0x6f62c8647b7cD3830F21BF0741BAD6f4b838Cb37;
        } else if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x8c1686069474410E6243425f4a10177a94EBEE11
            return 0x8c1686069474410E6243425f4a10177a94EBEE11;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e
            return 0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x0950195ac9b310815698f5dded3bd32814f46efd
            return 0x0950195ac9b310815698f5dded3bd32814f46efd;
        } else if (block.chainid == binance) {
            // https://bscscan.com/address/0x8849e9eB8bb27c1916AfB17ee4dEcAd375916474
            return 0x8849e9eB8bb27c1916AfB17ee4dEcAd375916474;
        } else if (block.chainid == sepolia) {
            // https://sepolia.etherscan.io/address/0xc98dFfD21F55f2eb2461E6cD7f8838DC33AEddDc
            return 0xc98dFfD21F55f2eb2461E6cD7f8838DC33AEddDc;
        } else if (block.chainid == opSepolia) {
            // https://sepolia-optimism.etherscan.io/address/0xccE1f605FdeeFA15b5708B87De3240196fEf0CA4
            return 0xccE1f605FdeeFA15b5708B87De3240196fEf0CA4;
        }

        revert("AccessManager not available for this chain");
    }

    function _getPufferVault() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xD9A442856C234a39a81a089C06451EBAa4306a72
            return 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x9196830bB4c05504E0A8475A0aD566AceEB6BeC9
            return 0x9196830bB4c05504E0A8475A0aD566AceEB6BeC9;
        } else if (block.chainid == sepolia) {
            // PufferVaultMock
            // https://sepolia.etherscan.io/address/0xd85D701A660a61D9737D05397612EF08be2cE62D
            return 0xd85D701A660a61D9737D05397612EF08be2cE62D;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x3248c7b9D2c8e427A2752cA2339166830FA83479
            return 0x3248c7b9D2c8e427A2752cA2339166830FA83479;
        }

        revert("PufferVault not available for this chain");
    }

    function _getPufferModuleManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x9E1E4fCb49931df5743e659ad910d331735C3860
            return 0x9E1E4fCb49931df5743e659ad910d331735C3860;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x20377c306451140119C9967Ba6D0158a05b4eD07
            return 0x20377c306451140119C9967Ba6D0158a05b4eD07;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x26eEa064e7Ed6b52847f8153Cd466A7b01f2cB14
            return 0x26eEa064e7Ed6b52847f8153Cd466A7b01f2cB14;
        }

        revert("PufferModuleManager not available for this chain");
    }

    function _getValidatorTicket() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x7D26AD6F6BA9D6bA1de0218Ae5e20CD3a273a55A
            return 0x7D26AD6F6BA9D6bA1de0218Ae5e20CD3a273a55A;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xB028194785178a94Fe608994A4d5AD84c285A640
            return 0xB028194785178a94Fe608994A4d5AD84c285A640;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0x032E3fF6716084Bd8D50a35f1cfC9a22cEeB0355
            return 0x032E3fF6716084Bd8D50a35f1cfC9a22cEeB0355;
        }

        revert("ValidatorTicket not available for this chain");
    }

    function _getPufferProtocol() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xf7b6B32492c2e13799D921E84202450131bd238B
            return 0xf7b6B32492c2e13799D921E84202450131bd238B;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD
            return 0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xa3eca8ef718538Fc2610899e95590B521D59a842
            return 0xa3eca8ef718538Fc2610899e95590B521D59a842;
        }

        revert("PufferProtocol not available for this chain");
    }

    function _getRestakingOperatorController() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x953b4113716CE71596F7Ba6B0E75050c25c493c1
            return 0x953b4113716CE71596F7Ba6B0E75050c25c493c1;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/-
            return address(0);
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xa3eca8ef718538Fc2610899e95590B521D59a842
            return 0xa3eca8ef718538Fc2610899e95590B521D59a842;
        }

        revert("RestakingOperatorController not available for this chain");
    }

    function _getDeprecatedXPufETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xD7D2802f6b19843ac4DfE25022771FD83b5A7464
            return 0xD7D2802f6b19843ac4DfE25022771FD83b5A7464;
        } else if (block.chainid == base) {
            // https://basescan.org/address/0x23dA5F2d509cb43A59d43C108a43eDf34510eff1
            return 0x23dA5F2d509cb43A59d43C108a43eDf34510eff1;
        } else if (block.chainid == binance) {
            // https://bscscan.com/address/0x64274835D88F5c0215da8AADd9A5f2D2A2569381
            return 0x64274835D88F5c0215da8AADd9A5f2D2A2569381;
        } else if (block.chainid == sepolia) {
            // https://sepolia.etherscan.io/address/0xc63b3a075269F67Dd0C4B21dedBed23E39A01aff
            return 0xc63b3a075269F67Dd0C4B21dedBed23E39A01aff;
        } else if (block.chainid == opSepolia) {
            // https://sepolia-optimism.etherscan.io/address/0xCcCA977cC71a8c97518b9A9b134263e83389B338
            return 0xCcCA977cC71a8c97518b9A9b134263e83389B338;
        }

        revert("XPufETH not available for this chain");
    }

    function _getDeprecatedLockbox() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xd44E91CfBBAa7b3B259A12a43b38CEBf47B463D5
            return 0xd44E91CfBBAa7b3B259A12a43b38CEBf47B463D5;
        } else if (block.chainid == sepolia) {
            // https://sepolia.etherscan.io/address/0xC89A39742AbA9944089DD06Cc1bc994793D68684
            return 0xC89A39742AbA9944089DD06Cc1bc994793D68684;
        }

        revert("Lockbox not available for this chain");
    }

    function _getDeprecatedEverclear() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6
            return 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;
        } else if (block.chainid == base) {
            // https://basescan.org/address/0xB8448C6f7f7887D36DcA487370778e419e9ebE3F
            return 0xB8448C6f7f7887D36DcA487370778e419e9ebE3F;
        } else if (block.chainid == binance) {
            // https://bscscan.com/address/0xCd401c10afa37d641d2F594852DA94C700e4F2CE
            return 0xCd401c10afa37d641d2F594852DA94C700e4F2CE;
        } else if (block.chainid == opSepolia) {
            // https://sepolia.optimism.io/address/0x8247ed6d0a344eeae4edBC7e44572F1B70ECA82A
            return 0x8247ed6d0a344eeae4edBC7e44572F1B70ECA82A;
        } else if (block.chainid == sepolia) {
            // https://sepolia.etherscan.io/address/0x445fbf9cCbaf7d557fd771d56937E94397f43965
            return 0x445fbf9cCbaf7d557fd771d56937E94397f43965;
        } else if (block.chainid == ape) {
            // https://apescan.io/address/0xD1daF260951B8d350a4AeD5C80d74Fd7298C93F4
            return 0xD1daF260951B8d350a4AeD5C80d74Fd7298C93F4;
        }

        revert("Everclear not available for this chain");
    }

    function _getPufETHOFTAdapter() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xa4931a9F9Aaf79057334371D6f62164743f97b18
            return 0xa4931a9F9Aaf79057334371D6f62164743f97b18;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xfe235A03d87FCBf94E91536955c8a6b1FF50A5C0
            return 0xfe235A03d87FCBf94E91536955c8a6b1FF50A5C0;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/???
            // return ???;
            // TODO Add address once deployed
        }

        revert("PufETHOFT not available for this chain");
    }

    function _getPufETHOFT() internal view returns (address) {
        if (block.chainid == sepolia) {
            // https://sepolia.etherscan.io/address/0xc0F1A1B26E7B3661c4875621883362CC48951c10
            return 0xc0F1A1B26E7B3661c4875621883362CC48951c10;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/???
            // return ???;
            // TODO Add address once deployed
        }

        revert("PufETHOFT not available for this chain");
    }

    function _getLayerZeroV2Endpoint() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x1a44076050125825900e736c501f859c50fE728c
            return 0x1a44076050125825900e736c501f859c50fE728c;
        } else if (block.chainid == base) {
            // https://basescan.org/address/0x1a44076050125825900e736c501f859c50fE728c
            return 0x1a44076050125825900e736c501f859c50fE728c;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0x6EDCE65403992e310A62460808c4b910D972f10f
            return 0x6EDCE65403992e310A62460808c4b910D972f10f;
        } else if (block.chainid == sepolia) {
            // https://sepolia.etherscan.io/address/0x6EDCE65403992e310A62460808c4b910D972f10f
            return 0x6EDCE65403992e310A62460808c4b910D972f10f;
        }

        revert("LayerZeroV2Endpoint not available for this chain");
    }

    function _getLayerZeroDestinationEID() internal view returns (uint32) {
        if (block.chainid == holesky) {
            // @DEPRECATED
            // https://docs.layerzero.network/v2/deployments/deployed-contracts
            return 40217;
        } else if (block.chainid == sepolia) {
            return 40161;
        }

        revert("LayerZeroDestinationEID not available for this chain");
    }

    function _getPaymaster() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x65d2dd7A66a2733a36559fE900A236280A05FBD6
            return 0x65d2dd7A66a2733a36559fE900A236280A05FBD6;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0
            return 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE
            return 0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE;
        }

        revert("Paymaster not available for this chain");
    }

    function _getCommunityMultisig() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x446d4d6b26815f9bA78B5D454E303315D586Cb2a
            return 0x446d4d6b26815f9bA78B5D454E303315D586Cb2a;
        } else if (block.chainid == ape) {
            // https://apescan.io/address/0xE417FD3b116eb604De2E14715DaeB099154E597B
            return 0xE417FD3b116eb604De2E14715DaeB099154E597B;
        }

        revert("CommunityMultisig not available for this chain");
    }

    function _getPauserMultisig() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x1ba8e3aA853F73ae8093E26B7B8F2520c3620Df4
            return 0x1ba8e3aA853F73ae8093E26B7B8F2520c3620Df4;
        } else if (block.chainid == ape) {
            // https://apescan.io/address/0x0B975bB578e9111977Bc75b667f3C18f96cD03E7
            return 0x0B975bB578e9111977Bc75b667f3C18f96cD03E7;
        }

        revert("PauserMultisig not available for this chain");
    }

    function _getOPSMultisig() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d
            return 0xC0896ab1A8cae8c2C1d27d011eb955Cca955580d;
        } else if (block.chainid == holesky) {
            // @DEPRECATED
            // https://holesky.etherscan.io/address/0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0
            return 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
        } else if (block.chainid == hoodi) {
            // https://hoodi.etherscan.io/address/0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE
            return 0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE;
        } else if (block.chainid == ape) {
            // https://apescan.io/address/0x36E3881Ff855c264045c22179b6fBc01430F97EC
            return 0x36E3881Ff855c264045c22179b6fBc01430F97EC;
        }

        revert("OPSMultisig not available for this chain");
    }

    function _getCarrotMultisig() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xE06A1ad7346Dfda7Ce9BCFba751DABFd754BAfAD
            return 0xE06A1ad7346Dfda7Ce9BCFba751DABFd754BAfAD;
        }

        revert("OPSMultisig not available for this chain");
    }

    function _getAeraVault() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x6c25aE178aC3466A63A552d4D6509c3d7385A0b8
            return 0x6c25aE178aC3466A63A552d4D6509c3d7385A0b8;
        }

        revert("AeraVault not available for this chain");
    }

    function _getAeraAssetRegistry() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0xc71C52425969286dAAd647e4088394C572d64fd9
            return 0xc71C52425969286dAAd647e4088394C572d64fd9;
        }

        revert("AeraAssetRegistry not available for this chain");
    }

    function _getAeraVaultHooks() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x933AD39feb35793B4d6B0A543db39b033Eb5D2C1
            return 0x933AD39feb35793B4d6B0A543db39b033Eb5D2C1;
        }

        revert("AeraVaultHooks not available for this chain");
    }

    function _getRevenueDepositor() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x21660F4681aD5B6039007f7006b5ab0EF9dE7882
            return 0x21660F4681aD5B6039007f7006b5ab0EF9dE7882;
        }

        revert("RevenueDepositor not available for this chain");
    }

    function _getL1RewardManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            // https://etherscan.io/address/0x157788cc028Ac6405bD406f2D1e0A8A22b3cf17b
            return 0x157788cc028Ac6405bD406f2D1e0A8A22b3cf17b;
        }

        revert("L1RewardManager not available for this chain");
    }

    function _getL2RewardsManager() internal view returns (address) {
        if (block.chainid == base) {
            // https://basescan.org/address/0xF9Dd335bF363b2E4ecFe3c94A86EBD7Dd3Dcf0e7
            return 0xF9Dd335bF363b2E4ecFe3c94A86EBD7Dd3Dcf0e7;
        }

        revert("L2RewardsManager not available for this chain");
    }
}
