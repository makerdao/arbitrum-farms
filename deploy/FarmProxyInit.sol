// SPDX-FileCopyrightText: © 2024 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity >=0.8.0;

import { DssInstance } from "dss-test/MCD.sol";
import { L2FarmProxyInstance } from "./L2FarmProxyInstance.sol";
import { L2FarmProxySpell } from "./L2FarmProxySpell.sol";

interface DssVestLike {
    function gem() external view returns (address);
    function create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) external returns (uint256 id);
    function restrict(uint256 _id) external;
}

interface VestedRewardsDistributionLike {
    function dssVest() external view returns (address);
    function stakingRewards() external view returns (address);
    function gem() external view returns (address);
    function file(bytes32 what, uint256 data) external;
}

interface L1FarmProxyLike {
    function rewardsToken() external view returns (address);
    function l2Proxy() external view returns (address);
    function feeRecipient() external view returns (address);
    function inbox() external view returns (address);
    function l1Gateway() external view returns (address);
    function file(bytes32 what, uint256 data) external;
}

interface L1RelayLike {
    function relay(
        address target,
        bytes calldata targetData,
        uint256 l1CallValue,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    ) external payable;
}

struct MessageParams {
    uint256 maxGas;
    uint256 gasPriceBid;
    uint256 maxSubmissionCost;
}

struct ProxiesConfig {
    address vest;
    address vestedRewardDistribution;
    uint256 vestTot;
    uint256 vestBgn;
    uint256 vestTau;
    address vestMgr;
    address rewardsToken;
    address l2Proxy;
    address feeRecipient;
    address inbox;
    address l1Gateway;
    uint256 maxGas;          // For the L1 proxy
    uint256 gasPriceBid;     // For the L1 proxy
    uint256 l1MinReward;     // For the L1 proxy
    uint256 l2MinReward;     // For the L2 proxy
    uint256 rewardsDuration; // For the farm on L2
    MessageParams xchainMsg; // For the xchain message executing the L2 spell
    bytes32 proxyChainlogKey;
    bytes32 distrChainlogKey;
}

library FarmProxyInit {
    function initProxies(
        DssInstance memory         dss,
        address                    l1Proxy_,
        L2FarmProxyInstance memory l2ProxyInstance,
        ProxiesConfig memory       cfg
    ) internal {
        L1FarmProxyLike l1Proxy = L1FarmProxyLike(l1Proxy_);
        DssVestLike vest = DssVestLike(cfg.vest);
        VestedRewardsDistributionLike distribution = VestedRewardsDistributionLike(cfg.vestedRewardDistribution);

        // sanity checks

        require(vest.gem()                    == cfg.rewardsToken,  "FarmProxyInit/vest-gem-mismatch");
        require(distribution.gem()            == cfg.rewardsToken,  "FarmProxyInit/distribution-gem-mismatch");
        require(distribution.stakingRewards() == l1Proxy_,          "FarmProxyInit/distribution-farm-mismatch");
        require(distribution.dssVest()        == cfg.vest,          "FarmProxyInit/distribution-vest-mismatch");
        require(l1Proxy.rewardsToken()        == cfg.rewardsToken,  "FarmProxyInit/rewards-token-mismatch");
        require(l1Proxy.l2Proxy()             == cfg.l2Proxy,       "FarmProxyInit/l2-proxy-mismatch");
        require(l1Proxy.feeRecipient()        == cfg.feeRecipient,  "FarmProxyInit/fee-recipient-mismatch");
        require(l1Proxy.inbox()               == cfg.inbox,         "FarmProxyInit/inbox-mismatch");
        require(l1Proxy.l1Gateway()           == cfg.l1Gateway,     "FarmProxyInit/l1-gateway-mismatch");
        require(cfg.maxGas                    <= 10_000_000_000,    "FarmProxyInit/max-gas-out-of-bounds");
        require(cfg.gasPriceBid               <= 10_000 gwei,       "FarmProxyInit/gas-price-bid-out-of-bounds");
        require(cfg.l1MinReward               <= type(uint128).max, "FarmProxyInit/l1-min-reward-out-of-bounds");
        require(cfg.l2MinReward               > 0,                  "FarmProxyInit/l2-min-reward-out-of-bounds");

        // setup vest

        uint256 vestId = vest.create({
            _usr: cfg.vestedRewardDistribution,
            _tot: cfg.vestTot,
            _bgn: cfg.vestBgn,
            _tau: cfg.vestTau,
            _eta: 0,
            _mgr: cfg.vestMgr
        });
        vest.restrict(vestId);
        distribution.file("vestId", vestId);

        // setup L1 proxy

        l1Proxy.file("maxGas",      cfg.maxGas);
        l1Proxy.file("gasPriceBid", cfg.gasPriceBid);
        l1Proxy.file("minReward",   cfg.l1MinReward);

        // setup L2 proxy

        L1RelayLike l1GovRelay = L1RelayLike(dss.chainlog.getAddress("ARBITRUM_GOV_RELAY"));
        uint256 l1CallValue = cfg.xchainMsg.maxSubmissionCost + cfg.xchainMsg.maxGas * cfg.xchainMsg.gasPriceBid;

        // not strictly necessary (as the retryable ticket creation would otherwise fail) 
        // but makes the eth balance requirement more explicit
        require(address(l1GovRelay).balance >= l1CallValue, "FarmProxyInit/insufficient-relay-balance");

        l1GovRelay.relay({
            target:            l2ProxyInstance.spell,
            targetData:        abi.encodeCall(L2FarmProxySpell.init, (cfg.l2MinReward, cfg.rewardsDuration)),
            l1CallValue:       l1CallValue,
            maxGas:            cfg.xchainMsg.maxGas,
            gasPriceBid:       cfg.xchainMsg.gasPriceBid,
            maxSubmissionCost: cfg.xchainMsg.maxSubmissionCost
        });

        // update chainlog

        dss.chainlog.setAddress(cfg.proxyChainlogKey, l1Proxy_);
        dss.chainlog.setAddress(cfg.distrChainlogKey, cfg.vestedRewardDistribution);
    }
}
