include .env
export $(shell sed 's/=.*//' .env)

test-puffervaultv3:
	forge test -vvv --fail-fast --match-path PufferVaultV3.fork.t.sol

deploy-puffervaultv3-holesky:
	forge script ./script/DeployPufferVaultV3.s.sol:DeployPufferVaultV3 \
		--rpc-url ${HOLESKY_RPC_URL} \
		--chain holesky \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--private-key ${PK} \
		--broadcast \
		--slow \
		-vvvv

upgrade-puffervaultv3-holesky:
	forge script ./script/UpgradePufferVaultV3.s.sol:UpgradePufferVaultV3 \
		--rpc-url ${HOLESKY_RPC_URL} \
		--chain holesky \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--private-key ${PK} \
		--broadcast \
		--slow \
		-vvvv
