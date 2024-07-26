// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import "eigenlayer/interfaces/IEigenPodManager.sol";
import "eigenlayer-test/mocks/EigenPodMock.sol";

contract EigenPodManagerMock is IEigenPodManager, Test {
    function slasher() external pure returns (ISlasher) { }

    function createPod() external returns (address) {
        return address(new EigenPodMock());
    }

    function addShares(address, uint256) external pure returns (uint256) {
        return 55;
    }

    function beaconChainETHStrategy() external pure returns (IStrategy) { }

    function eigenPodBeacon() external pure returns (IBeacon) {
        return IBeacon(address(99));
    }

    function ethPOS() external pure returns (IETHPOSDeposit) {
        return IETHPOSDeposit(address(99));
    }

    function getBlockRootAtTimestamp(uint64) external pure returns (bytes32) {
        return bytes32("asdf");
    }

    function maxPods() external pure returns (uint256) {
        return 100;
    }

    function numPods() external pure returns (uint256) {
        return 10;
    }

    function podOwnerShares(address) external pure returns (int256) {
        return 5;
    }

    /**
     * @notice the deneb hard fork timestamp used to determine which proof path to use for proving a withdrawal
     */
    function denebForkTimestamp() external view returns (uint64) { }

    /**
     * setting the deneb hard fork timestamp by the eigenPodManager owner
     * @dev this function is designed to be called twice.  Once, it is set to type(uint64).max
     * prior to the actual deneb fork timestamp being set, and then the second time it is set
     * to the actual deneb fork timestamp.
     */
    function setDenebForkTimestamp(uint64 newDenebForkTimestamp) external { }

    function recordBeaconChainETHBalanceUpdate(address podOwner, int256 sharesDelta) external { }
    function removeShares(address podOwner, uint256 shares) external { }
    function withdrawSharesAsTokens(address podOwner, address destination, uint256 shares) external { }

    function stake(bytes calldata, /*pubkey*/ bytes calldata, /*signature*/ bytes32 /*depositDataRoot*/ )
        external
        payable
    { }

    function restakeBeaconChainETH(address, /*podOwner*/ uint256 /*amount*/ ) external pure { }

    function recordBeaconChainETHBalanceUpdate(
        address, /*podOwner*/
        uint256, /*beaconChainETHStrategyIndex*/
        int256 /*sharesDelta*/
    ) external pure { }

    function withdrawRestakedBeaconChainETH(address, /*podOwner*/ address, /*recipient*/ uint256 /*amount*/ )
        external
        pure
    { }

    // function updateBeaconChainOracle(IBeaconChainOracle /*newBeaconChainOracle*/ ) external pure { }

    function ownerToPod(address /*podOwner*/ ) external view returns (IEigenPod) {
        // return IEigenPod(address(555));
        return IEigenPod(address(uint160(uint256(uint160(msg.sender)) + 1)));
    }

    function getPod(address podOwner) external pure returns (IEigenPod) {
        return IEigenPod(podOwner);
    }

    function getBeaconChainStateRoot(uint64 /*blockNumber*/ ) external pure returns (bytes32) {
        return bytes32(0);
    }

    function strategyManager() external pure returns (IStrategyManager) {
        return IStrategyManager(address(0));
    }

    function decrementWithdrawableRestakedExecutionLayerGwei(address podOwner, uint256 amountWei) external { }

    function incrementWithdrawableRestakedExecutionLayerGwei(address podOwner, uint256 amountWei) external { }

    function hasPod(address /*podOwner*/ ) external pure returns (bool) {
        return false;
    }

    function pause(uint256 /*newPausedStatus*/ ) external { }

    function pauseAll() external { }

    function paused() external pure returns (uint256) {
        return 0;
    }

    function paused(uint8 /*index*/ ) external pure returns (bool) {
        return false;
    }

    function setPauserRegistry(IPauserRegistry /*newPauserRegistry*/ ) external { }

    function pauserRegistry() external pure returns (IPauserRegistry) {
        return IPauserRegistry(address(0));
    }

    function unpause(uint256 /*newPausedStatus*/ ) external { }
}
