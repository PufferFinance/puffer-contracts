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

    // Helper Functions
    function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    }
}
