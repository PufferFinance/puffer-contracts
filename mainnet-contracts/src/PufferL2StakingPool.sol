// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

// import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
// import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
// import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
// import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
// import { IWETH } from "./interface/IWETH.sol";
// import { IMigrator } from "./interface/IMigrator.sol";
// import { Permit } from "./structs/Permit.sol";

// /**
//  * @title Puffer L2 Staking Pool
//  * @author Puffer Finance
//  * @notice PufferL2StakingPool
//  * @custom:security-contact security@puffer.fi
//  */
// contract PufferL2StakingPool is AccessManaged, EIP712, Nonces {
//     using SafeERC20 for IERC20;

//     event SetIsTokenAllowed(address indexed token, bool isAllowed);
//     event SetIsMigratorAllowed(address indexed migrator, bool isAllowed);
//     event Deposited(address indexed depositor, address indexed token, uint256 amount);
//     event Withdrawn(address indexed depositor, address indexed token, uint256 amount);
//     event Migrated(
//         address indexed depositor,
//         address[] tokens,
//         address indexed destination,
//         address indexed migratorContract,
//         uint256[] amounts
//     );

//     error InvalidTokenAmount(address token);
//     error InvalidAccount();
//     error InvalidAmount();
//     error TokenNotAllowed();
//     error ExpiredSignature();
//     error EmptyTokenArray();
//     error DuplicateToken();
//     error InvalidSignature();
//     error MigratorNotAllowed();

//     /**
//      * @notice EIP-712 type hash
//      */
//     bytes32 internal constant _MIGRATE_TYPEHASH = keccak256(
//         "Migrate(address depositor,address migratorContract,address destination,address[] tokens,uint256 signatureExpiry,uint256 nonce)"
//     );

//     /**
//      * @notice WETH
//      */
//     address public immutable WETH;

//     /**
//      * @notice Token Allow List
//      */
//     mapping(address token => bool allowed) public tokenAllowlist;

//     /**
//      * @notice Token balances for the account
//      */
//     mapping(address token => mapping(address account => uint256 amount)) public balances;

//     /**
//      * @notice Allowed migrator contracts
//      */
//     mapping(address migrator => bool isAllowed) public allowedMigrators;

//     constructor(address accessManager, address[] memory allowedTokens, address weth)
//         AccessManaged(accessManager)
//         EIP712("PufferL2StakingPool", "1")
//     {
//         require(accessManager != address(0));
//         require(weth != address(0));

//         WETH = weth;

//         for (uint256 i = 0; i < allowedTokens.length; ++i) {
//             _setTokenAllowed(allowedTokens[i], true);
//         }
//     }

//     /**
//      * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
//      */
//     function depositFor(address token, address account, Permit calldata permitData) external restricted {
//         if (permitData.amount == 0) {
//             revert InvalidAmount();
//         }
//         if (account == address(0)) {
//             revert InvalidAccount();
//         }
//         if (!tokenAllowlist[token]) {
//             revert TokenNotAllowed();
//         }

//         try ERC20Permit(address(token)).permit({
//             owner: msg.sender,
//             spender: address(this),
//             value: permitData.amount,
//             deadline: permitData.deadline,
//             v: permitData.v,
//             s: permitData.s,
//             r: permitData.r
//         }) { } catch { }

//         balances[token][account] += permitData.amount;

//         emit Deposited(account, token, permitData.amount);

//         // We always take tokens from `msg.sender`. It doesn't matter if token.permit reverts/is success
//         // This will revert if the `msg.sender` didn't approve tokens to this contract.
//         IERC20(token).safeTransferFrom(msg.sender, address(this), permitData.amount);
//     }

//     /**
//      * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
//      */
//     function depositETHFor(address account) external payable restricted {
//         // If WETH is not allowed, don't accept native ETH deposits
//         if (!tokenAllowlist[WETH]) {
//             revert TokenNotAllowed();
//         }
//         if (msg.value == 0) {
//             revert InvalidAmount();
//         }
//         if (account == address(0)) {
//             revert InvalidAccount();
//         }

