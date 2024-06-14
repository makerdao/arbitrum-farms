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

    function setUp() public {
        inbox = address(new InboxMock());
        gateway = address(new L1TokenGatewayMock(escrow));
        rewardsToken = new GemMock(1_000_000 ether);
        l1Proxy = new L1FarmProxy(address(rewardsToken), l2Proxy, feeRecipient, inbox, gateway);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L1FarmProxy g = new L1FarmProxy(address(rewardsToken), l2Proxy, feeRecipient, inbox, gateway);
        
        assertEq(g.rewardsToken(), address(rewardsToken));
        assertEq(g.l2Proxy(), l2Proxy);
        assertEq(g.feeRecipient(), feeRecipient);
        assertEq(address(g.inbox()), inbox);
        assertEq(address(g.l1Gateway()), gateway);
        assertEq(rewardsToken.allowance(address(g), gateway), type(uint256).max);
        assertEq(g.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(l1Proxy), "L1FarmProxy");
    }

    function testFile() public {
        checkFileUint(address(l1Proxy), "L1FarmProxy", ["maxGas", "gasPriceBid", "minReward"]);
    }

    function testAuthModifiers() public virtual {
        l1Proxy.deny(address(this));

        checkModifier(address(l1Proxy), string(abi.encodePacked("L1FarmProxy", "/not-authorized")), [
            l1Proxy.reclaim.selector
        ]);
    }

    function testReclaim() public {
        (bool success,) = address(l1Proxy).call{value: 1 ether}(""); // not using deal() here, so as to check payable fallback
        assertTrue(success);
        address to = address(0x123);
        uint256 proxyBefore = address(l1Proxy).balance;
        uint256 toBefore = to.balance;

        l1Proxy.reclaim(to, 0.2 ether);

        assertEq(to.balance, toBefore + 0.2 ether);
        assertEq(address(l1Proxy).balance, proxyBefore - 0.2 ether);

        vm.expectRevert("L1FarmProxy/failed-to-send-ether");
        l1Proxy.reclaim(address(this), 0.2 ether); // no fallback
    }

    function testNotifyRewardAmount() public {
        vm.expectRevert("L1FarmProxy/reward-too-small");
        l1Proxy.notifyRewardAmount(0);

        l1Proxy.file("minReward", 1000 ether);

        vm.expectRevert("L1FarmProxy/reward-too-small");
        l1Proxy.notifyRewardAmount(500 ether);

        (bool success,) = address(l1Proxy).call{value: 1 ether}("");
        assertTrue(success);
        rewardsToken.transfer(address(l1Proxy), 1000 ether);
        uint256 ethBefore = address(l1Proxy).balance;
        (uint256 l1CallValue,) = l1Proxy.estimateDepositCost(0, 0, 0);

        l1Proxy.notifyRewardAmount(1000 ether);

        assertEq(rewardsToken.balanceOf(escrow), 1000 ether);
        assertEq(rewardsToken.balanceOf(address(l1Proxy)), 0);
        assertEq(address(l1Proxy).balance, ethBefore - l1CallValue);
    }
}
