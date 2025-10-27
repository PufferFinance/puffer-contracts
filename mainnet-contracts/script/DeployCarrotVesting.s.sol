// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CarrotVesting } from "../src/CarrotVesting.sol";

/**
 * This script is used to deploy the CarrotVesting contract. This is done deploying the implementation and then deploying the proxy.
 * It requires the following arguments:
 * - CARROT: The address of the CARROT token
 * - PUFFER: The address of the PUFFER token
 * - OWNER: The address of the owner of the contract (This should be a multi-sig that then will call initializeVesting)
 *
 * Example:
 * forge script script/DeployCarrotVesting.s.sol:DeployCarrotVesting --rpc-url=$RPC_URL --private-key $PK --broadcast --sig "run(address,address,address)"  $CARROT $PUFFER $OWNER
 * Or using account instead of private key:
 * forge script script/DeployCarrotVesting.s.sol:DeployCarrotVesting --rpc-url=$RPC_URL --account puffer_deployer --broadcast --sig "run(address,address,address)"  $CARROT $PUFFER $OWNER
 *
 * 
 * deploy along with verification:
 * forge script script/DeployCarrotVesting.s.sol:DeployCarrotVesting -vvvv --rpc-url=$RPC_URL --private-key $PK  --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --sig "run(address,address,address)"  $CARROT $PUFFER $OWNER
 */
contract DeployCarrotVesting is Script {
    function run(
        address carrot, // CARROT token address, for impl constructor
        address puffer, // PUFFER token address, for impl constructor
        address owner // owner of the contract, for initialize
    ) public {
        vm.startBroadcast();

        CarrotVesting impl = new CarrotVesting(carrot, puffer);

        bytes memory data = abi.encodeCall(CarrotVesting.initialize, (owner));

        console.logBytes(data);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);

        vm.stopBroadcast();

        console.log("CarrotVesting deployed to:", address(proxy));
        console.log("CarrotVesting implementation:", address(impl));
        console.log("CarrotVesting owner:", owner);
        console.log("CarrotVesting carrot:", carrot);
        console.log("CarrotVesting puffer:", puffer);
    }
}
