// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title Deployer Helper script
 * @notice Contains the addresses of the contracts that are already deployed
 */
abstract contract DeployerHelper is Script {
    // Chain IDs
    uint256 public mainnet = 1;
    uint256 public holesky = 17000;
    uint256 public binance = 56;
    uint256 public base = 8453;
    uint256 public sepolia = 11155111;
    uint256 public opSepolia = 11155420;

    function _getDeployer() internal returns (address) {
        (, address msgSender,) = vm.readCallers();
        console.log("Deployer:", block.chainid, msgSender);
        return msgSender;
    }

    function _getStETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        } else if (block.chainid == holesky) {
            return 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
        }

        revert("stETH not available for this chain");
    }

    function _getStETHStrategy() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x93c4b944D05dfe6df7645A86cd2206016c51564D;
        } else if (block.chainid == holesky) {
            return 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
        }

        revert("stETH strategy not available for this chain");
    }

    function _getEigenLayerStrategyManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;
        } else if (block.chainid == holesky) {
            return 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
        }

        revert("strategy manager not available for this chain");
    }

    function _getPufferOracle() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x0BE2aE0edbeBb517541DF217EF0074FC9a9e994f;
        } else if (block.chainid == holesky) {
            return 0x8e043ed3F06720615685D4978770Cd5C8fe90fe3;
        }

        revert("puffer oracle not available for this chain");
    }

    function _getEigenDelegationManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        } else if (block.chainid == holesky) {
            return 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
        }

        revert("eigen delegation manager not available for this chain");
    }

    function _getWETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        } else if (block.chainid == holesky) {
            return 0x1d181cBd1825e9eBC6AD966878D555A7215FF4F0;
        }

        revert("WETH not available for this chain");
    }

    function _getLidoWithdrawalQueue() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
        } else if (block.chainid == holesky) {
            return 0xc7cc160b58F8Bb0baC94b80847E2CF2800565C50;
        }

        revert("lido withdrawal queue not available for this chain");
    }

    function _getAccessManager() internal view returns (address) {
        if (block.chainid == base) {
            return 0x6f62c8647b7cD3830F21BF0741BAD6f4b838Cb37;
        } else if (block.chainid == mainnet) {
            return 0x8c1686069474410E6243425f4a10177a94EBEE11;
        } else if (block.chainid == holesky) {
            return 0x180a345906e42293dcAd5CCD9b0e1DB26aE0274e;
        } else if (block.chainid == binance) {
            return 0x8849e9eB8bb27c1916AfB17ee4dEcAd375916474;
        } else if (block.chainid == sepolia) {
            return 0xc98dFfD21F55f2eb2461E6cD7f8838DC33AEddDc;
        } else if (block.chainid == opSepolia) {
            return 0xccE1f605FdeeFA15b5708B87De3240196fEf0CA4;
        }

        revert("AccessManager not available for this chain");
    }

    function _getPufferVault() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        } else if (block.chainid == holesky) {
            return 0x9196830bB4c05504E0A8475A0aD566AceEB6BeC9;
        } else if (block.chainid == sepolia) {
            // PufferVaultMock
            return 0xd85D701A660a61D9737D05397612EF08be2cE62D;
        }

        revert("PufferVault not available for this chain");
    }

    function _getPufferModuleManager() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x9E1E4fCb49931df5743e659ad910d331735C3860;
        } else if (block.chainid == holesky) {
            return 0x20377c306451140119C9967Ba6D0158a05b4eD07;
        }

        revert("PufferModuleManager not available for this chain");
    }

    function _getValidatorTicket() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x7D26AD6F6BA9D6bA1de0218Ae5e20CD3a273a55A;
        } else if (block.chainid == holesky) {
            return 0xB028194785178a94Fe608994A4d5AD84c285A640;
        }

        revert("ValidatorTicket not available for this chain");
    }

    function _getPufferProtocol() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0xf7b6B32492c2e13799D921E84202450131bd238B;
        } else if (block.chainid == holesky) {
            return 0xE00c79408B9De5BaD2FDEbB1688997a68eC988CD;
        }

        revert("PufferProtocol not available for this chain");
    }

    function _getXPufETH() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0xD7D2802f6b19843ac4DfE25022771FD83b5A7464;
        } else if (block.chainid == base) {
            return 0x23dA5F2d509cb43A59d43C108a43eDf34510eff1;
        } else if (block.chainid == binance) {
            return 0x64274835D88F5c0215da8AADd9A5f2D2A2569381;
        } else if (block.chainid == sepolia) {
            return 0xc63b3a075269F67Dd0C4B21dedBed23E39A01aff;
        } else if (block.chainid == opSepolia) {
            return 0xCcCA977cC71a8c97518b9A9b134263e83389B338;
        }

        revert("XPufETH not available for this chain");
    }

    function _getLockbox() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0xF78461CF59683af98dBec13C81dd064f4d77De48;
        } else if (block.chainid == sepolia) {
            return 0xC89A39742AbA9944089DD06Cc1bc994793D68684;
        }

        revert("Lockbox not available for this chain");
    }

    function _getEverclear() internal view returns (address) {
        if (block.chainid == mainnet) {
            return 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;
        } else if (block.chainid == base) {
            return 0xB8448C6f7f7887D36DcA487370778e419e9ebE3F;
        } else if (block.chainid == binance) {
            return 0xCd401c10afa37d641d2F594852DA94C700e4F2CE;
        } else if (block.chainid == opSepolia) {
            return 0x8247ed6d0a344eeae4edBC7e44572F1B70ECA82A;
        } else if (block.chainid == sepolia) {
            return 0x445fbf9cCbaf7d557fd771d56937E94397f43965;
        }
        revert("Everclear not available for this chain");
    }
}
