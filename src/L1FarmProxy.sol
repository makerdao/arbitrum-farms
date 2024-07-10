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
    function transfer(address, uint256) external;
}

interface L1TokenGatewayLike {
    function inbox() external view returns (address);
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

// From https://github.com/OffchainLabs/nitro-contracts/blob/90037b996509312ef1addb3f9352457b8a99d6a6/src/libraries/AddressAliasHelper.sol
library AddressAliasHelper {
    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);

    /// @notice Utility function that converts the msg.sender viewed in the L2 to the
    /// address in the L1 that submitted a tx to the inbox
    /// @param l2Address L2 address as viewed in msg.sender
    /// @return l1Address the address in the L1 that triggered the tx to L2
    function undoL1ToL2Alias(address l2Address) internal pure returns (address l1Address) {
        unchecked {
            l1Address = address(uint160(l2Address) - offset);
        }
    }
}

contract L1FarmProxy {
    mapping (address => uint256) public wards;
    uint64  public maxGas;
    uint64  public gasPriceBid;
    uint128 public rewardThreshold;

    address public immutable rewardsToken;
    address public immutable l2Proxy;
    address public immutable feeRecipient; // L2 recipient of excess fee. Negative alias must be applied to it if the address contains code on L1
    InboxLike public immutable inbox;
    L1TokenGatewayLike public immutable l1Gateway;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event RewardAdded(uint256 reward);

    constructor(address _rewardsToken, address _l2Proxy, address _feeRecipient, address _l1Gateway) {
        rewardsToken = _rewardsToken;
        l2Proxy = _l2Proxy;
        feeRecipient = _feeRecipient;
        l1Gateway = L1TokenGatewayLike(_l1Gateway);
        inbox = InboxLike(l1Gateway.inbox());

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

    // @notice Validation of the `data` boundaries is outside the scope of this 
    // contract and is assumed to be carried out in the corresponding spell process
    function file(bytes32 what, uint256 data) external auth {
        if      (what == "maxGas")          maxGas          =  uint64(data);
        else if (what == "gasPriceBid")     gasPriceBid     =  uint64(data);
        else if (what == "rewardThreshold") rewardThreshold = uint128(data);
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

    // @notice Allow governance to recover potentially stuck tokens
    function recover(address token, address to, uint256 amount) external auth {
        GemLike(token).transfer(to, amount);
    }

    // @notice Estimate the amount of ETH consumed as msg.value from this contract to bridge the reward to the L2 proxy
    // as well as the RetryableTicket submission cost.
    // @param l1BaseFee L1 baseFee to use for the estimate. Pass 0 to use block.basefee
    // @param _maxGas Max gas to cover the L2 execution of the deposit. Pass 0 to use the stored `maxGas` value.
    // @param _gasPriceBid Gas price bid for the L2 execution of the deposit. Pass 0 to use the stored `gasPriceBid` value.
    function estimateDepositCost(
        uint256 l1BaseFee,
        uint256 _maxGas,
        uint256 _gasPriceBid
    ) public view returns (uint256 l1CallValue, uint256 maxSubmissionCost) {
        maxSubmissionCost = inbox.calculateRetryableSubmissionFee(324, l1BaseFee); // size of finalizeInboundTransfer calldata = 4 + 10*32 bytes
        (uint256 maxGas_, uint256 gasPriceBid_) = (_maxGas > 0 ? _maxGas : maxGas, _gasPriceBid > 0 ? _gasPriceBid : gasPriceBid);
        l1CallValue = maxSubmissionCost + maxGas_ * gasPriceBid_;
    }

    // @notice As this function is permissionless, it could in theory be called at a time where 
    // maxGas and/or gasPriceBid are too low for the auto-redeem of the gem deposit RetryableTicket.
    // This is mitigated by incorporating large enough safety factors in maxGas and gasPriceBid.
    // Note that in any case a failed auto-redeem can be permissionlessly retried for 7 days
    function notifyRewardAmount(uint256 reward) external {
        (uint256 maxGas_, uint256 gasPriceBid_, uint256 rewardThreshold_) = (maxGas, gasPriceBid, rewardThreshold);

        require(reward > rewardThreshold_, "L1FarmProxy/reward-too-small");

        (uint256 l1CallValue, uint256 maxSubmissionCost) = estimateDepositCost(0, maxGas_, gasPriceBid_);

        // If the address of feeRecipient has code on L1, it will be aliased by the Arbitrum Inbox, which we want to cancel out here
        address refundTo = (feeRecipient.code.length > 0) ? AddressAliasHelper.undoL1ToL2Alias(feeRecipient) : feeRecipient;

        l1Gateway.outboundTransferCustomRefund{value: l1CallValue}({
            l1Token:     rewardsToken,
            refundTo:    refundTo,
            to:          l2Proxy,
            amount:      reward,
            maxGas:      maxGas_,
            gasPriceBid: gasPriceBid_,
            data:        abi.encode(maxSubmissionCost, bytes(""))
        });

        emit RewardAdded(reward);
    }
}
