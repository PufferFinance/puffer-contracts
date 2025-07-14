// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

interface IPufferProtocolEvents {
    /**
     * @notice Emitted when the number of active validators changes
     * @dev Signature "0xc06afc2b3c88873a9be580de9bbbcc7fea3027ef0c25fd75d5411ed3195abcec"
     */
    event NumberOfRegisteredValidatorsChanged(bytes32 indexed moduleName, uint256 newNumberOfRegisteredValidators);

    /**
     * @notice Emitted when the validation time is deposited
     * @dev Signature "0xdab70193ab2d6948fc2f6da9e82794bf650dc3099e042b6510f9e5019735545c"
     */
    event ValidationTimeDeposited(address indexed node, uint256 ethAmount);

    /**
     * @notice Emitted when the new Puffer module is created
     * @dev Signature "0x8ad2a9260a8e9a01d1ccd66b3875bcbdf8c4d0c552bc51a7d2125d4146e1d2d6"
     */
    event NewPufferModuleCreated(address module, bytes32 indexed moduleName, bytes32 withdrawalCredentials);

    /**
     * @notice Emitted when the module's validator limit is changed from `oldLimit` to `newLimit`
     * @dev Signature "0x21e92cbdc47ef718b9c77ea6a6ee50ff4dd6362ee22041ab77a46dacb93f5355"
     */
    event ValidatorLimitPerModuleChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when the minimum number of days for ValidatorTickets is changed from `oldMinimumNumberOfDays` to `newMinimumNumberOfDays`
     * @dev Signature "0xc6f97db308054b44394df54aa17699adff6b9996e9cffb4dcbcb127e20b68abc"
     */
    event MinimumVTAmountChanged(uint256 oldMinimumNumberOfDays, uint256 newMinimumNumberOfDays);

    /**
     * @notice Emitted when the VT Penalty amount is changed from `oldPenalty` to `newPenalty`
     * @dev Signature "0xfceca97b5d1d1164f9a15e42f38eaf4a6e760d8505f06161a258d4bf21cc4ee7"
     */
    event VTPenaltyChanged(uint256 oldPenalty, uint256 newPenalty);

    /**
     * @notice Emitted when VT is deposited to the protocol
     * @dev Signature "0xd47eb90c0b945baf5f3ae3f1384a7a524a6f78f1461b354c4a09c4001a5cee9c"
     */
    event ValidatorTicketsDeposited(address indexed node, address indexed depositor, uint256 amount);

    /**
     * @notice Emitted when VT is withdrawn from the protocol
     * @dev Signature "0xdf7e884ecac11650e1285647b057fa733a7bb9f1da100e7a8c22aafe4bdf6f40"
     */
    event ValidatorTicketsWithdrawn(address indexed node, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when Validation Time is withdrawn from the protocol
     * @dev Signature "0xd19b9bc208843da6deef01aa6dedd607204c4f8b6d02f79b60e326a8c6e2b6e8"
     */
    event ValidationTimeWithdrawn(address indexed node, address indexed recipient, uint256 ethAmount);

    /**
     * @notice Emitted when the guardians decide to skip validator provisioning for `moduleName`
     * @dev Signature "0x088dc5dc64f3e8df8da5140a284d3018a717d6b009e605513bb28a2b466d38ee"
     */
    event ValidatorSkipped(bytes pubKey, uint256 indexed pufferModuleIndex, bytes32 indexed moduleName);

    /**
     * @notice Emitted when the module weights changes from `oldWeights` to `newWeights`
     * @dev Signature "0xd4c9924bd67ff5bd900dc6b1e03b839c6ffa35386096b0c2a17c03638fa4ebff"
     */
    event ModuleWeightsChanged(bytes32[] oldWeights, bytes32[] newWeights);

    /**
     * @notice Emitted when the Validator key is registered
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @param numBatches is the number of batches the validator has
     * @dev Signature "0xd97b45553982eba642947754e3448d2142408b73d3e4be6b760a89066eb6c00a"
     */
    event ValidatorKeyRegistered(
        bytes pubKey, uint256 indexed pufferModuleIndex, bytes32 indexed moduleName, uint8 numBatches
    );

    /**
     * @notice Emitted when the Validator exited and stopped validating
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @param pufETHBurnAmount The amount of pufETH burned from the Node Operator
     * @param numBatches is the number of batches the validator had
     * @dev Signature "0xf435da9e3aeccc40d39fece7829f9941965ceee00d31fa7a89d608a273ea906e"
     */
    event ValidatorExited(
        bytes pubKey,
        uint256 indexed pufferModuleIndex,
        bytes32 indexed moduleName,
        uint256 pufETHBurnAmount,
        uint256 numBatches
    );

    /**
     * @notice Emitted when a validator is downsized
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @param pufETHBurnAmount The amount of pufETH burned from the Node Operator
     * @param epoch The epoch of the downsize
     * @param numBatchesBefore The number of batches before the downsize
     * @param numBatchesAfter The number of batches after the downsize
     * @dev Signature "0x75afd977bd493b29a8e699e6b7a9ab85df6b62f4ba5664e370bd5cb0b0e2b776"
     */
    event ValidatorDownsized(
        bytes pubKey,
        uint256 indexed pufferModuleIndex,
        bytes32 indexed moduleName,
        uint256 pufETHBurnAmount,
        uint256 epoch,
        uint256 numBatchesBefore,
        uint256 numBatchesAfter
    );

    /**
     * @notice Emitted when validation time is consumed
     * @param node is the node operator address
     * @param consumedAmount is the amount of validation time that was consumed
     * @param deprecated_burntVTs is the amount of VT that was burnt
     * @dev Signature "0x4b16b7334c6437660b5530a3a5893e7a10fa5424e5c0d67806687147553544ef"
     */
    event ValidationTimeConsumed(address indexed node, uint256 consumedAmount, uint256 deprecated_burntVTs);

    /**
     * @notice Emitted when a consolidation is requested
     * @param moduleName is the module name
     * @param srcPubkeys is the list of pubkeys to consolidate from
     * @param targetPubkeys is the list of pubkeys to consolidate to
     * @dev Signature "0xdc26585f08f92fc2f54b80496c32d3c20cfa17f1e91d9afc8449c17d1b4f85bb"
     */
    event ConsolidationRequested(bytes32 indexed moduleName, bytes[] srcPubkeys, bytes[] targetPubkeys);

    /**
     * @notice Emitted when the Validator is provisioned
     * @param pubKey is the validator public key
     * @param pufferModuleIndex is the internal validator index in Puffer Finance, not to be mistaken with validator index on Beacon Chain
     * @param moduleName is the staking Module
     * @param numBatches is the number of batches the validator has
     * @dev Signature "0xfed1ead36b4481c77b26f25acade13754ce94663e2515f15507b2cfbade3ed8d"
     */
    event SuccessfullyProvisioned(
        bytes pubKey, uint256 indexed pufferModuleIndex, bytes32 indexed moduleName, uint256 numBatches
    );

    /**
     * @notice Emitted when the PufferProtocolLogic is set
     * @dev Signature "0xe271f36954242c619ce9d0f727a7d3b5f4db04666752aaeb20bca6d52098792a"
     */
    event PufferProtocolLogicSet(address oldPufferProtocolLogic, address newPufferProtocolLogic);
}
