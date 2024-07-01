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

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { Domain } from "dss-test/domains/Domain.sol";

interface GatewayLike {
    function getOutboundCalldata(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure returns (bytes memory);
    function counterpartGateway() external view returns (address);
}

interface ChainLogLike {
    function getAddress(bytes32) external view returns (address);
}

// Estimate `maxGas` for L1FarmProxy
contract Estimate is Script {
    using stdJson for string;

    uint256 constant MAX_L1_BASE_FEE_ESTIMATE = 1 gwei; // worst-case estimate for l1BaseFeeEstimate (representing the blob base fee) returned from https://github.com/OffchainLabs/nitro-contracts/blob/90037b996509312ef1addb3f9352457b8a99d6a6/src/node-interface/NodeInterface.sol#L95
    bool    constant USE_DAI_BRIDGE = true;             // set to true if the new token gateway isn't yet initiated

    function run() external {
        // Note: this script should not be run on testnet as l1BaseFeeEstimate can sometimes be 0 on sepolia
        StdChains.Chain memory l1Chain = getChain(string("mainnet"));
        StdChains.Chain memory l2Chain = getChain(string("arbitrum_one"));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();
       
        (, address deployer,) = vm.readCallers();
        ChainLogLike chainlog = ChainLogLike(l1Domain.readConfigAddress("chainlog"));
        address l1Gateway;
        address l1Token;
        if (USE_DAI_BRIDGE) {
            l1Gateway = chainlog.getAddress("ARBITRUM_DAI_BRIDGE");
            l1Token = chainlog.getAddress("MCD_DAI");
        } else {
            l1Gateway = chainlog.getAddress("ARBITRUM_TOKEN_BRIDGE");
            l1Token = l1Domain.readConfigAddress("rewardsToken");
        }
        address l2Gateway = GatewayLike(l1Gateway).counterpartGateway();

        bytes memory finalizeDepositCalldata = GatewayLike(l1Gateway).getOutboundCalldata({
            l1Token: l1Token, 
            from:    deployer,
            to:      address(uint160(uint256(keccak256(abi.encode(deployer, block.timestamp))))), // a pseudo-random address used as "fresh" destination address,
            amount:  uint128(uint256(keccak256(abi.encode(deployer)))), // very large random-looking number => costlier calldata 
            data:    ""
        });
        bytes memory data = abi.encodeWithSignature(
            "gasEstimateComponents(address,bool,bytes)", 
            l2Gateway,
            false,
            finalizeDepositCalldata
        );
        address l2Sender = address(uint160(l1Gateway) + uint160(0x1111000000000000000000000000000000001111));

        l2Domain.selectFork();
        bytes memory res = vm.rpc("eth_call", string(abi.encodePacked(
            "[{\"to\": \"", 
            vm.toString(address(0xc8)), // NodeInterface
            "\", \"from\": \"",
            vm.toString(l2Sender),
            "\", \"data\": \"",    
            vm.toString(data),
            "\"}]"
        )));

        (uint64 gasEstimate, uint64 gasEstimateForL1,, uint256 l1BaseFeeEstimate) 
            = abi.decode(res, (uint64,uint64,uint256,uint256));

        uint256 l2ExecutionGas = gasEstimate - gasEstimateForL1;
        uint256 maxExtraGasForDataPosting = gasEstimateForL1 * MAX_L1_BASE_FEE_ESTIMATE / l1BaseFeeEstimate;
        uint256 maxGas = l2ExecutionGas + maxExtraGasForDataPosting; 

        console2.log("    L2 Execution Gas:", l2ExecutionGas);
        console2.log("Cur Data Posting Gas:", gasEstimateForL1);
        console2.log("Max Data Posting Gas:", maxExtraGasForDataPosting);
        console2.log("  Recommended maxGas:", maxGas);
    }
}
