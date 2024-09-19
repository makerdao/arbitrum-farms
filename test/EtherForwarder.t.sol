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

import { EtherForwarder } from "src/EtherForwarder.sol";

contract EtherForwarderTest is DssTest {

    EtherForwarder forwarder;
    address receiver = address(123);

    event Forward(uint256 amount);

    function setUp() public {
        forwarder = new EtherForwarder(receiver);
        assertEq(forwarder.receiver(), receiver);
    }

    function testForward() public {
        (bool success,) = address(forwarder).call{value: 1 ether}(""); // not using deal() here, so as to check receive()
        assertTrue(success);
        uint256 receiverBefore = receiver.balance;

        vm.expectEmit(true, true, true, true);
        emit Forward(1 ether);
        forwarder.forward();

        assertEq(receiver.balance, receiverBefore + 1 ether);
        assertEq(address(forwarder).balance, 0);

        EtherForwarder badForwarder = new EtherForwarder(address(this));
        vm.expectRevert("EtherForwarder/failed-to-send-ether");
        badForwarder.forward();
    }
}
