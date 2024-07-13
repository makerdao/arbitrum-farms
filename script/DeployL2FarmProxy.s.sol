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
import { StakingRewardsDeploy, StakingRewardsDeployParams } from "lib/endgame-toolkit/script/dependencies/StakingRewardsDeploy.sol";
import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";

interface ChainLogLike {
    function getAddress(bytes32) external view returns (address);
}

interface L1GovernanceRelayLike {
    function l2GovernanceRelay() external view returns (address);
}

contract DeployL2FarmProxy is Script {
    using stdJson for string;

    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    string deps;
    Domain l1Domain;
    Domain l2Domain;
    address deployer;
    ChainLogLike chainlog;
    address l1GovRelay;
    address l2GovRelay;
    address stakingToken;
    address l2RewardsToken;
    address farm;
    address l2Proxy;
    
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
        l1GovRelay = chainlog.getAddress("ARBITRUM_GOV_RELAY");
        l2GovRelay = L1GovernanceRelayLike(payable(l1GovRelay)).l2GovernanceRelay();

        // L2 deployment

        l2Domain.selectFork();

        stakingToken = l2Domain.readConfigAddress("stakingToken");
        l2RewardsToken = l2Domain.readConfigAddress("rewardsToken");
        StakingRewardsDeployParams memory farmParams = StakingRewardsDeployParams({
            owner: l2GovRelay,
            stakingToken: stakingToken,
            rewardsToken: l2RewardsToken
        });

        vm.startBroadcast();
        farm = StakingRewardsDeploy.deploy(farmParams);
        l2Proxy = FarmProxyDeploy.deployL2Proxy(deployer, l2GovRelay, farm);
        vm.stopBroadcast();

        // Export contract addresses

        // TODO: load the existing json so this is not required
        ScriptTools.exportContract("deployed", "chainlog", deps.readAddress(".chainlog"));
        ScriptTools.exportContract("deployed", "l2ProxySpell", deps.readAddress(".l2ProxySpell"));
        ScriptTools.exportContract("deployed", "etherForwarder", deps.readAddress(".etherForwarder"));
        ScriptTools.exportContract("deployed", "l1GovRelay", deps.readAddress(".l1GovRelay"));
        ScriptTools.exportContract("deployed", "l2GovRelay", deps.readAddress(".l2GovRelay"));

        ScriptTools.exportContract("deployed", "farm", farm);
        ScriptTools.exportContract("deployed", "l2Proxy", l2Proxy);        
        ScriptTools.exportContract("deployed", "l2RewardsToken", l2RewardsToken);
        ScriptTools.exportContract("deployed", "stakingToken", stakingToken);
    }
}
