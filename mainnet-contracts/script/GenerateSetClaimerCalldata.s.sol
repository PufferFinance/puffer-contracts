// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { PufferProtocol } from "../src/PufferProtocol.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { PufferModuleManager } from "../src/PufferModuleManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract CalldataGenerator is Script {

    address AERA_VAULT = 0x6c25aE178aC3466A63A552d4D6509c3d7385A0b8;
    address PUFFER_MODULE_MANAGER = 0x9E1E4fCb49931df5743e659ad910d331735C3860;

    function run(address pufferModuleManager) external {
        address[] memory noOps = new address[](7);
        address[] memory modules = new address[](98);

        // List of noOps 
        noOps[0] = 0x4d7c3fc856ab52753b91a6c9213adf013309dd25;
        noOps[1] = 0x175da1e44c8fbf124714a3bba5dc18a7e65664d6;
        noOps[2] = 0x73f23013c5a4c209de945cdc58595a4d53d23084;
        noOps[3] = 0x59639aeee35c4108923fd16e66055b347fbeadd2;
        noOps[4] = 0xdd6859450e80665db854022e85fb0ed2f0240cb9;
        noOps[5] = 0xe48e7102c03812dfa1fdf0bbe6dbba6dc70b0f33;
        noOps[6] = 0x8c81d590cc94ca2451c4bde24c598193da74a575;

        // List of modules
        modules[0] = 0xe60ca7abf24de99af64e7d9057659ae2dbc2eb2c;
        modules[1] = 0xf831b40e80ffd364b0a08619666ee09df3a3f73a;
        modules[2] = 0xf5d31b441b8f1c53c7c5beb80089fec228c531fb;
        modules[3] = 0xa4c78fdae426d16baa010acedeec87706ac3f76b;
        modules[4] = 0xbb43dcafa77fb5d1888a087ce6a30c287981c391;
        modules[5] = 0xbca580b952801236322734bb146f3e27894f736e;
        modules[6] = 0x48c09cad9d785e21210a4e84fcb0ff5a3a73c58d;
        modules[7] = 0x5fde1b2d371243edca74b77082d40e01c5f15b31;
        modules[8] = 0xc327e3152ef9784faf0190cfa2592ddea5455430;
        modules[9] = 0x4cee5738cc8cc1ff262034c4ddcf42675504afa9;
        modules[10] = 0x9afca71c47910fe300fe0419a621a29c79537337;
        modules[11] = 0x0c9e6af5ad0d4826d81b8d51c4f4c2044ad05763;
        modules[12] = 0xf66a37b7d6e99b9af3d835d1b33c80abe339915d;
        modules[13] = 0x2ab60aa450c7f16afd70f27a789833ebc638a9d0;
        modules[14] = 0xc6910530820b3b85053be0db2863f332d6f45792;
        modules[15] = 0x4d92687163dcfd582bb9e103e9086904901b55f8;
        modules[16] = 0xfbe7657e38fe774027978271603ec22d95c1eb54;
        modules[17] = 0xf22a3f429905f9faa2ebe5947fc2d58b6ecce440;
        modules[18] = 0x5a2b0b1a12af2b10c7d6a4ab612a667cb8ba278d;
        modules[19] = 0xfe80649dc2cb126dd10603be02f0d94afc364fc9;
        modules[20] = 0x2d8f1a00e3e768d679fa7bd6fe567faa70f726b2;
        modules[21] = 0x3000ca8ae328ae3996ee22c30b609d8e2b701599;
        modules[22] = 0x7822be4356b5e633bb8a445952c3d35fdb642986;
        modules[23] = 0xda2dcde31b020b6b6f8c02d2bf4821db22091750;
        modules[24] = 0x32eec068c4d0578b94169726890d5395d4647dc4;
        modules[25] = 0x70d8c06125145281710dd73de382b7c1938200ea;
        modules[26] = 0x55efc9f901a5ada996011276450f7320729223b0;
        modules[27] = 0xc1102180394132f19b6a50a158ec313ceffc4a3a;
        modules[28] = 0xf2d65e8093201c1645b822f9849fe375ea96056a;
        modules[29] = 0xb1ee744162e94cced7cab1d53d81664950e41c39;
        modules[30] = 0x6c6f3c472b5180df84efc7d65e81f7950d87a3f6;
        modules[31] = 0xca3964974bae15cb7d941b32712302b2b6c5d4ab;
        modules[32] = 0xb53d7bcbc30652ff35650246e3b591a064266b2b;
        modules[33] = 0xfa33e7d1bdfcb213e0cffa6e981fcad12d1638fa;
        modules[34] = 0x024d2378d80df4c6f49cb1f388d5a53d42c3e5fd;
        modules[35] = 0x2a89d38a2fd5b3d90c6f3813d23e0c2ed33cd7e2;
        modules[36] = 0x5905361a292c4582139a9ceaec1a71ea950d0677;
        modules[37] = 0x4cda1525b7d6577a59b6325201b3a68939da91d8;
        modules[38] = 0xb92ac33d59ec4f93787acc773ba6e26ef536749a;
        modules[39] = 0xdbe13208672a329ac8827d5752ba3e63253617aa;
        modules[40] = 0xd695b18944902c0a2c899aaa789e06d30e6b0c6c;
        modules[41] = 0x5fee3852b09fd5be7043ba5eca71e674ea80c3ff;
        modules[42] = 0x4e15b6331eadaa84750870e4e24b84780c88ff91;
        modules[43] = 0xd44cf40b14249811a50dcb6dbd809e94e421929e;
        modules[44] = 0xfe41129f707591fda06bfa30df467351d09f1806;
        modules[45] = 0xc360a5080719b3819531e6a9135d7062a9aa71a4;
        modules[46] = 0x1d5b496c6992e6ebcf7a38a4097017fad76457a8;
        modules[47] = 0x31710a5588cd7fadbf5002744ee433a3ec5bf75b;
        modules[48] = 0xb25cfe029b6dcd87d5d9ae333e587b7a4873ce29;
        modules[49] = 0xe859a34cdd097ac7e8167ad828ca9ad969925a6a;
        modules[50] = 0x97f51ba27bdee65bb87ffe38e4a88c9c938272f7;
        modules[51] = 0x56bfcc391b0be76a0fbd3c1b3c5e934680c92b0c;
        modules[52] = 0xef9c44b3b1a8101eba04e75c21f6ac67a4e0e626;
        modules[53] = 0xa709eb9a291304f99b830017523af8f1b9196fdf;
        modules[54] = 0x4b408f1ca8f09d0d9707ae5124238f451175d2ac;
        modules[55] = 0x141e6f34ff332e998f431199bedd6b0d0d10f860;
        modules[56] = 0xc7b096aa18541d4d9a3d617108f6935e65e5d069;
        modules[57] = 0x4bd8704cc263618e0620db01dbe30211de1dc72e;
        modules[58] = 0x09d4a923d904a86898898a79530190c40f5259e6;
        modules[59] = 0xc764054bded8ec0b71558e84615745f75cb6fd5c;
        modules[60] = 0xc63bf25a5f1f0ddaf87708087c8a1ea6de97ff23;
        modules[61] = 0x940c8dfad0c5e596d98e6acbf34d5edfbef11042;
        modules[62] = 0x311a752130c8e136dd1c6de8313d269b6105d319;
        modules[63] = 0x4f0f64afca99e253a89823c835ddb4d950cf6652;
        modules[64] = 0x0753edfd731698a1ac669c7c07602cbc3946bc5b;
        modules[65] = 0xfb31d482c5736a1bde326ac4621af0a142ce4046;
        modules[66] = 0x7b658386c82cd2752eb839f7a188cf048744686f;
        modules[67] = 0xad9b35123d1921a36a34ec806589e5d7c0777e72;
        modules[68] = 0xb2a550fcf3cfd3b16758b6efc7394aaf2ddf0601;
        modules[69] = 0x18d2df1cc6a44c32b52ffef413b15f14970f4002;
        modules[70] = 0xb21f8d9fc1d40ca63e190394fa8ad65cb4048d6f;
        modules[71] = 0xc2159dfff1c97c79678b40ae234eef8246ff6332;
        modules[72] = 0xca36526e36283a6420d740ff8d6b3b5a834c363e;
        modules[73] = 0x055057b3f45c308b7b45c1fdd5b68ae17d3f781f;
        modules[74] = 0x98968937aa45a038a33c9874aac8d054a1bb8746;
        modules[75] = 0xd9dc6ae799c8b6ab05e52f9afc11e2a9d7d51652;
        modules[76] = 0x32e0c22fce8996ccf63fad5aaa13b5556bec13ef;
        modules[77] = 0xccc08fe71dbec373c58053c58a3ccbec3a820369;
        modules[78] = 0x09f2180e5636a00f561853e39e0ac65dbfc79232;
        modules[79] = 0xc97474cdc5e92c6ff908cbcbacd310d57d0c73fe;
        modules[80] = 0x026503a3c936366d47527d9354d1c614365af921;
        modules[81] = 0xdd5a51b834bd1ee100d2d23eb99c669ad8c11362;
        modules[82] = 0xe141859cf4477f04c50c9c5f8c281204671c83cf;
        modules[83] = 0xdc717de5d799fca961daf88c12f61385ce898212;
        modules[84] = 0xc3fa8b2a4fd55b33ac09e3054b2dbc2a36ef7eac;
        modules[85] = 0xca4be9d9c8f038097cf0a8265da5202556960e52;
        modules[86] = 0x32d334624fc6c8e95a531f6304e5448830c53fde;
        modules[87] = 0x5e46cc19b371577b91336cca60d071d694a74c6d;
        modules[88] = 0x6537dd3904653ec917b78d58f4ceac0235504464;
        modules[89] = 0x044be5d76576e34b00c199833a043dd483f8485b;
        modules[90] = 0x3b181d9b973265f2e690082b7b7deee660257384;
        modules[91] = 0x5a2ea2b6d4ad7dab917e32ff45f85d1d5b4839ad;
        modules[92] = 0xa74034c7f7f4388e024f63b33626213181d6b984;
        modules[93] = 0xc48e944c94be1ec121d6cf68f79f2ef94ec44ca5;
        modules[94] = 0x45b3dca5af653c791ca49387f64b1e83cb96994c;
        modules[95] = 0x955d790417412ea7796676a16984c3a4ea5f830e;
        modules[96] = 0xd753548fc97aed8e3c30181bdb5f3a26836e4f4a;
        modules[97] = 0x13e0d6f093f4745b7f619a5cc03c434e435fb7c2;

        // Generate calldata for multicall
        bytes[] memory calldatas = new bytes[](modules.length);

        for (uint i = 0; i < modules.length; i++) {
            bytes memory callSetClaimerForCalldata =
                    abi.encodeWithSelector(PufferModuleManager.callSetClaimerFor.selector, modules[i], AERA_VAULT);
            

            calldatas[i] = abi.encodeWithSelector(AccessManager.execute.selector, PUFFER_MODULE_MANAGER, callSetClaimerForCalldata);
        }

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));
        console.logBytes(encodedMulticall);


        bytes[] memory calldatas2 = new bytes[](modules.length);
        for (uint i = 0; i < noOps.length; i++) {
            bytes memory callSetClaimerForCalldata =
                    abi.encodeWithSelector(PufferModuleManager.callSetClaimerFor.selector, noOps[i], AERA_VAULT);
            

            calldatas2[i] = abi.encodeWithSelector(AccessManager.execute.selector, PUFFER_MODULE_MANAGER, callSetClaimerForCalldata);
        }

        encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas2));
        console.logBytes(encodedMulticall);
    }
}
