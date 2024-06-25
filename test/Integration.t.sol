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

import "dss-test/DssTest.sol";

import { Domain } from "dss-test/domains/Domain.sol";
import { ArbitrumDomain } from "dss-test/domains/ArbitrumDomain.sol";

import { TokenGatewayDeploy } from "lib/arbitrum-token-bridge/deploy/TokenGatewayDeploy.sol";
import { L2TokenGatewaySpell } from "lib/arbitrum-token-bridge/deploy/L2TokenGatewaySpell.sol";
import { L2TokenGatewayInstance } from "lib/arbitrum-token-bridge/deploy/L2TokenGatewayInstance.sol";
import { TokenGatewayInit, GatewaysConfig, MessageParams as GatewayMessageParams } from "lib/arbitrum-token-bridge/deploy/TokenGatewayInit.sol";

import { StakingRewards, StakingRewardsDeploy, StakingRewardsDeployParams } from "lib/endgame-toolkit/script/dependencies/StakingRewardsDeploy.sol";
import { VestedRewardsDistributionDeploy, VestedRewardsDistributionDeployParams } from "lib/endgame-toolkit/script/dependencies/VestedRewardsDistributionDeploy.sol";
import { VestedRewardsDistribution } from "lib/endgame-toolkit/src/VestedRewardsDistribution.sol";

import { GemMock } from "test/mocks/GemMock.sol";
import { DssVestMintableMock } from "test/mocks/DssVestMock.sol";

import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";
import { L2FarmProxySpell } from "deploy/L2FarmProxySpell.sol";
import { L2FarmProxyInstance } from "deploy/L2FarmProxyInstance.sol";
import { FarmProxyInit, ProxiesConfig, MessageParams as ProxyMessageParams } from "deploy/FarmProxyInit.sol";
import { L1FarmProxy } from "src/L1FarmProxy.sol";
import { L2FarmProxy } from "src/L2FarmProxy.sol";

interface L1RelayLike {
    function l2GovernanceRelay() external view returns (address);
}

