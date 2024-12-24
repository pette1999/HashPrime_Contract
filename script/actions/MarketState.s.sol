// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Script.sol";

import {HToken} from "src/oracles/CompositeOracle.sol";
import "src/Comptroller.sol";
import "src/utils/MarketState.sol";

contract MarketStateScript is Script {
    address public deployerAddress = vm.envAddress("DEPLOYER");
    address public multiSigWallet = vm.envAddress("MUL_SIG_WALLET");

    // address public oracle = 0x653C2D3A1E4Ac5330De3c9927bb9BDC51008f9d5;
    // address public comptroller = 0x8a67AB98A291d1AEA2E1eB0a79ae4ab7f2D76041;
    MarketState public marketState;

    function run() public {
        vm.startBroadcast(deployerAddress);
        // marketState = new MarketState(comptroller, oracle);

        // console.log("marketState address: ", address(marketState));
    }
}
