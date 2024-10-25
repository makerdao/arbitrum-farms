// L1FarmProxy.spec

using GemMock as gem;
using Auxiliar as aux;
using L1TokenGatewayMock as l1Gateway;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function maxGas() external returns (uint64) envfree;
    function gasPriceBid() external returns (uint64) envfree;
    function rewardThreshold() external returns (uint128) envfree;
    // immutables
    function rewardsToken() external returns (address) envfree;
    function l2Proxy() external returns (address) envfree;
    function feeRecipient() external returns (address) envfree;
    function l1Gateway() external returns (address) envfree;
    //
    function aux.getDataHash(uint256) external returns (bytes32) envfree;
    function gem.allowance(address,address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function l1Gateway.escrow() external returns (address) envfree;
    function l1Gateway.lastL1Token() external returns (address) envfree;
    function l1Gateway.lastRefundTo() external returns (address) envfree;
    function l1Gateway.lastTo() external returns (address) envfree;
    function l1Gateway.lastAmount() external returns (uint256) envfree;
    function l1Gateway.lastMaxGas() external returns (uint256) envfree;
    function l1Gateway.lastGasPriceBid() external returns (uint256) envfree;
    function l1Gateway.lastDataHash() external returns (bytes32) envfree;
    function l1Gateway.lastValue() external returns (uint256) envfree;
    //
    function _.transfer(address,uint256) external => DISPATCHER(true);
    function _.transferFrom(address,address,uint256) external => DISPATCHER(true);
}

persistent ghost bool success;
hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    success = rc != 0;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint maxGasBefore = maxGas();
    mathint gasPriceBidBefore = gasPriceBid();
    mathint rewardThresholdBefore = rewardThreshold();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint maxGasAfter = maxGas();
    mathint gasPriceBidAfter = gasPriceBid();
    mathint rewardThresholdAfter = rewardThreshold();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "Assert 1";
    assert maxGasAfter != maxGasBefore => f.selector == sig:file(bytes32,uint256).selector, "Assert 2";
    assert gasPriceBidAfter != gasPriceBidBefore => f.selector == sig:file(bytes32,uint256).selector, "Assert 3";
    assert rewardThresholdAfter != rewardThresholdBefore => f.selector == sig:file(bytes32,uint256).selector, "Assert 4";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 what, uint256 data) {
    env e;

    mathint maxGasBefore = maxGas();
    mathint gasPriceBidBefore = gasPriceBid();
    mathint rewardThresholdBefore = rewardThreshold();

    file(e, what, data);

    mathint maxGasAfter = maxGas();
    mathint gasPriceBidAfter = gasPriceBid();
    mathint rewardThresholdAfter = rewardThreshold();

    assert what == to_bytes32(0x6d61784761730000000000000000000000000000000000000000000000000000) => maxGasAfter == data % (max_uint64 + 1), "Assert 1";
    assert what != to_bytes32(0x6d61784761730000000000000000000000000000000000000000000000000000) => maxGasAfter == maxGasBefore, "Assert 2";
    assert what == to_bytes32(0x6761735072696365426964000000000000000000000000000000000000000000) => gasPriceBidAfter == data % (max_uint64 + 1), "Assert 3";
    assert what != to_bytes32(0x6761735072696365426964000000000000000000000000000000000000000000) => gasPriceBidAfter == gasPriceBidBefore, "Assert 4";
    assert what == to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000) => rewardThresholdAfter == data % (max_uint128 + 1), "Assert 5";
    assert what != to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000) => rewardThresholdAfter == rewardThresholdBefore, "Assert 6";
}

// Verify revert rules on file
rule file_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6d61784761730000000000000000000000000000000000000000000000000000) &&
                   what != to_bytes32(0x6761735072696365426964000000000000000000000000000000000000000000) &&
                   what != to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000);

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting reclaim
rule reclaim(address receiver, uint256 amount) {
    env e;

    // require receiver == rec;

    mathint balanceProxyBefore = nativeBalances[currentContract];
    mathint balanceReceiverBefore = nativeBalances[receiver];
    // ERC20 assumption
    require gem.totalSupply() >= balanceProxyBefore + balanceReceiverBefore;

    reclaim(e, receiver, amount);

    mathint balanceProxyAfter = nativeBalances[currentContract];
    mathint balanceReceiverAfter = nativeBalances[receiver];

    assert currentContract != receiver => balanceProxyAfter == balanceProxyBefore - amount, "Assert 1";
    assert currentContract != receiver => balanceReceiverAfter == balanceReceiverBefore + amount, "Assert 2";
    assert currentContract == receiver => balanceProxyAfter == balanceProxyBefore, "Assert 3";
}

