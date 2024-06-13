// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { PufferL2Depositor } from "./PufferL2Depositor.sol";
import { IMigrator } from "./interface/IMigrator.sol";
import { IPufStakingPool } from "./interface/IPufStakingPool.sol";

/**
 * @title Puf token
 * @author Puffer Finance
 * @notice PufToken is a wrapper for ERC20 tokens
 * @custom:security-contact security@puffer.fi
 */
contract PufToken is IPufStakingPool, ERC20, ERC20Permit {
    using SafeERC20 for ERC20;

    /**
     * @notice EIP-712 type hash
     */
    bytes32 internal constant _MIGRATE_TYPEHASH = keccak256(
        "Migrate(address depositor,address migratorContract,address destination,address token,uint256 amount,uint256 signatureExpiry,uint256 nonce)"
    );

    /**
     * @notice Standard Token Decimals
     */
    uint256 internal constant _STANDARD_TOKEN_DECIMALS = 18;

    /**
     * @notice The underlying token decimals
     */
    uint256 internal immutable _TOKEN_DECIMALS;

    /**
     * @notice Puffer Token factory
     */
    PufferL2Depositor public immutable PUFFER_FACTORY;

    /**
     * @notice The underlying token
     */
    ERC20 public immutable TOKEN;

    constructor(address token, string memory tokenName, string memory tokenSymbol)
        ERC20(tokenName, tokenSymbol)
        ERC20Permit(tokenName)
    {
        // The Factory is the deployer of the contract
        PUFFER_FACTORY = PufferL2Depositor(msg.sender);
        TOKEN = ERC20(token);
        _TOKEN_DECIMALS = uint256(TOKEN.decimals());
    }

    /**
     * @dev Calls Puffer Factory to check if the system is paused
     */
    modifier whenNotPaused() {
        PUFFER_FACTORY.revertIfPaused();
        _;
    }

    /**
     * @dev Calls Puffer Factory to check if the system is paused
     */
    modifier onlyAllowedMigratorContract(address migrator) {
        if (!PUFFER_FACTORY.isAllowedMigrator(migrator)) {
            revert MigratorContractNotAllowed(migrator);
        }
        _;
    }

    /**
     * @dev Basic validation of the account and amount
     */
    modifier validateAddressAndAmount(address account, uint256 amount) {
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (account == address(0)) {
            revert InvalidAccount();
        }
        _;
    }

    /**
     * @notice Deposits the underlying token to receive pufToken to the `account`
     */
    function deposit(address account, uint256 amount)
        external
        whenNotPaused
        validateAddressAndAmount(account, amount)
    {
        TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        uint256 normalizedAmount = _normalizeAmount(amount);

        // Mint puffToken to the account
        _mint(account, normalizedAmount);

        // Using the original deposit amount in the event
        emit Deposited(msg.sender, account, amount);
    }

    /**
     * @notice Deposits the underlying token to receive pufToken to the `account`
     */
    function withdraw(address recipient, uint256 amount) external validateAddressAndAmount(recipient, amount) {
        _burn(msg.sender, amount);

        uint256 deNormalizedAmount = _denormalizeAmount(amount);

        // Send him the token
        TOKEN.safeTransfer(recipient, deNormalizedAmount);

        // Using the original deposit amount in the event (in this case it is denormalized amount)
        emit Withdrawn(msg.sender, recipient, deNormalizedAmount);
    }

    /**
     * @notice Migrates the `amount` of tokens using the allowlsited `migratorContract` to the `destination` address
     */
    function migrate(uint256 amount, address migratorContract, address destination)
        external
        onlyAllowedMigratorContract(migratorContract)
        validateAddressAndAmount(destination, amount)
        whenNotPaused
    {
        _migrate({ depositor: msg.sender, amount: amount, destination: destination, migratorContract: migratorContract });
    }

    /**
     * @notice Migrates the tokens using the allowlisted migrator contract using the EIP712 signature from the depositor
     */
    function migrateWithSignature(
        address depositor,
        address migratorContract,
        address destination,
        uint256 amount,
        uint256 signatureExpiry,
        bytes memory stakerSignature
    ) external onlyAllowedMigratorContract(migratorContract) whenNotPaused {
        if (block.timestamp >= signatureExpiry) {
            revert ExpiredSignature();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                _MIGRATE_TYPEHASH,
                depositor,
                migratorContract,
                destination,
                address(TOKEN),
                amount,
                signatureExpiry,
                _useNonce(depositor)
            )
        );

        if (!SignatureChecker.isValidSignatureNow(depositor, _hashTypedDataV4(structHash), stakerSignature)) {
            revert InvalidSignature();
        }

        _migrate({ depositor: depositor, amount: amount, destination: destination, migratorContract: migratorContract });
    }

    /**
     * @notice Transfers the Token from this contract using the migrator contract
     */
    function _migrate(address depositor, uint256 amount, address destination, address migratorContract) internal {
        _burn(depositor, amount);

        uint256 deNormalizedAmount = _denormalizeAmount(amount);

        emit Migrated({
            depositor: depositor,
            destination: destination,
            migratorContract: migratorContract,
            amount: amount
        });

        TOKEN.safeIncreaseAllowance(migratorContract, deNormalizedAmount);

        IMigrator(migratorContract).migrate({ depositor: depositor, destination: destination, amount: amount });
    }

    function _normalizeAmount(uint256 amount) internal view returns (uint256 normalizedAmount) {
        if (_TOKEN_DECIMALS > _STANDARD_TOKEN_DECIMALS) {
            return amount / (10 ** (_TOKEN_DECIMALS - _STANDARD_TOKEN_DECIMALS));
        } else if (_TOKEN_DECIMALS < _STANDARD_TOKEN_DECIMALS) {
            return amount * (10 ** (_STANDARD_TOKEN_DECIMALS - _TOKEN_DECIMALS));
        }
        return amount;
    }

    function _denormalizeAmount(uint256 amount) internal view returns (uint256 denormalizedAmount) {
        if (_TOKEN_DECIMALS > _STANDARD_TOKEN_DECIMALS) {
            return amount * (10 ** (_TOKEN_DECIMALS - _STANDARD_TOKEN_DECIMALS));
        } else if (_TOKEN_DECIMALS < _STANDARD_TOKEN_DECIMALS) {
            return amount / (10 ** (_STANDARD_TOKEN_DECIMALS - _TOKEN_DECIMALS));
        }
        return amount;
    }
}
