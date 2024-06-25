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

interface L2FarmProxyLike {
    function rewardsToken() external view returns (address);
    function farm() external view returns (address);
    function rely(address) external;
    function deny(address) external;
    function file(bytes32, uint256) external;
}

interface FarmLike {
    function setRewardsDistribution(address) external;
    function setRewardsDuration(uint256) external;
}

// A reusable L2 spell to be used by the L2GovernanceRelay to exert admin control over L2 farm proxies
contract L2FarmProxySpell {

    function rely(address l2Proxy, address usr) external { L2FarmProxyLike(l2Proxy).rely(usr); }
    function deny(address l2Proxy, address usr) external { L2FarmProxyLike(l2Proxy).deny(usr); }
    function file(address l2Proxy, bytes32 what, uint256 data) external { L2FarmProxyLike(l2Proxy).file(what, data); }

    function init(
        address l2Proxy,
        address rewardsToken,
        address farm,
        uint256 minReward,
        uint256 rewardsDuration
    ) external {
        require(L2FarmProxyLike(l2Proxy).rewardsToken() == rewardsToken, "L2FarmProxySpell/rewards-token-mismatch");
        require(L2FarmProxyLike(l2Proxy).farm() == farm, "L2FarmProxySpell/farm-mismatch");

        L2FarmProxyLike(l2Proxy).file("minReward", minReward);
    
        FarmLike(farm).setRewardsDistribution(l2Proxy);
        FarmLike(farm).setRewardsDuration(rewardsDuration);
    }
}
