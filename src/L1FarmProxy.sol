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

interface GemLike {
    function approve(address, uint256) external;
}

interface L1TokenGatewayLike {
    function outboundTransferCustomRefund(
        address l1Token,
        address refundTo,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (bytes memory);
}

interface InboxLike {
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee) external view returns (uint256);
}

contract L1FarmProxy {
    mapping (address => uint256) public wards;

    uint64  public maxGas = 70_000_000; // determined by running deploy/Estimate.s.sol and adding some margin
    uint192 public gasPriceBid = 0.1 gwei; // 0.01 gwei arbitrum-one gas price floor * 10x factor

    address public immutable rewardsToken;
    address public immutable l2Proxy;
    address public immutable feeRecipient;
    InboxLike public immutable inbox;
    L1TokenGatewayLike public immutable l1Gateway;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

    constructor(address _rewardsToken, address _l2Proxy, address _feeRecipient, address _inbox, address _l1Gateway) {
        rewardsToken = _rewardsToken;
        l2Proxy = _l2Proxy;
        feeRecipient = _feeRecipient;
        inbox = InboxLike(_inbox);
        l1Gateway = L1TokenGatewayLike(_l1Gateway);

        GemLike(_rewardsToken).approve(_l1Gateway, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "L1FarmProxy/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if      (what == "maxGas")      maxGas      =  uint64(data);
        else if (what == "gasPriceBid") gasPriceBid = uint192(data);
        else revert("L1FarmProxy/file-unrecognized-param");
        emit File(what, data);
    }

    // @notice Allow contract to receive ether
    receive() external payable {}

    // @notice Allow governance to reclaim stored ether
    function reclaim(address receiver, uint256 amount) external auth {
        (bool sent,) = receiver.call{value: amount}("");
        require(sent, "L1FarmProxy/failed-to-send-ether");
    }

    // @notice As this function is permissionless, it could in theory be called at a time where 
    // maxGas and/or gasPriceBid are too low for the auto-redeem of the gem deposit RetryableTicket.
    // This is mitigated by incorporating large enough safety factors in maxGas and gasPriceBid.
    // Note that in any case a failed auto-redeem can be permissionlessly retried for 7 days
    function notifyRewardAmount(uint256 reward) external {
        require(reward > 0, "L1FarmProxy/no-reward"); // prevent wasting gas for no-op

        (uint256 maxGas_, uint256 gasPriceBid_) = (maxGas, gasPriceBid);
        uint256 maxSubmissionCost = inbox.calculateRetryableSubmissionFee(324, 0); // size of finalizeInboundTransfer calldata = 4 + 10*32 bytes
        uint256 l1CallValue = maxSubmissionCost + maxGas_ * gasPriceBid_;

        l1Gateway.outboundTransferCustomRefund{value: l1CallValue}({
            l1Token:     rewardsToken,
            refundTo:    feeRecipient,
            to:          l2Proxy,
            amount:      reward,
            maxGas:      maxGas_,
            gasPriceBid: gasPriceBid_,
            data:        abi.encode(maxSubmissionCost, bytes(""))
        });
    }
}