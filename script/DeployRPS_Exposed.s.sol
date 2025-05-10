// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RPS_Exposed} from "test/mocks/RPS_Exposed.sol";
import {CreateSubscription, FundSubscriptions, AddConsumer} from "script/Interactions.s.sol";

contract DeployRPS_Exposed is Script {
    function run() external returns (RPS_Exposed, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        AddConsumer addConsumer = new AddConsumer();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        CreateSubscription createSubscription = new CreateSubscription();
        (config.subscriptionId, config.vrfCoordinator) = createSubscription.createSubscription(config.vrfCoordinator, config.account);

        FundSubscriptions fundSubscriptions = new FundSubscriptions();
        fundSubscriptions.fundSubsription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);

        helperConfig.setConfig(block.chainid, config);

        vm.startBroadcast(config.account);
        RPS_Exposed rps = new RPS_Exposed(
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
