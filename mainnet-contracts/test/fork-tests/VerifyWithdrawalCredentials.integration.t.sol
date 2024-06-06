// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { console } from "forge-std/console.sol";
import { ProofParsing } from "../helpers/ProofParsing.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { DeployEverything } from "script/DeployEverything.s.sol";
import { IEigenPod } from "eigenlayer/interfaces/IEigenPod.sol";
import { BeaconChainProofs } from "eigenlayer/libraries/BeaconChainProofs.sol";
import { PufferModuleManager } from "../../src/PufferModuleManager.sol";

interface IElOracle {
    function addTimestamp(uint256 timestamp) external;
    function timestampToBlockRoot(uint256 timestamp) external view returns (bytes32);
}

contract PufferModuleManagerIntegrationTest is ProofParsing {
    IElOracle elOracle = IElOracle(0x4C116BB629bff7A8373c2378bBd919f8349B8f25);
    address pufferModuleManager = 0xe4695ab93163F91665Ce5b96527408336f070a71;

    function setUp() public {
        // We create fork on 1269510 block, which has timestamp of 1712102016 (Tuesday, 2 April 2024 23:53:36)
        vm.createSelectFork(vm.rpcUrl("holesky"), 1269510);
    }

    function test_verityWithdrawalCredentials_123() public {
        setJSON("./test/data/1662066-proof.json");

        // Our validator https://holesky.beaconcha.in/validator/89E7DAC705610923C7FDB42A9B708B55BA5DDAC99B5D6A57765794BE2A42B7A94B2A4EC91253E08DDFB48CEB8573A978#deposits
        // timestamp of the https://holesky.beaconcha.in/slot/1348714
        // Deposit to beacon chain happened in slot 1348714, timestamp of that slot is 1712086968 (Tuesday, 2 April 2024 19:42:48)
        uint256 timestamp = 1712086968;

        // We first need to add that timestamp to the oracle
        elOracle.addTimestamp(timestamp);

        // Assert that it got updated
        assertEq(
            elOracle.timestampToBlockRoot(timestamp),
            hex"a45fd04b12349e8a73fefd478ecc3198e34b679b43b93ee24697aeeffcf5ee18",
            "root"
        );

        uint64 oracleTimestamp = uint64(timestamp);
        uint40[] memory validatorIndices = new uint40[](1);
        validatorIndices[0] = 1662066;

        BeaconChainProofs.StateRootProof memory stateRootProofStruct = _getStateRootProof();

        bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = getValidatorFields();

        bytes[] memory validatorFieldsProofs = new bytes[](1);
        validatorFieldsProofs[0] = abi.encodePacked(getWithdrawalCredentialProof());

        vm.startPrank(0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0); // DAO

        bytes memory moduleManagerCallData = abi.encodeCall(
            PufferModuleManager.callVerifyWithdrawalCredentials,
            (
                bytes32("PUFFER_MODULE_0"),
                oracleTimestamp,
                stateRootProofStruct,
                validatorIndices,
                validatorFieldsProofs,
                validatorFields
            )
        );

        console.log("Calling ModuleManager.verifyWithdrawalCredentials");
        // console.logBytes(moduleManagerCallData);

        vm.expectEmit(true, true, true, true);
        emit IEigenPod.ValidatorRestaked(1662066);
        (bool s,) = address(pufferModuleManager).call(moduleManagerCallData);
        assertEq(s, true, "ModuleManager.verifyWithdrawalCredentials");
    }

    // Helper Functions
    function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    }
}
