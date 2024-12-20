// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import {StandardToken} from "src/mock/token/FaucetToken.sol";
import {CoreScript} from "script/mainnet/Core.sol";

contract Deploy is Test, CoreScript {
    address public deployerAddress = vm.envAddress("DEPLOYER");
    uint256 public multisigWalletKey = vm.envUint("MUL_SIG_WALLET");
    address public multisigWalletAddress = vm.addr(multisigWalletKey);

    function run() public {
        vm.startBroadcast(deployerAddress);
        setupHtokenList();
        deployCore(deployerAddress);
        deployAsset(deployerAddress);
        build();

        // transferOwnership(multisigWalletAddress);
        save();
    }
}
