// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import "./PufToken.sol";

contract PufferStakingPool is AccessManaged {
    using Address for address;

    struct Asset {
        address tokenAddress;
        address derivativeTokenAddress;
    }

    mapping(address => Asset) public allowlistedAssets;
    address[] public assetList;

    mapping(address migrator => bool isAllowed) public allowedMigrators;

    // Custom error definitions
    error Unauthorized();
    error AssetAlreadyAdded();
    error AssetNotAllowlisted();
    error InvalidMigratorContract();

    event AssetAdded(address indexed tokenAddress, address indexed derivativeTokenAddress);
    event Deposit(address indexed user, address indexed tokenAddress, uint256 amount);
    event Withdraw(address indexed user, address indexed tokenAddress, uint256 amount);
    event Migrated(address indexed user, address indexed tokenAddress, address destination, uint256 amount);
    event SetIsMigratorAllowed(address indexed migrator, bool isAllowed);

    constructor(address addressManager) AccessManaged(addressManager) { }

    function addAsset(address tokenAddress, string calldata name, string calldata symbol) external restricted {
        if (allowlistedAssets[tokenAddress].tokenAddress != address(0)) {
            revert AssetAlreadyAdded();
        }

        address derivativeToken = address(new PufToken(name, symbol, tokenAddress, address(this)));

        allowlistedAssets[tokenAddress] = Asset({ tokenAddress: tokenAddress, derivativeTokenAddress: derivativeToken });

        assetList.push(tokenAddress);

        emit AssetAdded(tokenAddress, derivativeToken);
    }

    function deposit(address tokenAddress, uint256 amount) external {
        Asset memory asset = allowlistedAssets[tokenAddress];
        if (asset.tokenAddress == address(0)) {
            revert AssetNotAllowlisted();
        }

        PufToken(asset.derivativeTokenAddress).depositFor(msg.sender, amount);
        emit Deposit(msg.sender, tokenAddress, amount);
    }

    function withdraw(address tokenAddress, uint256 amount) external {
        Asset memory asset = allowlistedAssets[tokenAddress];
        if (asset.tokenAddress == address(0)) {
            revert AssetNotAllowlisted();
        }

        PufToken(asset.derivativeTokenAddress).withdrawFor(msg.sender, amount);
        emit Withdraw(msg.sender, tokenAddress, amount);
    }

    function migrate(address tokenAddress, address destination, uint256 amount, address migratorAddress) external {
        Asset memory asset = allowlistedAssets[tokenAddress];
        if (asset.tokenAddress == address(0)) {
            revert AssetNotAllowlisted();
        }

        if (!allowedMigrators[migratorAddress]) {
            revert InvalidMigratorContract();
        }

        PufToken(asset.derivativeTokenAddress).migrateFor(msg.sender, migratorAddress, destination, amount);
        emit Migrated(msg.sender, tokenAddress, destination, amount);
    }

    /**
     * @dev Restricted to Puffer Multisig
     */
    function setMigrator(address migrator, bool allowed) external restricted {
        if (migrator == address(0)) {
            revert InvalidMigratorContract();
        }

        allowedMigrators[migrator] = allowed;
        emit SetIsMigratorAllowed(migrator, allowed);
    }
}
