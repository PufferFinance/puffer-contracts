// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    TEEType,
    TeeReportType,
    CloudType,
    WorkloadCollaterals
} from "@automata-network/automata-tee-workload-measurement/interfaces/IWorkloadVerifier.sol";

contract WorkloadVerifierMock {
    bytes32 public mockMeasurementHash;

    function verifyAttestationAndGetMeasurementHash(
        TEEType,
        TeeReportType,
        CloudType,
        bytes calldata _teeAttestationReport,
        WorkloadCollaterals calldata
    ) external payable returns (bytes memory teeOutput, bytes32 measurementHash, bytes memory tpmExtraData) {
        return (hex"", mockMeasurementHash, _teeAttestationReport);
    }

    function setMeasurementHash(bytes32 _measurementHash) external {
        mockMeasurementHash = _measurementHash;
    }
}
