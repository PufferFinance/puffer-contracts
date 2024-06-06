// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

// import { Test } from "forge-std/Test.sol";
// import { console } from "forge-std/console.sol";

// contract AbiEncode is Test {
//     uint256 x = 1;
//     uint256 y = 2;
//     uint256 z = 3;
//     string name = "benjamin";
//     bytes pubKey =
//         hex"048289b999a1a6bc0cc6550ea018d03adee9bfeae6441e53e2e5eed22232a2b8f2d87cf1619c263971a6ada43f7310f37f473de7262ab63778fe3a859c68dc2e27";
//     bytes withdrawalCredentials = hex"010000000000000000000000deb250647aafbac89d11f5cc02d3069a938bd81c";
//     bytes signature =
//         hex"4c15c80ec83f5ebbee20f1be0cf1f7c1850179988442cba027152e01b79474592f2cd526fc8b2b2808b9c6afeaed642061aafa9b92ffcedc7cfbc1418bb9865719ef86c9de9f01bc166cf5f2ce392a70d5cd2017336c8817eaad129ad9ff5dd88eb3ecc26b0d21e04aba01c0bf303ed5e343e85104ea7a6e45514938158358825bf339fbd5116581218575551478e49c0aecfb1eb40c863c4401c44da2aa5634e335512915b38d77c7dc693ee8b9fa41f3bf9d939c1c5e382c010c42da237650c16a3ff4ac504376b215b1fc08f69a3dc0c3d0404f643e42e3078a70db5d61305c87e90ad39968b28e333e24b0887b0f01ace55d647805575fd96648c006abe3";

//     // function testReference() public {
//     //     bytes memory encoded = abi.encode(pubKey, withdrawalCredentials, signature);

//     //     console.logBytes(encoded);

//     //     bytes memory encodedx = abi.encode(pubKey);
//     //     bytes memory encodedy = abi.encode(withdrawalCredentials);
//     //     bytes memory encodedz = abi.encode(signature);

//     //     bytes memory encodedSplit = bytes.concat(encodedx, encodedy, encodedz);

//     //     emit log_named_bytes("original", encoded);

//     //     emit log_named_bytes("split", encodedSplit);

//     //     assertTrue(keccak256(encoded) == keccak256(encodedSplit), "no match");
//     // }

//     function testWithdrawalCreds() public {
//         bytes32 withdrawalCreds = bytes32(
//             bytes.concat(hex"010000000000000000000000", abi.encodePacked(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4))
//         );
//         // console.logBytes32(withdrawalCreds);
//     }

//     function testWithdrawalCreds2() public {
//         bytes32 withdrawalCreds =
//             bytes32(abi.encodePacked(bytes1(uint8(1)), bytes11(0), 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4));
//         // console.logBytes32(withdrawalCreds);
//     }
// }
