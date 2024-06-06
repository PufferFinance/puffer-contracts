import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

// Values for proof #1 for NoRestakingStrategy.t.sol
const valuesProf1 = [
  ["0x328809Bc894f92807417D2dAD6b7C998c1aFdac6", "16080000000000000"],
  ["0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e", "16120000000000000"],
  ["0xea475d60c118d7058beF4bDd9c32bA51139a74e0", "16070000000000000"],
];

// Values for proof #2 for NoRestakingStrategy.t.sol
const valuesProof2 = [
  ["0x328809Bc894f92807417D2dAD6b7C998c1aFdac6", "26080000000000000"],
  ["0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e", "36120000000000000"],
  ["0xea475d60c118d7058beF4bDd9c32bA51139a74e0", "46070000000000000"],
];

// (2)
const tree = StandardMerkleTree.of(values, ["address", "uint256"]);

// (3)
console.log('Merkle Root:', tree.root);

// (4)
fs.writeFileSync("tree.json", JSON.stringify(tree.dump()));

console.log(tree.render());

// Get proofs
for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    console.log('Proof:', proof);
}