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
import { VestedRewardsDistributionDeploy, VestedRewardsDistributionDeployParams } from "lib/endgame-toolkit/script/dependencies/VestedRewardsDistributionDeploy.sol";
import { DssVestMintableMock } from "test/mocks/DssVestMock.sol";
import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";

interface ChainLogLike {
    function getAddress(bytes32) external view returns (address);
}

interface AuthLike {
    function rely(address usr) external;
}

contract DeployL1FarmProxy is Script {
    using stdJson for string;

    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    string deps;
    Domain l1Domain;
    Domain l2Domain;
    address deployer;
    ChainLogLike chainlog;
    address owner;
    address l1Gateway;
    address vest;
    address stakingToken;
    address l1RewardsToken;
    address l2RewardsToken;
    address l1Proxy;
    address vestedRewardsDistribution;

    function run() external {
        l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        config = ScriptTools.loadConfig("config");
        deps   = ScriptTools.loadDependencies();
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        (,deployer, ) = vm.readCallers();
        chainlog = ChainLogLike(l1Domain.readConfigAddress("chainlog"));
        l1Gateway = chainlog.getAddress("ARBITRUM_TOKEN_BRIDGE");
        l1RewardsToken = l1Domain.readConfigAddress("rewardsToken");

        if (keccak256(bytes(l1Chain.chainAlias)) == keccak256("mainnet")) {
            owner = chainlog.getAddress("MCD_PAUSE_PROXY");
            vest = l1Domain.readConfigAddress("vest");
        } else {
            owner = deployer;
            vm.startBroadcast();
            vest = address(new DssVestMintableMock(l1RewardsToken));
            DssVestMintableMock(vest).file("cap", type(uint256).max);
            AuthLike(l1RewardsToken).rely(address(vest));
            vm.stopBroadcast();
        }

        // L1 deployment

        vm.startBroadcast();
        l1Proxy = FarmProxyDeploy.deployL1Proxy(
            deployer,
            owner,
            l1RewardsToken,
            deps.readAddress(".l2Proxy"),
            deps.readAddress(".etherForwarder"),
            l1Gateway
        );
        VestedRewardsDistributionDeployParams memory distributionParams = VestedRewardsDistributionDeployParams({
            deployer:  deployer,
            owner:     owner,
            vest:      vest,
            rewards:   l1Proxy
        });
        vestedRewardsDistribution = (VestedRewardsDistributionDeploy.deploy(distributionParams));
        vm.stopBroadcast();

        // Export contract addresses

        // TODO: load the existing json so this is not required
        ScriptTools.exportContract("deployed", "chainlog", deps.readAddress(".chainlog"));
        ScriptTools.exportContract("deployed", "l2ProxySpell", deps.readAddress(".l2ProxySpell"));
        ScriptTools.exportContract("deployed", "etherForwarder", deps.readAddress(".etherForwarder"));
        ScriptTools.exportContract("deployed", "l1GovRelay", deps.readAddress(".l1GovRelay"));
        ScriptTools.exportContract("deployed", "l2GovRelay", deps.readAddress(".l2GovRelay"));
        ScriptTools.exportContract("deployed", "farm", deps.readAddress(".farm"));
        ScriptTools.exportContract("deployed", "l2Proxy", deps.readAddress(".l2Proxy"));        
        ScriptTools.exportContract("deployed", "l2RewardsToken", deps.readAddress(".l2RewardsToken"));
        ScriptTools.exportContract("deployed", "stakingToken", deps.readAddress(".stakingToken"));

        ScriptTools.exportContract("deployed", "l1Proxy", l1Proxy);
        ScriptTools.exportContract("deployed", "vest", vest);
        ScriptTools.exportContract("deployed", "vestedRewardsDistribution", vestedRewardsDistribution);
        ScriptTools.exportContract("deployed", "l1RewardsToken", l1RewardsToken);
        ScriptTools.exportContract("deployed", "l1Gateway", l1Gateway);
    }
}
