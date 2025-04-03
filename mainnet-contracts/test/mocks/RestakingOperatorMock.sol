// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

contract RestakingOperatorMock {
    event CustomCalldataCall(address target, bytes customCalldata);
    event CallSetClaimerFor(address claimer);

    address public restakingOperatorController;

    modifier onlyRestakingOperatorController() {
        require(msg.sender == restakingOperatorController, "Only restaking operator controller can call this function");
        _;
    }

    constructor(address _restakingOperatorController) {
        restakingOperatorController = _restakingOperatorController;
    }

    function customCalldataCall(address target, bytes calldata customCalldata)
        external
        onlyRestakingOperatorController
    {
        emit CustomCalldataCall(target, customCalldata);
    }

    function callSetClaimerFor(address claimer) external onlyRestakingOperatorController {
        emit CallSetClaimerFor(claimer);
    }
}
