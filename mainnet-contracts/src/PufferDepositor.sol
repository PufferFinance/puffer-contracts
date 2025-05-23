// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessManagedUpgradeable } from
    "@openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IStETH } from "./interface/Lido/IStETH.sol";
import { IWstETH } from "./interface/Lido/IWstETH.sol";
import { PufferVaultV5 } from "./PufferVaultV5.sol";
import { PufferDepositorStorage } from "./PufferDepositorStorage.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISushiRouter } from "./interface/Other/ISushiRouter.sol";
import { IPufferDepositor } from "./interface/IPufferDepositor.sol";
import { Permit } from "./structs/Permit.sol";

/**
 * @title PufferDepositor
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
contract PufferDepositor is IPufferDepositor, PufferDepositorStorage, AccessManagedUpgradeable, UUPSUpgradeable {
    using SafeERC20 for address;

    IStETH internal immutable _ST_ETH;
    IWstETH internal constant _WST_ETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    /**
     * @dev This is how both 1Inch and Sushi represent native ETH
     */
    address internal constant _NATIVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant _1INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    ISushiRouter internal constant _SUSHI_ROUTER = ISushiRouter(0x5550D13389bB70F45fCeF58f19f6b6e87F6e747d);

    /**
     * @dev The Puffer Vault contract address
     */
    PufferVaultV5 public immutable PUFFER_VAULT;

    constructor(PufferVaultV5 pufferVault, IStETH stETH) payable {
        PUFFER_VAULT = pufferVault;
        _ST_ETH = stETH;
        _disableInitializers();
    }

    function initialize(address accessManager) external initializer {
        __AccessManaged_init(accessManager);
        SafeERC20.safeIncreaseAllowance(_ST_ETH, address(PUFFER_VAULT), type(uint256).max);
    }

    /**
     * @inheritdoc IPufferDepositor
     */
    function swapAndDeposit1Inch(address tokenIn, uint256 amountIn, bytes calldata callData)
        public
        payable
        virtual
        restricted
        returns (uint256 pufETHAmount)
    {
        if (tokenIn != _NATIVE_ETH) {
            SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);
            SafeERC20.safeIncreaseAllowance(IERC20(tokenIn), address(_1INCH_ROUTER), amountIn);
        }

        // PUFFER_VAULT.deposit will revert if we get no stETH from this contract
        // nosemgrep arbitrary-low-level-call
        (bool success, bytes memory returnData) = _1INCH_ROUTER.call{ value: msg.value }(callData);
        if (!success) {
            revert SwapFailed(address(tokenIn), amountIn);
        }

        uint256 amountOut = abi.decode(returnData, (uint256));

        if (amountOut == 0) {
            revert SwapFailed(address(tokenIn), amountIn);
        }

        return PUFFER_VAULT.deposit(amountOut, msg.sender);
    }

    /**
     * @inheritdoc IPufferDepositor
     */
    function swapAndDepositWithPermit1Inch(address tokenIn, Permit calldata permitData, bytes calldata callData)
        public
        payable
        virtual
        restricted
        returns (uint256 pufETHAmount)
    {
        try ERC20Permit(address(tokenIn)).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }

        return swapAndDeposit1Inch(tokenIn, permitData.amount, callData);
    }

    /**
     * @inheritdoc IPufferDepositor
     */
    function swapAndDeposit(address tokenIn, uint256 amountIn, uint256 amountOutMin, bytes calldata routeCode)
        public
        payable
        virtual
        restricted
        returns (uint256 pufETHAmount)
    {
        if (tokenIn != _NATIVE_ETH) {
            SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);
            SafeERC20.safeIncreaseAllowance(IERC20(tokenIn), address(_SUSHI_ROUTER), amountIn);
        }

        uint256 stETHAmountOut = _SUSHI_ROUTER.processRoute{ value: msg.value }({
            tokenIn: tokenIn,
            amountIn: amountIn,
            tokenOut: address(_ST_ETH),
            amountOutMin: amountOutMin,
            to: address(this),
            route: routeCode
        });

        if (stETHAmountOut == 0) {
            revert SwapFailed(address(tokenIn), amountIn);
        }

        return PUFFER_VAULT.deposit(stETHAmountOut, msg.sender);
    }

    /**
     * @inheritdoc IPufferDepositor
     */
    function swapAndDepositWithPermit(
        address tokenIn,
        uint256 amountOutMin,
        Permit calldata permitData,
        bytes calldata routeCode
    ) public payable virtual restricted returns (uint256 pufETHAmount) {
        try ERC20Permit(address(tokenIn)).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }

        return swapAndDeposit(tokenIn, permitData.amount, amountOutMin, routeCode);
    }

    /**
     * @inheritdoc IPufferDepositor
     */
    function depositWstETH(Permit calldata permitData) external restricted returns (uint256 pufETHAmount) {
        try ERC20Permit(address(_WST_ETH)).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }

        SafeERC20.safeTransferFrom(IERC20(address(_WST_ETH)), msg.sender, address(this), permitData.amount);
        uint256 stETHAmount = _WST_ETH.unwrap(permitData.amount);

        return PUFFER_VAULT.deposit(stETHAmount, msg.sender);
    }

    /**
     * @inheritdoc IPufferDepositor
     */
    function depositStETH(Permit calldata permitData) external restricted returns (uint256 pufETHAmount) {
        try ERC20Permit(address(_ST_ETH)).permit({
            owner: msg.sender,
            spender: address(this),
            value: permitData.amount,
            deadline: permitData.deadline,
            v: permitData.v,
            s: permitData.s,
            r: permitData.r
        }) { } catch { }

        SafeERC20.safeTransferFrom(IERC20(address(_ST_ETH)), msg.sender, address(this), permitData.amount);

        return PUFFER_VAULT.deposit(permitData.amount, msg.sender);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * Restricted access
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted { }
}
