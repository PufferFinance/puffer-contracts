// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IXReceiver} from "interfaces/core/IXReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title L2RwardManager
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract L2RewardManager is IXReceiver {
    // The ERC20 token being distributed
    IERC20 public immutable XTOKEN;
    // The root of the Merkle tree
    bytes32 public immutable merkleRoot;
    // to track claimed tokens
    mapping(uint256 => bool) private claimed;

    constructor(address xToken, bytes32 _merkleRoot) {
        merkleRoot = _merkleRoot;
        XTOKEN = IERC20(xToken);
    }

    // Check if a token has been claimed
    function isClaimed(uint256 index) public view returns (bool) {
        return claimed[index];
    }

    /** @notice The receiver function as required by the IXReceiver interface.
     * @dev The Connext bridge contract will call this function.
     */
    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external returns (bytes memory) {
        // Check for the right token
        require(_asset == address(XTOKEN), "Wrong asset received");
        // Enforce a cost to update merkle on L2
        require(_amount > 0, "Must pay at least 1 wei");

        // Decode the _callData to get the BridgingParams
        // TODO get struct for BridgingParams
        string memory params = abi.decode(_callData, (BridgingParams));

        //TODO do something
    }


    function claimRewards(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        //TODO change to revert syntax
        require(!isClaimed(index), "L2RewardManager: Rewards already claimed.");
        // TODO Claim rewards

    }
}
