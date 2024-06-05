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
}

// Estimate `maxGas` for L1FarmProxy
contract Estimate is Script {
    using stdJson for string;

    function run() external {
        string memory config = ScriptTools.readInput("config"); // loads from FOUNDRY_SCRIPT_CONFIG

        Domain l1Domain = new Domain(config, getChain(string(vm.envOr("L1", string("mainnet")))));
        Domain l2Domain = new Domain(config, getChain(vm.envOr("L2", string("arbitrum_one"))));
        l1Domain.selectFork();
       
        (, address deployer,) = vm.readCallers();
        address l1Gateway = l1Domain.readConfigAddress("gateway");
        address l1Nst     = l1Domain.readConfigAddress("nst");
        address l2Gateway = l2Domain.readConfigAddress("gateway");

        bytes memory finalizeDepositCalldata = GatewayLike(l1Gateway).getOutboundCalldata({
            l1Token: l1Nst, 
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

        (uint64 gasEstimate, uint64 gasEstimateForL1, uint256 l2BaseFee, uint256 l1BaseFeeEstimate) 
            = abi.decode(res, (uint64,uint64,uint256,uint256));


        uint256 l2g = gasEstimate - gasEstimateForL1;
        uint256 l1p = 16 * l1BaseFeeEstimate;
        uint256 l1s = gasEstimateForL1 * l2BaseFee / l1p;

        // maxGas is estimated based on the formula in https://docs.arbitrum.io/build-decentralized-apps/how-to-estimate-gas#breaking-down-the-formula
        // where we use:
        // * (L1P)_max = 16 * 100 gwei
        // * (P)_min = 0.01 gwei
        uint256 maxGas = l2g + (16 * 100 gwei * l1s) / 0.01 gwei; 

        console2.log("L2G:", l2g);
        console2.log("L1S:", l1s);
        console2.log("Recommended maxGas:", maxGas);
    }
}