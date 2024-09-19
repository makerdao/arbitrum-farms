// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

contract InboxMock {
    function calculateRetryableSubmissionFee(
        uint256 dataLength,
        uint256 baseFee
    ) external pure returns (uint256 fee) {
        fee = (1400 + 6 * dataLength) * (baseFee == 0 ? 30 gwei : baseFee);
    }
}
