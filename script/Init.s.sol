// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2024 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { Domain } from "dss-test/domains/Domain.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { FarmProxyInit, ProxiesConfig, MessageParams } from "deploy/FarmProxyInit.sol";
import { L2FarmProxySpell } from "deploy/L2FarmProxySpell.sol";
import { RetryableTickets } from "arbitrum-token-bridge/script/utils/RetryableTickets.sol";

interface L2GovernanceRelayLike {
    function relay(address, bytes calldata) external;
}

contract Init is Script {
    using stdJson for string;

    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    string deps;
    Domain l1Domain;
    Domain l2Domain;
    DssInstance dss;

    address l1GovRelay;
    address l2GovRelay;

    function run() external {
        l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        config = ScriptTools.loadConfig("config");
        deps   = ScriptTools.loadDependencies();
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        dss = MCD.loadFromChainlog(deps.readAddress(".chainlog"));

        l1GovRelay = deps.readAddress(".l1GovRelay");
        l2GovRelay = deps.readAddress(".l2GovRelay");
        RetryableTickets retryable = new RetryableTickets(l1Domain, l2Domain, l1GovRelay, l2GovRelay);

        address l2Proxy = deps.readAddress(".l2Proxy");
        address l2ProxySpell = deps.readAddress(".l2ProxySpell");
        address l2RewardsToken = deps.readAddress(".l2RewardsToken");
        address stakingToken = deps.readAddress(".stakingToken");
        address farm = deps.readAddress(".farm");
        uint256 l2MinReward = 1 ether;
        uint256 rewardsDuration = 1 days;

        bytes memory initCalldata = abi.encodeCall(L2GovernanceRelayLike.relay, (
            l2ProxySpell, 
            abi.encodeCall(L2FarmProxySpell.init, (
                l2Proxy,
                l2RewardsToken,
                stakingToken,
                farm,
                l2MinReward,
                rewardsDuration
            ))
        ));
        MessageParams memory xchainMsg = MessageParams({
            maxGas:            retryable.getMaxGas(initCalldata) * 150 / 100,
            gasPriceBid:       retryable.getGasPriceBid() * 200 / 100,
            maxSubmissionCost: retryable.getSubmissionFee(initCalldata) * 250 / 100
        });
        ProxiesConfig memory cfg = ProxiesConfig({
            vest:                      deps.readAddress(".vest"),
            vestTot:                   100 ether,
            vestBgn:                   block.timestamp,
            vestTau:                   100 days,
            vestMgr:                   address(0),
            vestedRewardsDistribution: deps.readAddress(".vestedRewardsDistribution"),
            l1RewardsToken:            deps.readAddress(".l1RewardsToken"),
            l2RewardsToken:            l2RewardsToken,
            stakingToken:              stakingToken,
            l1Gateway:                 deps.readAddress(".l1Gateway"),
            maxGas:                    70_000_000, // determined by running deploy/Estimate.s.sol and adding some margin
            gasPriceBid:               0.1 gwei, // 0.01 gwei arbitrum-one gas price floor * 10x factor
            l1MinReward:               1 ether,
            l2MinReward:               l2MinReward,
            farm:                      farm,
            rewardsDuration:           rewardsDuration, 
            xchainMsg:                 xchainMsg,
            proxyChainlogKey:          "FARM_PROXY_TKA_TKB_ARB",
            distrChainlogKey:          "REWARDS_DISTRIBUTION_TKA_TKB_ARB"
        });

        vm.startBroadcast();
        uint256 minGovRelayBal = cfg.xchainMsg.maxSubmissionCost + cfg.xchainMsg.maxGas * cfg.xchainMsg.gasPriceBid;
        if (l1GovRelay.balance < minGovRelayBal) {
            (bool success,) = l1GovRelay.call{value: minGovRelayBal - l1GovRelay.balance}("");
            require(success, "l1GovRelay topup failed");
        }

        FarmProxyInit.initProxies(
            dss,
            deps.readAddress(".l1Proxy"),
            l2Proxy,
            l2ProxySpell,
            cfg
        );
        vm.stopBroadcast();
    }
}