// Verify revert rules on reclaim
rule reclaim_revert(address receiver, uint256 amount) {
    env e;

    mathint balanceProxy = nativeBalances[currentContract];
    // Practical assumption
    require nativeBalances[receiver] + amount <= max_uint256;

    mathint wardsSender = wards(e.msg.sender);

    reclaim@withrevert(e, receiver, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = balanceProxy < amount;
    bool revert4 = !success;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}

// Verify correct storage changes for non reverting recover
rule recover(address token, address receiver, uint256 amount) {
    env e;

    require token == gem;

    mathint tokenBalanceOfProxyBefore = gem.balanceOf(currentContract);
    mathint tokenBalanceOfReceiverBefore = gem.balanceOf(receiver);
    // ERC20 assumption
    require gem.totalSupply() >= tokenBalanceOfProxyBefore + tokenBalanceOfReceiverBefore;

    recover(e, token, receiver, amount);

    mathint tokenBalanceOfProxyAfter = gem.balanceOf(currentContract);
    mathint tokenBalanceOfReceiverAfter = gem.balanceOf(receiver);

    assert currentContract != receiver => tokenBalanceOfProxyAfter == tokenBalanceOfProxyBefore - amount, "Assert 1";
    assert currentContract != receiver => tokenBalanceOfReceiverAfter == tokenBalanceOfReceiverBefore + amount, "Assert 2";
    assert currentContract == receiver => tokenBalanceOfProxyAfter == tokenBalanceOfProxyBefore, "Assert 3";
}

// Verify revert rules on recover
rule recover_revert(address token, address receiver, uint256 amount) {
    env e;

    mathint tokenBalanceOfProxy = gem.balanceOf(currentContract);
    // ERC20 assumption
    require gem.totalSupply() >= tokenBalanceOfProxy + gem.balanceOf(receiver);

    mathint wardsSender = wards(e.msg.sender);

    recover@withrevert(e, token, receiver, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = tokenBalanceOfProxy < amount;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct estimateDepositCost getter behavior
rule estimateDepositCost(uint256 l1BaseFee, uint256 _maxGas, uint256 _gasPriceBid) {
    env e;

    mathint maxSubmissionCost = (1400 + 6 * 324) * (l1BaseFee == 0 ? 30 * 10^9 : l1BaseFee);
    mathint l1CallValue = maxSubmissionCost + (_maxGas > 0 ? _maxGas : maxGas()) * (_gasPriceBid > 0 ? _gasPriceBid : gasPriceBid());

    mathint l1CallValueRet; mathint maxSubmissionCostRet;
    l1CallValueRet, maxSubmissionCostRet = estimateDepositCost(e, l1BaseFee, _maxGas, _gasPriceBid);

    assert l1CallValueRet == l1CallValue, "Assert 1";
    assert maxSubmissionCostRet == maxSubmissionCost, "Assert 2";
}

// Verify correct storage changes for non reverting notifyRewardAmount
rule notifyRewardAmount(uint256 reward) {
    env e;

    address rewardsToken = rewardsToken();
    address l2Proxy = l2Proxy();
    address feeRecipient = feeRecipient();
    mathint maxGas = maxGas();
    mathint gasPriceBid = gasPriceBid();
    uint256 maxSubmissionCost = (1400 + 6 * 324) * 30*10^9;
    bytes32 dataHash = aux.getDataHash(maxSubmissionCost);
    mathint l1CallValue = maxSubmissionCost + maxGas * gasPriceBid;

    notifyRewardAmount(e, reward);

    address lastL1TokenAfter = l1Gateway.lastL1Token();
    address lastRefundToAfter = l1Gateway.lastRefundTo();
    address lastToAfter = l1Gateway.lastTo();
    mathint lastAmountAfter = l1Gateway.lastAmount();
    mathint lastMaxGasAfter = l1Gateway.lastMaxGas();
    mathint lastGasPriceBidAfter = l1Gateway.lastGasPriceBid();
    bytes32 lastDataHashAfter = l1Gateway.lastDataHash();
    mathint lastValueAfter = l1Gateway.lastValue();

    assert lastL1TokenAfter == rewardsToken, "Assert 1";
    assert lastRefundToAfter == feeRecipient, "Assert 2";
    assert lastToAfter == l2Proxy, "Assert 3";
    assert lastAmountAfter == to_mathint(reward), "Assert 4";
    assert lastMaxGasAfter == maxGas, "Assert 5";
    assert lastGasPriceBidAfter == gasPriceBid, "Assert 6";
    assert lastDataHashAfter == dataHash, "Assert 7";
    assert lastValueAfter == l1CallValue, "Assert 8";
}

// Verify revert rules on notifyRewardAmount
rule notifyRewardAmount_revert(uint256 reward) {
    env e;

    require rewardsToken() == gem;

    mathint maxGas = maxGas();
    mathint gasPriceBid = gasPriceBid();
    mathint rewardThreshold = rewardThreshold();
    mathint rewardsTokenBalanceOfProxy = gem.balanceOf(currentContract);
    address escrow = l1Gateway.escrow();
    mathint rewardsTokenBalanceOfEscrow = gem.balanceOf(escrow);
    // ERC20 assumption
    require gem.totalSupply() >= rewardsTokenBalanceOfProxy + rewardsTokenBalanceOfEscrow;
    // Happening in constructor
    require gem.allowance(currentContract, l1Gateway) == max_uint256;

    mathint balanceProxy = nativeBalances[currentContract];
    uint256 maxSubmissionCost = (1400 + 6 * 324) * 30*10^9;
    mathint l1CallValue = maxSubmissionCost + maxGas * gasPriceBid;
    // Practical assumption
    require nativeBalances[l1Gateway] + l1CallValue <= max_uint256;

    notifyRewardAmount@withrevert(e, reward);

    bool revert1 = e.msg.value > 0;
    bool revert2 = reward <= rewardThreshold;
    bool revert3 = balanceProxy < l1CallValue;
    bool revert4 = rewardsTokenBalanceOfProxy < reward;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}
