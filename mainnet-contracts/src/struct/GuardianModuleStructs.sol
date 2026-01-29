// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { TEEType, TeeReportType, CloudType } from "@automata-network/automata-tee-workload-measurement/lib/LibTEE.sol";
import { WorkloadCollaterals } from
    "@automata-network/automata-tee-workload-measurement/interfaces/IWorkloadVerifier.sol";

/**
 * @dev Tdx Registration Data
 */
struct TdxRegistrationData {
    TEEType teeType;
    TeeReportType teeReportType;
    CloudType cloudType;
    bytes teeAttestationReport;
    WorkloadCollaterals workloadCollaterals;
}

/**
 * @dev Golden Measurement Info
 */
struct GoldenMeasurementInfo {
    bool valid;
    TEEType teeType;
    CloudType cloudType;
    string tag; // e.g., "guardian-v1.0.0"
}

/**
 * @dev Enclave data
 * The guardian doesn't know the Secret Key of an enclave wallet
 */
struct GuardianData {
    bytes enclavePubKey;
    address enclaveAddress;
}
