// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RockPaperScissors} from "src/RockPaperScissors.sol";
import {CreateSubscription, FundSubscriptions, AddConsumer} from "script/Interactions.s.sol";

contract DeployRPS is Script {
    function run() external returns (RockPaperScissors, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        // local -> deploy mocks, get local config
        // sepolia -> get sepolia config
        AddConsumer addConsumer = new AddConsumer();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // create subscription
        CreateSubscription createSubscription = new CreateSubscription();
        (config.subscriptionId, config.vrfCoordinator) = createSubscription.createSubscription(config.vrfCoordinator, config.account);

        // fund subscription
        FundSubscriptions fundSubscriptions = new FundSubscriptions();
        fundSubscriptions.fundSubsription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);

        helperConfig.setConfig(block.chainid, config);

        vm.startBroadcast(config.account);
        RockPaperScissors rps = new RockPaperScissors(
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        addConsumer.addConsumer(address(rps), config.vrfCoordinator, config.subscriptionId, config.account);
        return (rps, helperConfig);
    }
}