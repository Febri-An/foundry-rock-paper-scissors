// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RockPaperScissors} from "../../src/RockPaperScissors.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

contract RPS_Exposed is RockPaperScissors {
    constructor(
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) RockPaperScissors( vrfCoordinator, gasLane, subscriptionId, callbackGasLimit){}

    function exposed_requestRandomSalt(
        address player
    ) external returns (uint256) {
        return requestRandomSalt(player);
    }
}
