// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { TEEType, TeeReportType, CloudType, WorkloadCollaterals } from "@automata-network/automata-tee-workload-measurement/interfaces/IWorkloadVerifier.sol";

contract WorkloadVerifierMock {
        function verifyAttestationAndGetMeasurementHash(
        TEEType teeType,
        TeeReportType teeReportType,
        CloudType cloudType,
        bytes calldata _teeAttestationReport,
        WorkloadCollaterals calldata _workloadReport
    ) external payable returns (bytes memory teeOutput, bytes32 measurementHash, bytes memory tpmExtraData) {
        // TODO
    }
}