contract IntegrationTest is DssTest {
    string config;
    Domain l1Domain;
    ArbitrumDomain l2Domain;

    // L1-side
    DssInstance dss;
    address PAUSE_PROXY;
    address ESCROW;
    GemMock l1Token;
    address l1Gateway;
    address INBOX;
    L1FarmProxy l1Proxy;
    DssVestMintableMock vest;
    uint256 vestId;
    VestedRewardsDistribution vestedRewardDistribution;

    // L2-side
    address L2_GOV_RELAY;
    GemMock l2Token;
    address l2Gateway;
    L2FarmProxy l2Proxy;
    StakingRewards farm;

    function setupGateways() internal {
        ESCROW = dss.chainlog.getAddress("ARBITRUM_ESCROW");
        vm.label(address(ESCROW), "ESCROW");

        l2Domain = new ArbitrumDomain(config, getChain("arbitrum_one"), l1Domain);
        INBOX = l2Domain.readConfigAddress("inbox");
        vm.label(INBOX, "INBOX");

        address l1Gateway_ = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2); // foundry increments a global nonce across domains
        l2Domain.selectFork();
        L2TokenGatewayInstance memory l2GatewayInstance = TokenGatewayDeploy.deployL2Gateway({
            deployer:  address(this),
            owner:     L2_GOV_RELAY,
            l1Gateway: l1Gateway_, 
            l2Router:  address(0)
        });
        l2Gateway = l2GatewayInstance.gateway;
        assertEq(address(L2TokenGatewaySpell(l2GatewayInstance.spell).l2Gateway()), address(l2Gateway));

        l1Domain.selectFork();
        l1Gateway = TokenGatewayDeploy.deployL1Gateway({
            deployer:  address(this),
            owner:     PAUSE_PROXY,
            l2Gateway: address(l2Gateway), 
            l1Router:  address(0),
            inbox:     INBOX,
            escrow:    ESCROW
        });
        assertEq(address(l1Gateway), l1Gateway_);

        l2Domain.selectFork();
        l2Token = new GemMock(0);
        l2Token.rely(L2_GOV_RELAY);
        l2Token.deny(address(this));
        vm.label(address(l2Token), "l2Token");

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);
        GatewayMessageParams memory xchainMsg = GatewayMessageParams({
            gasPriceBid:       0.1 gwei,
            maxGas:            300_000,
            maxSubmissionCost: 0.01 ether
        });
        GatewaysConfig memory cfg = GatewaysConfig({
            counterpartGateway: address(l2Gateway),
            l1Router:           address(0),
            inbox:              INBOX,
            l1Tokens:           l1Tokens,
            l2Tokens:           l2Tokens,
            xchainMsg:          xchainMsg
        });

        l1Domain.selectFork();
        vm.startPrank(PAUSE_PROXY);
        TokenGatewayInit.initGateways(dss, address(l1Gateway), l2GatewayInstance, cfg);
        vm.stopPrank();
    }

    function setUp() public {
        config = ScriptTools.readInput("config");

        l1Domain = new Domain(config, getChain("mainnet"));
        l1Domain.selectFork();
        l1Domain.loadDssFromChainlog();
        dss = l1Domain.dss();
        PAUSE_PROXY  = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        L2_GOV_RELAY = L1RelayLike(dss.chainlog.getAddress("ARBITRUM_GOV_RELAY")).l2GovernanceRelay();
        vm.label(address(PAUSE_PROXY),  "PAUSE_PROXY");
        vm.label(address(L2_GOV_RELAY), "L2_GOV_RELAY");

        vm.startPrank(PAUSE_PROXY);
        l1Token = new GemMock(100 ether);
        vest = new DssVestMintableMock(address(l1Token));
        l1Token.rely(address(vest));
        vest.file("cap", type(uint256).max);
        vm.stopPrank();

        setupGateways();

        l2Domain.selectFork();

        StakingRewardsDeployParams memory farmParams = StakingRewardsDeployParams({
            owner: L2_GOV_RELAY,
            stakingToken: address(new GemMock(100 ether)),
            rewardsToken: address(l2Token)
        });
        farm = StakingRewards(StakingRewardsDeploy.deploy(farmParams));

        L2FarmProxyInstance memory l2ProxyInstance = FarmProxyDeploy.deployL2Proxy({
            deployer: address(this),
            owner:    L2_GOV_RELAY,
            farm:     address(farm)
        });
        l2Proxy = L2FarmProxy(l2ProxyInstance.proxy);
        assertEq(address(L2FarmProxySpell(l2ProxyInstance.spell).l2Proxy()), address(l2Proxy));

        l1Domain.selectFork();
        l1Proxy = L1FarmProxy(payable(FarmProxyDeploy.deployL1Proxy({
            deployer:     address(this),
            owner:        PAUSE_PROXY,
            gem:          address(l1Token), 
            l2Proxy:      address(l2Proxy),
            feeRecipient: L2_GOV_RELAY,
            inbox:        INBOX,
            l1Gateway:    l1Gateway
        })));

        VestedRewardsDistributionDeployParams memory distributionParams = VestedRewardsDistributionDeployParams({
            deployer:  address(this),
            owner:     PAUSE_PROXY,
            vest:      address(vest),
            rewards:   address(l1Proxy)
        });
        vestedRewardDistribution = VestedRewardsDistribution(VestedRewardsDistributionDeploy.deploy(distributionParams));

        (bool success,) = address(l1Proxy).call{value: 1 ether}("");
        assertTrue(success);
        ProxyMessageParams memory xchainMsg = ProxyMessageParams({
            gasPriceBid:       0.1 gwei,
            maxGas:            300_000,
            maxSubmissionCost: 0.01 ether
        });
        ProxiesConfig memory cfg = ProxiesConfig({
            vest:                     address(vest),
            vestedRewardDistribution: address(vestedRewardDistribution),
            vestTot:                  100 * 1e18,
            vestBgn:                  block.timestamp,
            vestTau:                  100 days,
            vestMgr:                  address(0),
            rewardsToken:             address(l1Token),
            l2Proxy:                  address(l2Proxy),
            feeRecipient:             L2_GOV_RELAY,
            inbox:                    INBOX,
            l1Gateway:                l1Gateway,
            maxGas:                   70_000_000, // determined by running deploy/Estimate.s.sol and adding some margin
            gasPriceBid:              0.1 gwei, // 0.01 gwei arbitrum-one gas price floor * 10x factor
            l1MinReward:              0,
            l2MinReward:              1 ether,
            rewardsDuration:          1 days, 
            xchainMsg:                xchainMsg
        });
        vm.startPrank(PAUSE_PROXY);
        FarmProxyInit.initProxies(dss, address(l1Proxy), l2ProxyInstance, cfg);
        vm.stopPrank();

        // test L1 side of initProxies
        vestId = vestedRewardDistribution.vestId();
        assertEq(vest.usr(vestId),                                  cfg.vestedRewardDistribution);
        assertEq(vest.tot(vestId),                                  cfg.vestTot);
        assertEq(vest.bgn(vestId),                                  cfg.vestBgn);
        assertEq(vest.fin(vestId),                                  cfg.vestBgn + cfg.vestTau);
        assertEq(vest.clf(vestId),                                  cfg.vestBgn);
        assertEq(vest.mgr(vestId),                                  cfg.vestMgr);
        assertEq(vest.res(vestId),                                  1);
        assertEq(l1Proxy.maxGas(),                                  cfg.maxGas);
        assertEq(l1Proxy.gasPriceBid(),                             cfg.gasPriceBid);
        assertEq(l1Proxy.minReward(),                               cfg.l1MinReward);
        assertEq(dss.chainlog.getAddress("ARBITRUM_L1_FARM_PROXY"), address(l1Proxy));

        l2Domain.relayFromHost(true);

        // test L2 side of initProxies
        assertEq(l2Proxy.minReward(),        cfg.l2MinReward);
        assertEq(farm.rewardsDistribution(), address(l2Proxy));
        assertEq(farm.rewardsDuration(),     cfg.rewardsDuration);
    }

    function testDistribution() public {
        l2Domain.selectFork();
        uint256 minReward = l2Proxy.minReward();

        l1Domain.selectFork();
        vm.warp(vest.bgn(vestId) + minReward * (vest.fin(vestId) - vest.bgn(vestId)) / vest.tot(vestId));
        uint256 amount = vest.unpaid(vestId);
        assertGe(amount, minReward);
        assertEq(l1Token.balanceOf(ESCROW), 0);

        vestedRewardDistribution.distribute();

        assertEq(l1Token.balanceOf(ESCROW), amount);

        l2Domain.relayFromHost(true);

        assertEq(l2Token.balanceOf(address(l2Proxy)), amount);
    
        l2Proxy.forwardReward();

        assertEq(l2Token.balanceOf(address(l2Proxy)), 0);
        assertEq(l2Token.balanceOf(address(farm)), amount);
        assertEq(farm.rewardRate(), amount / farm.rewardsDuration());
    }
}
