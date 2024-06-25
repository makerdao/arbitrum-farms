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

interface TokenLike {
    function transferFrom(address, address, uint256) external;
}

contract L1TokenGatewayMock {
    address public immutable inbox;
    address public immutable escrow;

    constructor(
        address _inbox,
        address _escrow
    ) {
        inbox = _inbox;
        escrow = _escrow;
    }

    function outboundTransferCustomRefund(
        address l1Token,
        address /* refundTo */,
        address /* to */,
        uint256 amount,
        uint256 /* maxGas */,
        uint256 /* gasPriceBid */,
        bytes calldata /* data */
    ) public payable returns (bytes memory res) {
        TokenLike(l1Token).transferFrom(msg.sender, escrow, amount);
        res = abi.encode(0);
    }
}
