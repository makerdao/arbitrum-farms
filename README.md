# Arbitrum Farms

## Overview

This repository implements a mechanism to distribute rewards vested in a [DssVest](https://github.com/makerdao/dss-vest) contract on L1 to users staking tokens in a [StakingRewards](https://github.com/makerdao/endgame-toolkit/blob/master/src/synthetix/StakingRewards.sol) farm on Arbitrum. It uses the [Arbitrum Token Bridge](https://github.com/makerdao/arbitrum-token-bridge) to transfer the rewards from L1 to L2.

## Contracts

- `L1FarmProxy.sol` - Proxy to the farm on the L1 side. Receives the token reward (expected to come from a [`VestedRewardDistribution`](https://github.com/makerdao/endgame-toolkit/blob/master/src/VestedRewardsDistribution.sol) contract) and transfers it cross-chain to the `L2FarmProxy`. An instance of `L1FarmProxy` must be deployed for each supported pair of staking and rewards token.
- `L2FarmProxy.sol` - Proxy to the farm on the L2 side. Receives the token reward (expected to be bridged from the `L1FarmProxy`) and forwards it to the [StakingRewards](https://github.com/makerdao/endgame-toolkit/blob/master/src/synthetix/StakingRewards.sol) farm where it gets distributed to stakers. An instance of `L2FarmProxy` must be deployed for each supported pair of staking and rewards token.

### External dependencies

- The L2 staking tokens and the L1 and L2 rewards tokens are not provided as part of this repository. It is assumed that only simple, regular ERC20 tokens will be used. In particular, the supported tokens are assumed to revert on failure (instead of returning false) and do not execute any hook on transfer.
- [`DssVest`](https://github.com/makerdao/dss-vest) is used to vest the rewards token on L1.
- [`VestedRewardDistribution`](https://github.com/makerdao/endgame-toolkit/blob/master/src/VestedRewardsDistribution.sol) is used to vest the rewards tokens from `DssVest`, transfer them to the `L1FarmProxy` and trigger the bridging of the tokens.
- The [Arbitrum Token Bridge](https://github.com/makerdao/arbitrum-token-bridge) is used to bridge the tokens from L1 to L2.
- The [escrow contract](https://etherscan.io/address/0xA10c7CE4b876998858b1a9E12b10092229539400#code) is used by the Arbitrum Token Bridge to hold the bridged tokens on L1.
- [`StakingRewards`](https://github.com/makerdao/endgame-toolkit/blob/master/src/synthetix/StakingRewards.sol) is used to distribute the bridged rewards to stakers on L2.
- The [`L1GovernanceRelay`](https://etherscan.io/address/0x9ba25c289e351779E0D481Ba37489317c34A899d#code) & [`L2GovernanceRelay`](https://arbiscan.io/address/0x10E6593CDda8c58a1d0f14C5164B376352a55f2F#code) allow governance to exert admin control over the deployed L2 contracts. These contracts have been previously deployed to control the Arbitrum Dai Bridge.

## Expected flow

- It is expected that the ether balance of the `L1FarmProxy` is continuously monitored and topped up as needed to ensure the successful operation of the proxy.
- Once the vested amount of rewards tokens exceeds `L1FarmProxy.rewardThreshold`, a keeper calls `VestedRewardDistribution.distribute()` to vest the rewards and have them bridged to L2.
- Once the bridged amount of rewards tokens exceeds `L2FarmProxy.rewardThreshold`, anyone (e.g. a keeper or an L2 staker) can call `L2FarmProxy.forwardReward()` to distribute the rewards to the L2 farm.

Note that `L1FarmProxy.rewardThreshold` must be sufficiently large to reduce the frequency of cross-chain transfers (thereby also reducing the amount of ether that needs to be provisionned into the `L1FarmProxy`). `L2FarmProxy.rewardThreshold` must also be sufficiently large to limit the reduction of the farm's rate of rewards distribution.

## Deployment

### Declare env variables

Add the required env variables listed in `.env.example` to your `.env` file, and run `source .env`.

Make sure to set the `L1` and `L2` env variables according to your desired deployment environment.

Mainnet deployment:

```
L1=mainnet
L2=arbitrum_one
```

Testnet deployment:

```
L1=sepolia
L2=arbitrum_one_sepolia
```

### Deploy the farm L1 & L2 proxies

The deployment assumes that the [arbitrum-token-bridge](https://github.com/makerdao/arbitrum-token-bridge) has already been deployed and was properly initialized.

Fill in the addresses of the L2 staking token and L1 and L2 rewards tokens in `script/input/{chainId}/config.json` under the `"stakingToken"` and `"rewardsToken"` keys. It is assumed that these tokens have been registered with the Arbitrum Token Bridge.

Fill in the address of the mainnet DssVest contract in `script/input/1/config.json` under the `vest` key. It is assumed that the vesting contract was properly initialized. On testnet, a mock DssVest contract will automatically be deployed.

The following command deploys the L1 and L2 farm proxies:

```
forge script script/Deploy.s.sol:Deploy --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --verify --multi --broadcast
```

### Initialize the farm L1 & L2 proxies

On mainnet, the farm proxies should be initialized via the spell process. To determine an adequate value for the `maxGas` storage variable of `L1FarmProxy`, the `Estimate` script can be run:

```
forge script script/Estimate.s.sol:Estimate --sender $DEPLOYER --private-key $PRIVATE_KEY
```

On testnet, the proxies initialization can be performed via the following command:

```
forge script script/Init.s.sol:Init --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast
```

### Run a test distribution

Run the following command to distribute the vested funds to the L1 proxy:

```
forge script script/Distribute.s.sol:Distribute --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast
```

Wait for the transaction to be relayed to L2, then run the following command to forward the bridged funds from the L2 proxy to the farm:

```
forge script script/Forward.s.sol:Forward --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast
```
