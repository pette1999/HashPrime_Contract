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
}
