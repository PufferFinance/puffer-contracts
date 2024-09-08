// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { PufferL2Depositor } from "./PufferL2Depositor.sol";
import { IMigrator } from "./interface/IMigrator.sol";
import { IPufStakingPool } from "./interface/IPufStakingPool.sol";
import { Unauthorized, InvalidAmount } from "./Errors.sol";

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
        "Migrate(address depositor,address migratorContract,address destination,address token,uint256 amount,uint256 signatureExpiry,uint256 nonce,uint256 chainId)"
    );

    /**
     * @notice The underlying token decimals
     */
    uint8 internal immutable _TOKEN_DECIMALS;

    /**
     * @notice Puffer Token factory
     */
    PufferL2Depositor public immutable PUFFER_FACTORY;

    /**
     * @notice The underlying token
     */
    ERC20 public immutable TOKEN;

    /**
     * @notice The maximum deposit amount.
     * @dev Deposit cap is in wei
     */
    uint256 public totalDepositCap;

    constructor(address token, string memory tokenName, string memory tokenSymbol, uint256 depositCap)
        ERC20(tokenName, tokenSymbol)
        ERC20Permit(tokenName)
    {
        // The Factory is the deployer of the contract
        PUFFER_FACTORY = PufferL2Depositor(msg.sender);
        TOKEN = ERC20(token);
        _TOKEN_DECIMALS = TOKEN.decimals();
        totalDepositCap = depositCap;
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

    modifier onlyPufferFactory() {
        if (msg.sender != address(PUFFER_FACTORY)) {
            revert Unauthorized();
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
     * @inheritdoc IPufStakingPool
     */
    function deposit(address from, address account, uint256 amount) external whenNotPaused {
        _deposit(from, account, amount);
    }

    /**
     * @inheritdoc IPufStakingPool
     */
    function withdraw(address recipient, uint256 amount) external validateAddressAndAmount(recipient, amount) {
        _burn(msg.sender, amount);

        TOKEN.safeTransfer(recipient, amount);

        emit Withdrawn(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IPufStakingPool
     */
    function migrate(uint256 amount, address migratorContract, address destination)
        external
        onlyAllowedMigratorContract(migratorContract)
        whenNotPaused
    {
        _migrate({ depositor: msg.sender, amount: amount, destination: destination, migratorContract: migratorContract });
    }

    /**
     * @inheritdoc IPufStakingPool
     */
    // solhint-disable-next-line gas-calldata-parameters
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
                _useNonce(depositor),
                block.chainid
            )
        );

        if (!SignatureChecker.isValidSignatureNow(depositor, _hashTypedDataV4(structHash), stakerSignature)) {
            revert InvalidSignature();
        }

        _migrate({ depositor: depositor, amount: amount, destination: destination, migratorContract: migratorContract });
    }

    /**
     * @notice Sets the underlying token deposit cap
     */
    function setDepositCap(uint256 newDepositCap) external onlyPufferFactory {
        if (newDepositCap < totalSupply()) {
            revert InvalidAmount();
        }

        emit DepositCapChanged(totalDepositCap, newDepositCap);
        totalDepositCap = newDepositCap;
    }

    function _deposit(address depositor, address account, uint256 amount)
        internal
        validateAddressAndAmount(account, amount)
    {
        TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        if (totalSupply() + amount > totalDepositCap) {
            revert TotalDepositCapReached();
        }

        // Mint puffToken to the account
        _mint(account, amount);

        // If the user is depositng using the factory, we emit the `depositor` from the parameters
        if (msg.sender == address(PUFFER_FACTORY)) {
            emit Deposited(depositor, account, amount);
        } else {
            // If it is a direct deposit not coming from the depositor, we use msg.sender
            emit Deposited(msg.sender, account, amount);
        }
    }

    /**
     * @notice Transfers the Token from this contract using the migrator contract
     */
    function _migrate(address depositor, uint256 amount, address destination, address migratorContract)
        internal
        validateAddressAndAmount(destination, amount)
    {
        _burn(depositor, amount);

        emit Migrated({
            depositor: depositor,
            destination: destination,
            migratorContract: migratorContract,
            amount: amount
        });

        TOKEN.safeIncreaseAllowance(migratorContract, amount);

        IMigrator(migratorContract).migrate({ depositor: depositor, destination: destination, amount: amount });
    }

    function decimals() public view override returns (uint8 _decimals) {
        return _TOKEN_DECIMALS;
    }
}
