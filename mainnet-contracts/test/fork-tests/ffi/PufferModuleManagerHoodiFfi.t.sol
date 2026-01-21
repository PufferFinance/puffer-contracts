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
    address PUFFER_SHARED_DEV_WALLET = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;
    address ACCESS_MANAGER_HOODI = 0x77D6694E1B6a86760036Febe78315363ccA402ae;
    address MODULE_BEACON_HOODI = 	0xE526d80Dc834371f11B64A491d8f654a46e86Fc9;
    address PUFFER_PROTOCOL_HOODI = 0x9D362e5CA054e03aa27327732b764F2104334942;
    address PUFFER_MODULE_MANAGER =  0xCf6265030F12ebd79541F8fD6bBb2AfB3359e5D1;
    address PUFFER_MODULE_0_HOODI = 0xE3Cf98C52E20794582E7Edc25cC9Da60C2E70135;
    // https://hoodi.eigenlayer.xyz/operator/0xe2c2dc296a0bff351f6bc3e98d37ea798e393e56 // TODO Change
    address RESTAKING_OPERATOR_CONTRACT = 0xe2c2dc296a0bFF351F6bC3e98D37ea798e393e56; // TODO Change
    address RESTAKING_OPERATOR_BEACON = 0xdfB311149d4d576c74d2ff5DBa22C332d727E7fC;
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
