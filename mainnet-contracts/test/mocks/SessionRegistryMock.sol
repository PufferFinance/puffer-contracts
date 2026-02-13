// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CVMSession, PublicIdentity} from "@automata-network/automata-tee-workload-measurement/interfaces/registries/ISessionRegistry.sol";

contract SessionRegistryMock {

    function getSession(bytes32 sessionId) external view returns (CVMSession memory session) {

    }

    function getSessionOwner(bytes32 sessionId) external view returns (bytes32 ownerFingerprint) {

    }

    function verifySessionSignature(
        bytes32 sessionId,
        PublicIdentity calldata sessionKey,
        bytes32 message,
        bytes calldata signature
    ) external view returns (bool valid) {

    }
}