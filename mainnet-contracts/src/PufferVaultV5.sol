// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferVaultStorage } from "./PufferVaultStorage.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { IStETH } from "./interface/Lido/IStETH.sol";
import { ILidoWithdrawalQueue } from "./interface/Lido/ILidoWithdrawalQueue.sol";
import { IWETH } from "./interface/Other/IWETH.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { IPufferVaultV5 } from "./interface/IPufferVaultV5.sol";
import { IPufferOracleV2 } from "./interface/IPufferOracleV2.sol";
import { IPufferRevenueDepositor } from "./interface/IPufferRevenueDepositor.sol";

/**
 * @title PufferVaultV5
 * @dev Implementation of the PufferVault version 5.
 * @custom:security-contact security@puffer.fi
 */
contract PufferVaultV5 is
    IPufferVaultV5,
    IERC721Receiver,
    PufferVaultStorage,
    AccessManagedUpgradeable,
    ERC20PermitUpgradeable,
    ERC4626Upgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for address;
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using Math for uint256;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;
    IStETH internal immutable _ST_ETH;
    ILidoWithdrawalQueue internal immutable _LIDO_WITHDRAWAL_QUEUE;
    IWETH internal immutable _WETH;
    IPufferOracleV2 public immutable PUFFER_ORACLE;
    IPufferRevenueDepositor public immutable RESTAKING_REWARDS_DEPOSITOR;

    constructor(
        IStETH stETH,
        ILidoWithdrawalQueue lidoWithdrawalQueue,
        IWETH weth,
        IPufferOracleV2 pufferOracle,
        IPufferRevenueDepositor revenueDepositor
    ) {
        _ST_ETH = stETH;
        _LIDO_WITHDRAWAL_QUEUE = lidoWithdrawalQueue;
        _WETH = weth;
        PUFFER_ORACLE = pufferOracle;
        RESTAKING_REWARDS_DEPOSITOR = revenueDepositor;
        _disableInitializers();
    }

    /**
     * @notice Accept ETH from anywhere
     */
    receive() external payable virtual { }

    /**
     * @notice Initializes the PufferVaultV5 contract
     * @dev This function is only used for Unit Tests, we will not use it in mainnet
     */
    // nosemgrep tin-unprotected-initialize
    function initialize(address accessManager) public initializer {
        __AccessManaged_init(accessManager);
        __ERC20Permit_init("pufETH");
        __ERC4626_init(_WETH);
        __ERC20_init("pufETH", "pufETH");
        _setExitFeeBasisPoints(100); // 1%
    }

    modifier markDeposit() virtual {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            tstore(_DEPOSIT_TRACKER_LOCATION, 1) // Store `1` in the deposit tracker location
        }
        _;
    }

    modifier revertIfDeposited() virtual {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            // If the deposit tracker location is set to `1`, revert with `DepositAndWithdrawalForbidden()`
            if tload(_DEPOSIT_TRACKER_LOCATION) {
                mstore(0x00, 0x39b79d11) // Store the error signature `0x39b79d11` for `error DepositAndWithdrawalForbidden()` in memory.
                revert(0x1c, 0x04) // Revert by returning those 4 bytes. `revert DepositAndWithdrawalForbidden()`
            }
        }
        _;
    }

    /**
     * @dev See {IERC4626-totalAssets}.
     * pufETH, the shares of the vault, will be backed primarily by the WETH asset.
     * However, at any point in time, the full backings may be a combination of stETH, WETH, and ETH.
     * `totalAssets()` is calculated by summing the following:
     * + WETH held in the vault contract
     * + ETH  held in the vault contract
     * + PUFFER_ORACLE.getLockedEthAmount(), which is the oracle-reported Puffer validator ETH locked in the Beacon chain
     * + getTotalRewardMintAmount(), which is the total amount of rewards minted
     * - getTotalRewardDepositAmount(), which is the total amount of rewards deposited to the Vault
     * - RESTAKING_REWARDS_DEPOSITOR.getPendingDistributionAmount(), which is the total amount of rewards pending distribution
     * - callvalue(), which is the amount of ETH deposited by the caller in the transaction, it will be non zero only when the caller is depositing ETH
     *
     * NOTE on the native ETH deposits:
     * When dealing with NATIVE ETH deposits, we need to deduct callvalue from the balance.
     * The contract calculates the amount of shares(pufETH) to mint based on the total assets.
     * When a user sends ETH, the msg.value is immediately added to address(this).balance.
     * Since address(this.balance)` is used in calculating `totalAssets()`, we must deduct the `callvalue()` from the balance to prevent the user from minting excess shares.
     * `msg.value` cannot be accessed from a view function, so we use assembly to get the callvalue.
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 callValue;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            callValue := callvalue()
        }
        return _ST_ETH.balanceOf(address(this)) + getPendingLidoETHAmount() + _WETH.balanceOf(address(this))
            + (address(this).balance - callValue) + PUFFER_ORACLE.getLockedEthAmount() + getTotalRewardMintAmount()
            - getTotalRewardDepositAmount() - RESTAKING_REWARDS_DEPOSITOR.getPendingDistributionAmount();
    }

    /**
     * @notice Deposits native ETH into the Puffer Vault
     * @param receiver The recipient of pufETH tokens
     * @return shares The amount of pufETH received from the deposit
     *
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function depositETH(address receiver) public payable virtual markDeposit restricted returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (msg.value > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, msg.value, maxAssets);
        }

        uint256 shares = previewDeposit(msg.value);
        _mint(receiver, shares);
        emit Deposit(_msgSender(), receiver, msg.value, shares);

        return shares;
    }

    /**
     * @notice Deposits stETH into the Puffer Vault
     * @param stETHSharesAmount The shares amount of stETH to deposit
     * @param receiver The recipient of pufETH tokens
     * @return shares The amount of pufETH received from the deposit
     *
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function depositStETH(uint256 stETHSharesAmount, address receiver)
        public
        virtual
        markDeposit
        restricted
        returns (uint256)
    {
        uint256 maxAssets = maxDeposit(receiver);

        // Get the amount of assets (stETH) that corresponds to `stETHSharesAmount` so that we can use it in our calculation
        uint256 assets = _ST_ETH.getPooledEthByShares(stETHSharesAmount);

        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        // Transfer the exact number of stETH shares from the user to the vault
        _ST_ETH.transferSharesFrom({ _sender: msg.sender, _recipient: address(this), _sharesAmount: stETHSharesAmount });
        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /**
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        markDeposit
        restricted
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /**
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function mint(uint256 shares, address receiver) public virtual override markDeposit restricted returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Mints pufETH rewards for the L1RewardManager contract and returns the exchange rate.
     *
     * @dev Restricted to L1RewardManager
     */
    function mintRewards(uint256 rewardsAmount)
        external
        restricted
        returns (uint256 ethToPufETHRate, uint256 pufETHAmount)
    {
        ethToPufETHRate = convertToShares(1 ether);
        // calculate the shares using this formula since calling convertToShares again is costly
        pufETHAmount = ethToPufETHRate.mulDiv(rewardsAmount, 1 ether, Math.Rounding.Floor);

        VaultStorage storage $ = _getPufferVaultStorage();

        uint256 previousRewardsAmount = $.totalRewardMintAmount;
        uint256 newTotalRewardsAmount = previousRewardsAmount + rewardsAmount;
        $.totalRewardMintAmount = newTotalRewardsAmount;

        emit UpdatedTotalRewardsAmount(previousRewardsAmount, newTotalRewardsAmount, 0);

        // msg.sender is the L1RewardManager contract
        _mint(msg.sender, pufETHAmount);

        return (ethToPufETHRate, pufETHAmount);
    }

    /**
     * @notice Deposits the rewards amount to the vault and updates the total reward deposit amount.
     *
     * @dev Restricted to PufferModuleManager
     */
    function depositRewards() external payable restricted {
        VaultStorage storage $ = _getPufferVaultStorage();
        uint256 previousRewardsAmount = $.totalRewardDepositAmount;
        uint256 newTotalRewardsAmount = previousRewardsAmount + msg.value;
        $.totalRewardDepositAmount = newTotalRewardsAmount;

        emit UpdatedTotalRewardsAmount(previousRewardsAmount, newTotalRewardsAmount, msg.value);
    }

    /**
     * @notice Reverts the `mintRewards` action.
     *
     * @dev Restricted to L1RewardManager
     */
    function revertMintRewards(uint256 pufETHAmount, uint256 ethAmount) external restricted {
        VaultStorage storage $ = _getPufferVaultStorage();

        uint256 previousMintAmount = $.totalRewardMintAmount;
        // nosemgrep basic-arithmetic-underflow
        uint256 newMintAmount = previousMintAmount - ethAmount;
        $.totalRewardMintAmount = newMintAmount;

        emit UpdatedTotalRewardsAmount(previousMintAmount, newMintAmount, 0);

        // msg.sender is the L1RewardManager contract
        _burn(msg.sender, pufETHAmount);
    }

    /**
     * @notice Withdrawals WETH assets from the vault, burning the `owner`'s (pufETH) shares.
     * The caller of this function does not have to be the `owner` if the `owner` has approved the caller to spend their pufETH.
     * Copied the original ERC4626 code back to override `PufferVault` + wrap ETH logic
     * @param assets The amount of assets (WETH) to withdraw
     * @param receiver The address to receive the assets (WETH)
     * @param owner The address of the owner for which the shares (pufETH) are burned.
     * @return shares The amount of shares (pufETH) burned
     *
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        revertIfDeposited
        restricted
        returns (uint256)
    {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        _wrapETH(assets);

        uint256 shares = previewWithdraw(assets);
        _withdraw({ caller: _msgSender(), receiver: receiver, owner: owner, assets: assets, shares: shares });

        return shares;
    }

    /**
     * @notice Redeems (pufETH) `shares` to receive (WETH) assets from the vault, burning the `owner`'s (pufETH) `shares`.
     * The caller of this function does not have to be the `owner` if the `owner` has approved the caller to spend their pufETH.
     * Copied the original ERC4626 code back to override `PufferVault` + wrap ETH logic
     * @param shares The amount of shares (pufETH) to withdraw
     * @param receiver The address to receive the assets (WETH)
     * @param owner The address of the owner for which the shares (pufETH) are burned.
     * @return assets The amount of assets (WETH) redeemed
     *
     * @dev Restricted in this context is like `whenNotPaused` modifier from Pausable.sol
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        revertIfDeposited
        restricted
        returns (uint256)
    {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);

        _wrapETH(assets);

        _withdraw({ caller: _msgSender(), receiver: receiver, owner: owner, assets: assets, shares: shares });

        return assets;
    }

    /**
     * @notice Initiates ETH withdrawals from Lido
     * @param amounts An array of stETH amounts to queue
     * @return requestIds An array of request IDs for the withdrawals
     *
     * @dev Restricted to Operations Multisig
     */
    function initiateETHWithdrawalsFromLido(uint256[] calldata amounts)
        external
        virtual
        restricted
        returns (uint256[] memory requestIds)
    {
        require(amounts.length != 0);
        VaultStorage storage $ = _getPufferVaultStorage();

        uint256 lockedAmount;
        for (uint256 i = 0; i < amounts.length; ++i) {
            lockedAmount += amounts[i];
        }
        $.lidoLockedETH += lockedAmount;

        SafeERC20.safeIncreaseAllowance(_ST_ETH, address(_LIDO_WITHDRAWAL_QUEUE), lockedAmount);
        requestIds = _LIDO_WITHDRAWAL_QUEUE.requestWithdrawals(amounts, address(this));

        // nosemgrep array-length-outside-loop
        for (uint256 i = 0; i < requestIds.length; ++i) {
            $.lidoWithdrawalAmounts.set(requestIds[i], amounts[i]);
        }
        emit RequestedWithdrawals(requestIds);
        return requestIds;
    }

    /**
     * @notice Claims ETH withdrawals from Lido
     * @param requestIds An array of request IDs for the withdrawals
     *
     * @dev Restricted to Operations Multisig
     */
    function claimWithdrawalsFromLido(uint256[] calldata requestIds) external virtual restricted {
        require(requestIds.length != 0);
        VaultStorage storage $ = _getPufferVaultStorage();

        // ETH balance before the claim
        uint256 balanceBefore = address(this).balance;

        uint256 expectedWithdrawal = 0;

        for (uint256 i = 0; i < requestIds.length; ++i) {
            // .get reverts if requestId is not present
            expectedWithdrawal += $.lidoWithdrawalAmounts.get(requestIds[i]);
            $.lidoWithdrawalAmounts.remove(requestIds[i]);

            // slither-disable-next-line calls-loop
            _LIDO_WITHDRAWAL_QUEUE.claimWithdrawal(requestIds[i]);
        }

        // ETH balance after the claim
        uint256 balanceAfter = address(this).balance;
        uint256 actualWithdrawal = balanceAfter - balanceBefore;
        // Deduct from the locked amount the expected amount
        // nosemgrep basic-arithmetic-underflow
        $.lidoLockedETH -= expectedWithdrawal;

        emit ClaimedWithdrawals(requestIds);
        emit LidoWithdrawal(expectedWithdrawal, actualWithdrawal);
    }

    /**
     * @notice Transfers ETH to a specified address.
     * @dev It is used to transfer ETH to PufferModules to fund Puffer validators.
     * @param to The address of the PufferModule to transfer ETH to
     * @param ethAmount The amount of ETH to transfer
     *
     * @dev Restricted to PufferProtocol|PufferWithdrawalManager smart contracts
     */
    function transferETH(address to, uint256 ethAmount) external restricted {
        // Our Vault holds ETH & WETH
        // If we don't have enough ETH for the transfer, unwrap WETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance < ethAmount) {
            // Reverts if no WETH to unwrap
            // nosemgrep basic-arithmetic-underflow
            _WETH.withdraw(ethAmount - ethBalance);
        }

        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = to.call{ value: ethAmount }("");

        if (!success) {
            revert ETHTransferFailed();
        }

        emit TransferredETH(to, ethAmount);
    }

    /**
     * @notice Allows the `msg.sender` to burn their (pufETH) shares
     * It is used to burn portions of Puffer validator bonds due to inactivity or slashing
     * @param shares The amount of shares to burn
     *
     * @dev Restricted to PufferProtocol|PufferWithdrawalManager smart contracts
     */
    function burn(uint256 shares) public restricted {
        _burn(msg.sender, shares);
    }

    /**
     * @param newExitFeeBasisPoints is the new exit fee basis points
     *
     * @dev Restricted to the DAO
     */
    function setExitFeeBasisPoints(uint256 newExitFeeBasisPoints) external restricted {
        _setExitFeeBasisPoints(newExitFeeBasisPoints);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from the vault for a given owner
     * If the user has more assets than the available vault's liquidity, the user will be able to withdraw up to the available liquidity
     * else the user will be able to withdraw up to their assets
     * @param owner The address to check the maximum withdrawal amount for
     * @return maxAssets The maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256 maxAssets) {
        uint256 maxUserAssets = previewRedeem(balanceOf(owner));

        uint256 vaultLiquidity = (_WETH.balanceOf(address(this)) + (address(this).balance));
        // Calculate the available liquidity after applying the exit fee
        uint256 availableLiquidity = vaultLiquidity - _feeOnRaw(vaultLiquidity, getExitFeeBasisPoints());
        // Return the minimum of user's assets and available liquidity
        return Math.min(maxUserAssets, availableLiquidity);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed from the vault for a given owner
     * If the user has more shares than what can be redeemed given the available liquidity, the user will be able to redeem up to the available liquidity
     * else the user will be able to redeem all their shares
     * @param owner The address to check the maximum redeemable shares for
     * @return maxShares The maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) public view virtual override returns (uint256 maxShares) {
        uint256 shares = balanceOf(owner);
        // Calculate max shares based on available liquidity (WETH + ETH balance)
        uint256 availableLiquidity = _WETH.balanceOf(address(this)) + (address(this).balance);
        // Calculate how many shares can be redeemed from the available liquidity after fees
        uint256 maxSharesFromLiquidity = previewWithdraw(availableLiquidity);
        // Return the minimum of user's shares and shares from available liquidity
        return Math.min(shares, maxSharesFromLiquidity);
    }

    /**
     * @dev Preview adding an exit fee on withdraw. See {IERC4626-previewWithdraw}.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnRaw(assets, getExitFeeBasisPoints());
        return super.previewWithdraw(assets + fee);
    }

    /**
     * @dev Preview taking an exit fee on redeem. See {IERC4626-previewRedeem}.
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        // nosemgrep basic-arithmetic-underflow
        return assets - _feeOnTotal(assets, getExitFeeBasisPoints());
    }

    /**
     * @notice Returns the current exit fee basis points
     */
    function getExitFeeBasisPoints() public view virtual returns (uint256) {
        VaultStorage storage $ = _getPufferVaultStorage();
        return $.exitFeeBasisPoints;
    }

    /**
     * @notice Returns the amount of ETH that is pending withdrawal from Lido
     * @return The amount of ETH pending withdrawal
     */
    function getPendingLidoETHAmount() public view virtual returns (uint256) {
        VaultStorage storage $ = _getPufferVaultStorage();
        return $.lidoLockedETH;
    }

    /**
     * @notice Returns the total reward mint amount
     * @return The total minted rewards amount
     */
    function getTotalRewardMintAmount() public view returns (uint256) {
        VaultStorage storage $ = _getPufferVaultStorage();
        return $.totalRewardMintAmount;
    }

    /**
     * @notice Returns the total reward deposit amount
     * @return The total deposited rewards amount
     */
    function getTotalRewardDepositAmount() public view returns (uint256) {
        VaultStorage storage $ = _getPufferVaultStorage();
        return $.totalRewardDepositAmount;
    }

    /**
     * @notice Returns the amount of shares (pufETH) for the `assets` amount rounded up
     * @param assets The amount of assets
     */
    function convertToSharesUp(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /**
     * @notice Required by the ERC721 Standard to receive Lido withdrawal NFT
     */
    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Returns the number of decimals used to get its user representation
     */
    function decimals() public pure override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return 18;
    }

    /**
     * @dev Calculates the fees that should be added to an amount `assets` that does not already include fees.
     * Used in {IERC4626-withdraw}.
     */
    function _feeOnRaw(uint256 assets, uint256 feeBasisPoints) internal pure virtual returns (uint256) {
        return assets.mulDiv(feeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    /**
     * @dev Calculates the fee part of an amount `assets` that already includes fees.
     * Used in {IERC4626-redeem}.
     */
    function _feeOnTotal(uint256 assets, uint256 feeBasisPoints) internal pure virtual returns (uint256) {
        return assets.mulDiv(feeBasisPoints, feeBasisPoints + _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    /**
     * @notice Updates the exit fee basis points
     * @dev 200 Basis points = 2% is the maximum exit fee
     */
    function _setExitFeeBasisPoints(uint256 newExitFeeBasisPoints) internal virtual {
        VaultStorage storage $ = _getPufferVaultStorage();
        // 2% is the maximum exit fee
        if (newExitFeeBasisPoints > 200) {
            revert InvalidExitFeeBasisPoints();
        }
        emit ExitFeeBasisPointsSet($.exitFeeBasisPoints, newExitFeeBasisPoints);
        $.exitFeeBasisPoints = newExitFeeBasisPoints;
    }

    /**
     * @notice Wraps the vault's ETH balance to WETH
     * @dev Used to provide WETH liquidity
     */
    function _wrapETH(uint256 assets) internal virtual {
        uint256 wethBalance = _WETH.balanceOf(address(this));

        if (wethBalance < assets) {
            _WETH.deposit{ value: assets - wethBalance }();
        }
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    // slither-disable-next-line dead-code
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
