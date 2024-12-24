// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import {Api3Aggregator} from "src/oracles/Api3Aggregator.sol";

contract Api3Script is Script {
    address public deployerAddress = vm.envAddress("DEPLOYER");

    function run() public {
        vm.startBroadcast(deployerAddress);
    }

    function deploySei() public {
        Api3Aggregator seiPriceFeed =
            new Api3Aggregator(0x09c6e594DE2EB633902f00B87A43b27F80a31a60, "Sei/USD Market Price Feed");

        (, int256 seiPrice,,,) = seiPriceFeed.latestRoundData();
        console.log("seiPrice ", uint256(seiPrice));
    }
}
