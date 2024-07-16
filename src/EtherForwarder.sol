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

contract EtherForwarder {
    address public immutable receiver;

    event Forward(uint256 amount);

    constructor(address _receiver) {
        receiver = _receiver;
    }

    receive() external payable {}

    function forward() external {
        uint256 amount = address(this).balance;
        (bool sent, ) = receiver.call{value: amount}("");
        require(sent, "EtherForwarder/failed-to-send-ether");
        emit Forward(amount);
    }
}
