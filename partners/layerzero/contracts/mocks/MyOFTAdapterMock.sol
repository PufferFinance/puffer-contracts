// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

    import { PUFFERAdapter } from "../PUFFERAdapter.sol";

// @dev WARNING: This is for testing purposes only
contract MyOFTAdapterMock is PUFFERAdapter {
    constructor(address _token, address _lzEndpoint, address _delegate) PUFFERAdapter(_token, _lzEndpoint, _delegate) {}
}
