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

import { L1FarmProxy } from "src/L1FarmProxy.sol";
import { InboxMock } from "test/mocks/InboxMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { L1TokenGatewayMock } from "test/mocks/L1TokenGatewayMock.sol";

contract L1FarmProxyTest is DssTest {

    GemMock rewardsToken;
    L1FarmProxy l1Proxy;
    address inbox;
    address gateway;
    address escrow = address(0xeee);
    address l2Proxy = address(0x222);
    address feeRecipient = address(0xfee);

    event RewardAdded(uint256 rewards);

    function setUp() public {
        inbox = address(new InboxMock());
        gateway = address(new L1TokenGatewayMock(inbox, escrow));
        rewardsToken = new GemMock(1_000_000 ether);
        l1Proxy = new L1FarmProxy(address(rewardsToken), l2Proxy, feeRecipient, gateway);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L1FarmProxy p = new L1FarmProxy(address(rewardsToken), l2Proxy, feeRecipient, gateway);
        
        assertEq(p.rewardsToken(), address(rewardsToken));
        assertEq(p.l2Proxy(), l2Proxy);
        assertEq(p.feeRecipient(), feeRecipient);
        assertEq(address(p.l1Gateway()), gateway);
        assertEq(address(p.inbox()), inbox);
        assertEq(rewardsToken.allowance(address(p), gateway), type(uint256).max);
        assertEq(p.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(l1Proxy), "L1FarmProxy");
    }

    function testFile() public {
        checkFileUint(address(l1Proxy), "L1FarmProxy", ["maxGas", "gasPriceBid", "rewardThreshold"]);
    }

    function testAuthModifiers() public virtual {
        l1Proxy.deny(address(this));

        checkModifier(address(l1Proxy), string(abi.encodePacked("L1FarmProxy", "/not-authorized")), [
            l1Proxy.reclaim.selector,
            l1Proxy.recover.selector
        ]);
    }

    function testReclaim() public {
        (bool success,) = address(l1Proxy).call{value: 1 ether}(""); // not using deal() here, so as to check receive()
        assertTrue(success);
        address to = address(0x123);
        uint256 proxyBefore = address(l1Proxy).balance;
        uint256 toBefore = to.balance;

        l1Proxy.reclaim(to, 0.2 ether);

        assertEq(to.balance, toBefore + 0.2 ether);
        assertEq(address(l1Proxy).balance, proxyBefore - 0.2 ether);

        vm.expectRevert("L1FarmProxy/failed-to-send-ether");
        l1Proxy.reclaim(to, 1 ether); // insufficient balance
    }

    function testRecover() public {
        address receiver = address(0x123);
        rewardsToken.transfer(address(l1Proxy), 1 ether);

        assertEq(rewardsToken.balanceOf(receiver), 0);
        assertEq(rewardsToken.balanceOf(address(l1Proxy)), 1 ether);

        l1Proxy.recover(address(rewardsToken), receiver, 1 ether);

        assertEq(rewardsToken.balanceOf(receiver), 1 ether);
        assertEq(rewardsToken.balanceOf(address(l1Proxy)), 0);
    }

    function testNotifyRewardAmount() public {
        l1Proxy.file("rewardThreshold", 100 ether);

        vm.expectRevert("L1FarmProxy/reward-too-small");
        l1Proxy.notifyRewardAmount(100 ether);

        (bool success,) = address(l1Proxy).call{value: 1 ether}("");
        assertTrue(success);
        rewardsToken.transfer(address(l1Proxy), 101 ether);
        assertEq(rewardsToken.balanceOf(escrow), 0);
        assertEq(rewardsToken.balanceOf(address(l1Proxy)), 101 ether);
        uint256 ethBefore = address(l1Proxy).balance;
        (uint256 l1CallValue,) = l1Proxy.estimateDepositCost(0, 0, 0);

        vm.expectEmit(true, true, true, true);
        emit RewardAdded(101 ether);
        l1Proxy.notifyRewardAmount(101 ether);

        assertEq(rewardsToken.balanceOf(escrow), 101 ether);
        assertEq(rewardsToken.balanceOf(address(l1Proxy)), 0);
        assertEq(address(l1Proxy).balance, ethBefore - l1CallValue);
    }
}
