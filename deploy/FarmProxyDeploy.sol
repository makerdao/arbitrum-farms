// SPDX-FileCopyrightText: © 2024 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity >=0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { L2FarmProxySpell } from "./L2FarmProxySpell.sol";
import { L1FarmProxy } from "src/L1FarmProxy.sol";
import { L2FarmProxy } from "src/L2FarmProxy.sol";
import { AddressAliasHelper } from "./utils/AddressAliasHelper.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface L1RelayLike {
    function l2GovernanceRelay() external view returns (address);
}

library FarmProxyDeploy {
    function deployL1Proxy(
        address deployer,
        address owner,
        address chainlog,
        address rewardsToken,
        address l2Proxy,
        address l1Gateway
    ) internal returns (address l1Proxy) {
        // if the address of l2GovRelay has code on L1, it will be aliased, which we want to cancel out
        address l2GovRelay = L1RelayLike(ChainlogLike(chainlog).getAddress("ARBITRUM_GOV_RELAY")).l2GovernanceRelay();
        address feeRecipient = (l2GovRelay.code.length > 0) ? AddressAliasHelper.undoL1ToL2Alias(l2GovRelay) : l2GovRelay;

        l1Proxy = address(new L1FarmProxy(rewardsToken, l2Proxy, feeRecipient, l1Gateway));
        ScriptTools.switchOwner(l1Proxy, deployer, owner);
    }

    function deployL2Proxy(
        address deployer,
        address owner,
        address farm
    ) internal returns (address l2Proxy) {
        l2Proxy = address(new L2FarmProxy(farm));
        ScriptTools.switchOwner(l2Proxy, deployer, owner);
    }

    function deployL2ProxySpell() internal returns (address l2Spell) {
        l2Spell = address(new L2FarmProxySpell());
    }
}
