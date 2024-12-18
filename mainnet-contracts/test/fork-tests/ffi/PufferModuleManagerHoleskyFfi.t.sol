// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { BN254 } from "src/interface/libraries/BN254.sol";

interface Weth {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

// PufferTestnet V1 deployment
contract PufferModuleManagerHoleskyTestnetFFI is Test {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    uint256[] privKeys;

    // https://github.com/Layr-Labs/eigenlayer-contracts?tab=readme-ov-file#deployments
    address EIGEN_DA_REGISTRY_COORDINATOR_HOLESKY = 0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490;
    address EIGEN_DA_SERVICE_MANAGER = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b;
    address BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
    address EIGEN_POD_MANAGER = 0x30770d7E3e71112d7A6b7259542D1f680a70e315;
    address DELAYED_WITHDRAWAL_ROUTER = 0x642c646053eaf2254f088e9019ACD73d9AE0FA32;
    address DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;

    // Puffer Holesky deployment
    address PUFFER_SHARED_DEV_WALLET = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
    address ACCESS_MANAGER_HOLESKY = 0xA6c916f85DAfeb6f726E03a1Ce8d08cf835138fF;
    address MODULE_BEACON_HOLESKY = 0x5B81A4579f466fB17af4d8CC0ED51256b94c61D4;
    address PUFFER_PROTOCOL_HOLESKY = 0x705E27D6A6A0c77081D32C07DbDE5A1E139D3F14;
    address PUFFER_MODULE_MANAGER = 0xe4695ab93163F91665Ce5b96527408336f070a71;
    address PUFFER_MODULE_0_HOLESKY = 0x0B0456ec773B7D89C9deCc38b682F98556CF9862;
    // https://holesky.eigenlayer.xyz/operator/0xe2c2dc296a0bff351f6bc3e98d37ea798e393e56
    address RESTAKING_OPERATOR_CONTRACT = 0xe2c2dc296a0bFF351F6bC3e98D37ea798e393e56;
    address RESTAKING_OPERATOR_BEACON = 0xa7DC88c059F57ADcE41070cEfEFd31F74649a261;
    address REWARDS_COORDINATOR = 0xAcc1fb458a1317E886dB376Fc8141540537E68fE;

    function _mulGo(uint256 x) internal returns (BN254.G2Point memory g2Point) {
        string[] memory inputs = new string[](3);
        inputs[0] = "./test/helpers/go2mul"; // lib/eigenlayer-middleware/test/ffi/go/g2mul.go binary
        inputs[1] = x.toString();

        inputs[2] = "1";
        bytes memory res = vm.ffi(inputs);
        g2Point.X[1] = abi.decode(res, (uint256));

        inputs[2] = "2";
        res = vm.ffi(inputs);
        g2Point.X[0] = abi.decode(res, (uint256));

        inputs[2] = "3";
        res = vm.ffi(inputs);
        g2Point.Y[1] = abi.decode(res, (uint256));

        inputs[2] = "4";
        res = vm.ffi(inputs);
        g2Point.Y[0] = abi.decode(res, (uint256));
    }
}
