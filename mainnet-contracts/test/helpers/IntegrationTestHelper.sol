// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { PufferProtocolDeployment } from "script/DeploymentStructs.sol";
import { GuardianModule } from "../../src/GuardianModule.sol";
import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { IEnclaveVerifier } from "../../src/interface/IEnclaveVerifier.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract IntegrationTestHelper is Test {
    address DAO = 0xC4a2E012024d4ff28a4E2334F58D4Cc233EB1FE1;
    PufferProtocol public pufferProtocol;
    UpgradeableBeacon public beacon;
    PufferModuleManager public moduleManager;

    GuardianModule public guardianModule;

    AccessManager public accessManager;
    IEnclaveVerifier public verifier;

    bytes32 PUFFER_MODULE_0 = bytes32("PUFFER_MODULE_0");
    address PAYMASTER = 0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0;

    // custom block number
    function deployContractsHolesky(uint256 blockNumber) public virtual {
        // see foundry.toml for the rpc urls
        if (blockNumber == 0) {
            vm.createSelectFork(vm.rpcUrl("holesky"));
        } else {
            vm.createSelectFork(vm.rpcUrl("holesky"), blockNumber);
        }

        address[] memory guardians = new address[](1);
        guardians[0] = address(this);

        _deployAndLabel(guardians, 1);
    }

    // 'default' block number
    function deployContractsHolesky() public virtual {
        deployContractsHolesky(1_212_252);
    }

    function _deployAndLabel(address[] memory guardians, uint256 threshold) internal {
        // Deploy everything with one script
        (PufferProtocolDeployment memory pufferDeployment,) =
            new DeployEverything().run(guardians, threshold, PAYMASTER);

        pufferProtocol = PufferProtocol(payable(pufferDeployment.pufferProtocol));
        vm.label(address(pufferProtocol), "PufferProtocol");
        accessManager = AccessManager(pufferDeployment.accessManager);
        vm.label(address(accessManager), "AccessManager");
        verifier = IEnclaveVerifier(pufferDeployment.enclaveVerifier);
        vm.label(address(verifier), "EnclaveVerifier");
        guardianModule = GuardianModule(payable(pufferDeployment.guardianModule));
        vm.label(address(guardianModule), "GuardianModule");
        beacon = UpgradeableBeacon(pufferDeployment.beacon);
        vm.label(address(beacon), "PufferModuleBeacon");
        moduleManager = PufferModuleManager(payable(pufferDeployment.moduleManager));
        vm.label(address(moduleManager), "PufferModuleManager");
    }

    function getDepositData(bytes memory pubKey, bytes memory signature, bytes memory withdrawalCredentials)
        internal
        view
        returns (bytes32)
    {
        return this.reconstructDepositData(pubKey, signature, withdrawalCredentials);
    }

    function reconstructDepositData(
        bytes memory pubkey,
        bytes calldata signature,
        bytes calldata withdrawal_credentials
    ) public pure returns (bytes32) {
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])), sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );

        return sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkey_root, withdrawal_credentials)),
                sha256(abi.encodePacked(to_little_endian_64(uint64(32000000000)), bytes24(0), signature_root))
            )
        );
    }

    function to_little_endian_64(uint64 value) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }
}
