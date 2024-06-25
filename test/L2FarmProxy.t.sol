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

import { L2FarmProxy } from "src/L2FarmProxy.sol";
import { FarmMock } from "test/mocks/FarmMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract L2FarmProxyTest is DssTest {

    GemMock rewardsToken;
    L2FarmProxy l2Proxy;
    address farm;

    event RewardAdded(uint256 rewards);

    function setUp() public {
        rewardsToken = new GemMock(1_000_000 ether);
        farm = address(new FarmMock(address(rewardsToken)));
        l2Proxy = new L2FarmProxy(farm);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L2FarmProxy p = new L2FarmProxy(farm);
        assertEq(address(p.farm()), farm);
        assertEq(address(p.rewardsToken()), address(rewardsToken));
        assertEq(p.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(l2Proxy), "L2FarmProxy");
    }

    function testFile() public {
        checkFileUint(address(l2Proxy), "L2FarmProxy", ["minReward"]);
    }

    function testForwardReward() public {
        l2Proxy.file("minReward", 1000 ether);

        vm.expectRevert("L2FarmProxy/reward-too-small");
        l2Proxy.forwardReward();

        rewardsToken.transfer(address(l2Proxy), 10_000 ether);
        assertEq(rewardsToken.balanceOf(farm), 0);
        assertEq(rewardsToken.balanceOf(address(l2Proxy)), 10_000 ether);

        vm.expectEmit(true, true, true, true);
        emit RewardAdded(10_000 ether);
        l2Proxy.forwardReward();

        assertEq(rewardsToken.balanceOf(farm), 10_000 ether);
        assertEq(rewardsToken.balanceOf(address(l2Proxy)), 0);
    }
}
