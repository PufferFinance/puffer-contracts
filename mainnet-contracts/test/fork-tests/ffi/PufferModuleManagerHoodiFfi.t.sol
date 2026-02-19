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
    address EIGEN_DA_REGISTRY_COORDINATOR_HOODI = 0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490; // TODO Change
    address EIGEN_DA_SERVICE_MANAGER = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b; // TODO Change
    address BEACON_CHAIN_STRATEGY = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
    address EIGEN_POD_MANAGER = 0xcd1442415Fc5C29Aa848A49d2e232720BE07976c;
    address DELAYED_WITHDRAWAL_ROUTER = 0x642c646053eaf2254f088e9019ACD73d9AE0FA32; // TODO Change
    address DELEGATION_MANAGER = 0x867837a9722C512e0862d8c2E15b8bE220E8b87d;

    // Puffer Hoodi deployment
    address PUFFER_SHARED_DEV_WALLET = 0xeeE554b5b2bF5FBc9730Ce33c6dc92828DA01BeE;
    address ACCESS_MANAGER_HOODI = 0x0950195AC9B310815698f5dDeD3BD32814f46EFD;
    address MODULE_BEACON_HOODI = 0x6899d0dE991458929b43e3DE4fC2d4A9ca7E4673;
    address PUFFER_PROTOCOL_HOODI = 0xa3eca8ef718538Fc2610899e95590B521D59a842;
    address PUFFER_MODULE_MANAGER = 0x26eEa064e7Ed6b52847f8153Cd466A7b01f2cB14;
    address PUFFER_MODULE_0_HOODI = 0xeaA758DC50180ac70Ec69A241f8a866e6e852905;
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