//         balances[WETH][account] += msg.value;
//         emit Deposited(account, WETH, msg.value);

//         IWETH(WETH).deposit{ value: msg.value }();
//     }

//     /**
//      * @notice Withdraws the amount:`amount` `token` from the staking contract
//      */
//     function withdraw(address token, uint256 amount) external {
//         if (amount == 0) {
//             revert InvalidAmount();
//         }

//         balances[token][msg.sender] -= amount;
//         emit Withdrawn(msg.sender, token, amount);

//         IERC20(token).safeTransfer(msg.sender, amount);
//     }

//     /**
//      * @notice Migrates the tokens using the allowlisted migrator contract
//      * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
//      */
//     function migrate(address[] calldata tokens, address migratorContract, address destination) external restricted {
//         _migrate({ depositor: msg.sender, destination: destination, migratorContract: migratorContract, tokens: tokens });
//     }

//     /**
//      * @notice Migrates the tokens using the allowlisted migrator contract using the EIP712 signature from the depositor
//      * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
//      */
//     function migrateWithSig(
//         address depositor,
//         address[] calldata tokens,
//         address migratorContract,
//         address destination,
//         uint256 signatureExpiry,
//         bytes memory stakerSignature
//     ) external restricted {
//         if (block.timestamp >= signatureExpiry) {
//             revert ExpiredSignature();
//         }

//         bytes32 structHash = keccak256(
//             abi.encode(
//                 _MIGRATE_TYPEHASH,
//                 depositor,
//                 migratorContract,
//                 destination,
//                 // The array values are encoded as the keccak256 hash of the concatenated encodeData of their contents
//                 // Ref: https://eips.ethereum.org/EIPS/eip-712#definition-of-encodedata
//                 keccak256(abi.encodePacked(tokens)),
//                 signatureExpiry,
//                 _useNonce(depositor)
//             )
//         );

//         if (!SignatureChecker.isValidSignatureNow(depositor, _hashTypedDataV4(structHash), stakerSignature)) {
//             revert InvalidSignature();
//         }

//         _migrate({ depositor: depositor, destination: destination, migratorContract: migratorContract, tokens: tokens });
//     }

//     /**
//      * @dev Restricted to Puffer Multisig
//      */
//     function setTokenAllowed(address token, bool allowed) external restricted {
//         _setTokenAllowed(token, allowed);
//     }

//     /**
//      * @dev Restricted to Puffer Multisig
//      */
//     function setMigrator(address migrator, bool allowed) external restricted {
//         require(migrator != address(0));
//         allowedMigrators[migrator] = allowed;
//         emit SetIsMigratorAllowed(migrator, allowed);
//     }

//     function _migrate(address depositor, address destination, address migratorContract, address[] calldata tokens)
//         internal
//     {
//         if (!allowedMigrators[migratorContract]) {
//             revert MigratorNotAllowed();
//         }
//         if (tokens.length == 0) {
//             revert EmptyTokenArray();
//         }

//         uint256[] memory amounts = new uint256[](tokens.length);

//         for (uint256 i = 0; i < tokens.length; ++i) {
//             amounts[i] = balances[tokens[i]][depositor];
//             balances[tokens[i]][depositor] = 0;

//             // if the balances has been already set to zero, `tokens` contains duplicates, or the user provided token with 0 amount
//             if (amounts[i] == 0) {
//                 revert InvalidTokenAmount(tokens[i]);
//             }

//             IERC20(tokens[i]).safeIncreaseAllowance(migratorContract, amounts[i]);
//         }

//         emit Migrated({
//             depositor: depositor,
//             tokens: tokens,
//             destination: destination,
//             migratorContract: migratorContract,
//             amounts: amounts
//         });

//         IMigrator(migratorContract).migrate({
//             depositor: depositor,
//             tokens: tokens,
//             destination: destination,
//             amounts: amounts
//         });
//     }

//     function _setTokenAllowed(address token, bool allowed) internal {
//         require(token != address(0));
//         tokenAllowlist[token] = allowed;
//         emit SetIsTokenAllowed(token, allowed);
//     }
// }
