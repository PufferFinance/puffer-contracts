// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @notice Beacon Deposit Contract for ETH Mainnet
 * https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa#code
 */
interface IBeaconDepositContract {
    //solhint-disable-next-line func-param-name-mixedcase
    event DepositEvent(bytes pubkey, bytes withdrawal_credentials, bytes amount, bytes signature, bytes index);

    function deposit(
        //solhint-disable-next-line func-param-name-mixedcase
        bytes memory pubkey,
        //solhint-disable-next-line func-param-name-mixedcase
        bytes memory withdrawal_credentials,
        //solhint-disable-next-line func-param-name-mixedcase
        bytes memory signature,
        //solhint-disable-next-line func-param-name-mixedcase
        bytes32 deposit_data_root
    ) external payable;
    function get_deposit_count() external view returns (bytes memory);
    function get_deposit_root() external view returns (bytes32);
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
