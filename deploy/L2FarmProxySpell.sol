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

import { L2FarmProxy } from "src/L2FarmProxy.sol";

interface FarmLike {
    function setRewardsDistribution(address) external;
    function setRewardsDuration(uint256) external;
}

// A reusable L2 spell to be used by the L2GovernanceRelay to exert admin control over L2FarmProxy
contract L2FarmProxySpell {
    L2FarmProxy public immutable l2Proxy;
    constructor(address l2Proxy_) {
        l2Proxy = L2FarmProxy(l2Proxy_);
    }

    function rely(address usr) external { l2Proxy.rely(usr); }
    function deny(address usr) external { l2Proxy.deny(usr); }
    function file(bytes32 what, uint256 data) external { l2Proxy.file(what, data); }

    function init(uint256 minReward, uint256 rewardsDuration) external {
        l2Proxy.file("minReward", minReward);
    
        FarmLike farm = FarmLike(address(l2Proxy.farm()));
        farm.setRewardsDistribution(address(l2Proxy));
        farm.setRewardsDuration(rewardsDuration);
    }
}
