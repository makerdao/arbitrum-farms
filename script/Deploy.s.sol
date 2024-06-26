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
import { VestedRewardsDistributionDeploy, VestedRewardsDistributionDeployParams } from "lib/endgame-toolkit/script/dependencies/VestedRewardsDistributionDeploy.sol";
import { DssVestMintableMock } from "test/mocks/DssVestMock.sol";
import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";

interface ChainLogLike {
    function getAddress(bytes32) external view returns (address);
}

interface L1GovernanceRelayLike {
    function l2GovernanceRelay() external view returns (address);
}

interface AuthLike {
    function rely(address usr) external;
}

contract Deploy is Script {
    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    Domain l1Domain;
    Domain l2Domain;
    address deployer;
    ChainLogLike chainlog;
    address owner;
    address l1GovRelay;
    address l2GovRelay;
    address l1Gateway;
    address vest;
    address stakingToken;
    address l1RewardsToken;
    address l2RewardsToken;
    address farm;
    address l2Spell;
    address l2Proxy;
    address l1Proxy;
    address vestedRewardsDistribution;

    function run() external {
        l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        config = ScriptTools.loadConfig("config");
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        (,deployer, ) = vm.readCallers();
        chainlog = ChainLogLike(l1Domain.readConfigAddress("chainlog"));
        l1GovRelay = chainlog.getAddress("ARBITRUM_GOV_RELAY");
        l2GovRelay = L1GovernanceRelayLike(payable(l1GovRelay)).l2GovernanceRelay();
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
        l2Spell = FarmProxyDeploy.deployL2ProxySpell();
        l2Proxy = FarmProxyDeploy.deployL2Proxy(deployer, l2GovRelay, farm);
        vm.stopBroadcast();

        // L1 deployment

        l1Domain.selectFork();

        vm.startBroadcast();
        l1Proxy = FarmProxyDeploy.deployL1Proxy(
            deployer,
            owner,
            l1RewardsToken,
            l2Proxy,
            l2GovRelay,
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

        ScriptTools.exportContract("deployed", "chainlog", address(chainlog));
        ScriptTools.exportContract("deployed", "farm", farm);
        ScriptTools.exportContract("deployed", "l2ProxySpell", l2Spell);
        ScriptTools.exportContract("deployed", "l2Proxy", l2Proxy);
        ScriptTools.exportContract("deployed", "l1Proxy", l1Proxy);
        ScriptTools.exportContract("deployed", "vest", vest);
        ScriptTools.exportContract("deployed", "vestedRewardsDistribution", vestedRewardsDistribution); // TODO: fix etherscan verification
        ScriptTools.exportContract("deployed", "l1GovRelay", l1GovRelay);
        ScriptTools.exportContract("deployed", "l2GovRelay", l2GovRelay);
        ScriptTools.exportContract("deployed", "l1RewardsToken", l1RewardsToken);
        ScriptTools.exportContract("deployed", "l2RewardsToken", l2RewardsToken);
        ScriptTools.exportContract("deployed", "stakingToken", stakingToken);
        ScriptTools.exportContract("deployed", "l1Gateway", l1Gateway);
    }
}
