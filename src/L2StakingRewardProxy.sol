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

interface FarmLike {
    function notifyRewardAmount(uint256 reward) external;
}

interface GemLike {
    function transfer(address, uint256) external;
}

contract L2StakingRewardProxy {
    mapping (address => uint256) public wards;
    uint256 public minReward;

    GemLike  public immutable gem;
    FarmLike public immutable farm;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

    constructor(address _gem, address _farm) {
        gem = GemLike(_gem);
        farm = FarmLike(_farm);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "L2StakingRewardProxy/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if   (what == "minReward") minReward = data;
        else revert("L2StakingRewardProxy/file-unrecognized-param");
        emit File(what, data);
    }

    // @notice `reward` must exceed a minimum threshold to reduce the impact of calling 
    // this function too frequently in an attempt to reduce the rewardRate of the farm
    function notifyRewardAmount(uint256 reward) external {
        require(reward >= minReward, "L2StakingRewardProxy/reward-too-small");
        gem.transfer(address(farm), reward);
        farm.notifyRewardAmount(reward);
    }
}