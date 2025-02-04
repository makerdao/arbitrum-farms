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
    function l1Gateway() external view returns (address);
    function file(bytes32 what, uint256 data) external;
}

interface L1RelayLike {
    function l2GovernanceRelay() external view returns (address);
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
    address vest;           // DssVest, assumed to have been fully init'ed for l1RewardsToken
    uint256 vestTot;
    uint256 vestBgn;
    uint256 vestTau;
    address vestedRewardsDistribution;
    address l1RewardsToken;
    address l2RewardsToken;
    address stakingToken;
    address l1Gateway;
    uint256 maxGas;            // For the L1 proxy
    uint256 gasPriceBid;       // For the L1 proxy
    uint256 rewardThreshold;   // For the L1 and L2 proxies 
    address farm;              // The L2 farm
    uint256 rewardsDuration;   // For the L2 farm
    MessageParams xchainMsg;   // For the xchain message executing the L2 spell
    bytes32 proxyChainlogKey;  // Chainlog key for the L1 proxy
    bytes32 distrChainlogKey;  // Chainlog key for vestedRewardsDistribution
}

library FarmProxyInit {
    function initProxies(
        DssInstance memory   dss,
        address              l1Proxy_,
        address              l2Proxy,
        address              etherForwarder,
        address              l2Spell,
        ProxiesConfig memory cfg
    ) internal {
        L1FarmProxyLike l1Proxy = L1FarmProxyLike(l1Proxy_);
        DssVestLike vest = DssVestLike(cfg.vest);
        VestedRewardsDistributionLike distribution = VestedRewardsDistributionLike(cfg.vestedRewardsDistribution);
        L1RelayLike l1GovRelay = L1RelayLike(dss.chainlog.getAddress("ARBITRUM_GOV_RELAY"));

        // sanity checks

        require(vest.gem()                    == cfg.l1RewardsToken, "FarmProxyInit/vest-gem-mismatch");
        require(distribution.gem()            == cfg.l1RewardsToken, "FarmProxyInit/distribution-gem-mismatch");
        require(distribution.stakingRewards() == l1Proxy_,           "FarmProxyInit/distribution-farm-mismatch");
        require(distribution.dssVest()        == cfg.vest,           "FarmProxyInit/distribution-vest-mismatch");
        require(l1Proxy.rewardsToken()        == cfg.l1RewardsToken, "FarmProxyInit/rewards-token-mismatch");
        require(l1Proxy.l2Proxy()             == l2Proxy,            "FarmProxyInit/l2-proxy-mismatch");
        require(l1Proxy.feeRecipient()        == etherForwarder,     "FarmProxyInit/fee-recipient-mismatch");
        require(l1Proxy.l1Gateway()           == cfg.l1Gateway,      "FarmProxyInit/l1-gateway-mismatch");
        require(cfg.maxGas                    <= 10_000_000_000,     "FarmProxyInit/max-gas-out-of-bounds");
        require(cfg.gasPriceBid               <= 10_000 gwei,        "FarmProxyInit/gas-price-bid-out-of-bounds");
        require(cfg.rewardThreshold           <= type(uint128).max,  "FarmProxyInit/reward-threshold-out-of-bounds");
        require(etherForwarder.code.length    == 0,                  "FarmProxyInit/forwarder-addr-has-code-on-l1");

        // setup vest

        uint256 vestId = vest.create({
            _usr: cfg.vestedRewardsDistribution,
            _tot: cfg.vestTot,
            _bgn: cfg.vestBgn,
            _tau: cfg.vestTau,
            _eta: 0,
            _mgr: address(0)
        });
        vest.restrict(vestId);
        distribution.file("vestId", vestId);

        // setup L1 proxy

        l1Proxy.file("maxGas",          cfg.maxGas);
        l1Proxy.file("gasPriceBid",     cfg.gasPriceBid);
        l1Proxy.file("rewardThreshold", cfg.rewardThreshold);

        // setup L2 proxy

        uint256 l1CallValue = cfg.xchainMsg.maxSubmissionCost + cfg.xchainMsg.maxGas * cfg.xchainMsg.gasPriceBid;

        // not strictly necessary (as the retryable ticket creation would otherwise fail) 
        // but makes the eth balance requirement more explicit
        require(address(l1GovRelay).balance >= l1CallValue, "FarmProxyInit/insufficient-relay-balance");

        l1GovRelay.relay({
            target:            l2Spell,
            targetData:        abi.encodeCall(L2FarmProxySpell.init, (
                l2Proxy,
                etherForwarder,
                cfg.l2RewardsToken,
                cfg.stakingToken,
                cfg.farm,
                cfg.rewardThreshold,
                cfg.rewardsDuration
            )),
            l1CallValue:       l1CallValue,
            maxGas:            cfg.xchainMsg.maxGas,
            gasPriceBid:       cfg.xchainMsg.gasPriceBid,
            maxSubmissionCost: cfg.xchainMsg.maxSubmissionCost
        });

        // update chainlog

        dss.chainlog.setAddress(cfg.proxyChainlogKey, l1Proxy_);
        dss.chainlog.setAddress(cfg.distrChainlogKey, cfg.vestedRewardsDistribution);
    }
}
