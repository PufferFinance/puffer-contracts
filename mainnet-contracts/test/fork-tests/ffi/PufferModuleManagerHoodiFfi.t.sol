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
contract PufferModuleManagerHoodiTestnetFFI is Test {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    uint256[] privKeys;

    // https://github.com/Layr-Labs/eigenlayer-contracts?tab=readme-ov-file#deployments
    address EIGEN_DA_REGISTRY_COORDINATOR_HOODI = 0xB5b76D561eeF36CD772890C94C6Bde8b895455e2;
    address EIGEN_DA_SERVICE_MANAGER = 0x3FF2204A567C15dC3731140B95362ABb4b17d8ED;
    address BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
    address EIGEN_POD_MANAGER = 0xcd1442415Fc5C29Aa848A49d2e232720BE07976c;
    address DELEGATION_MANAGER = 0x867837a9722C512e0862d8c2E15b8bE220E8b87d;

    // Puffer Hoodi deployment
    address PUFFER_SHARED_DEV_WALLET = 0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE;
    address ACCESS_MANAGER_HOODI = 0x519C59FeaD8D65A5a3Fa331634ce5E69508dD36d;
    address MODULE_BEACON_HOODI = 0xd8E4EC18c776E6d9391b0F386e653A246e986Eb9;
    address PUFFER_PROTOCOL_HOODI = 0x6ECcBAB07B8e592D9e5Ab9042EF2CacF1eff1155;
    address PUFFER_MODULE_MANAGER = 0x2E6a94456014B1b152fdCF5e047c793b1E36F3D4;
    address PUFFER_MODULE_0_HOODI = 0x1086349d358fa589641e8a7440d46E5EE8A683C5;
    // https://hoodi.eigenlayer.xyz/operator/0xe2c2dc296a0bff351f6bc3e98d37ea798e393e56 // TODO Change
    address RESTAKING_OPERATOR_CONTRACT = 0xe2c2dc296a0bFF351F6bC3e98D37ea798e393e56; // TODO Change
    address RESTAKING_OPERATOR_BEACON = 0x9f9aa46c3b98aDDc1eEef87De25f986024f7C6Bb;
    address REWARDS_COORDINATOR = 0x29e8572678e0c272350aa0b4B8f304E47EBcd5e7;

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
