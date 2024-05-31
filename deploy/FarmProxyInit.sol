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
    function create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) external returns (uint256 id);
    function restrict(uint256 _id) external;
}

interface VestedRewardsDistributionLike {
    function file(bytes32 what, uint256 data) external;
}

interface L1FarmProxyLike {
    function rewardsToken() external view returns (address);
    function l2Proxy() external view returns (address);
    function feeRecipient() external view returns (address);
    function inbox() external view returns (address);
    function l1Gateway() external view returns (address);
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
    uint256 minReward;
    uint256 rewardsDuration;
    MessageParams xchainMsg;
}

library FarmProxyInit {
    function initProxies(
        DssInstance memory         dss,
        address                    l1Proxy_,
        L2FarmProxyInstance memory l2ProxyInstance,
        ProxiesConfig memory         cfg
    ) internal {
        L1FarmProxyLike l1Proxy = L1FarmProxyLike(l1Proxy_);

        // sanity checks

        require(l1Proxy.rewardsToken() == cfg.rewardsToken, "FarmProxyInit/gem-mismatch");
        require(l1Proxy.l2Proxy() == cfg.l2Proxy, "FarmProxyInit/l2-proxy-mismatch");
        require(l1Proxy.feeRecipient() == cfg.feeRecipient, "FarmProxyInit/fee-recipient-mismatch");
        require(l1Proxy.inbox() == cfg.inbox, "FarmProxyInit/inbox-mismatch");
        require(l1Proxy.l1Gateway() == cfg.l1Gateway, "FarmProxyInit/l1-gateway-mismatch");

        // setup vest

        DssVestLike vest = DssVestLike(cfg.vest);
        uint256 vestId = vest.create({
            _usr: cfg.vestedRewardDistribution,
            _tot: cfg.vestTot,
            _bgn: cfg.vestBgn,
            _tau: cfg.vestTau,
            _eta: 0,
            _mgr: cfg.vestMgr
        });
        vest.restrict(vestId);
        VestedRewardsDistributionLike(cfg.vestedRewardDistribution).file("vestId", vestId);

        // relay L2 spell

        L1RelayLike l1GovRelay = L1RelayLike(dss.chainlog.getAddress("ARBITRUM_GOV_RELAY"));
        uint256 l1CallValue = cfg.xchainMsg.maxSubmissionCost + cfg.xchainMsg.maxGas * cfg.xchainMsg.gasPriceBid;

        // not strictly necessary (as the retryable ticket creation would otherwise fail) 
        // but makes the eth balance requirement more explicit
        require(address(l1GovRelay).balance >= l1CallValue, "FarmProxyInit/insufficient-relay-balance");

        l1GovRelay.relay({
            target:            l2ProxyInstance.spell,
            targetData:        abi.encodeCall(L2FarmProxySpell.init, (cfg.minReward, cfg.rewardsDuration)),
            l1CallValue:       l1CallValue,
            maxGas:            cfg.xchainMsg.maxGas,
            gasPriceBid:       cfg.xchainMsg.gasPriceBid,
            maxSubmissionCost: cfg.xchainMsg.maxSubmissionCost
        });
        dss.chainlog.setAddress("ARBITRUM_L1_FARM_PROXY", l1Proxy_);
    }
}
