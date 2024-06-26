TODO: Rename repo to arbitrum-farms

# Arbitrum Farms

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

On mainnet, the farm proxies should be initialized via the spell process. On testnet, the proxies initialization can be performed via the following command:

```
forge script script/Init.s.sol:Init --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast
```
