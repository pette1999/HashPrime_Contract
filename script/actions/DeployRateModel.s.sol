// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "src/irm/JumpRateModel.sol";
// import "src/irm/JumpRateModel.sol";

contract DeployRateModelScript is Script {
    address public deployerAddress = vm.envAddress("DEPLOYER");

    function run() public {
        vm.startBroadcast(deployerAddress);

        // uint256 baseRatePerYear = 0.02e18; // 0.5%
        // uint256 multiplierPerYear = 0.04375e18; // 2.23%
        // uint256 jumpMultiplierPerYear = 2e18; // 200%
        // uint256 kink = 0.9e18; // 90%

        // eth interest
        uint256 ethBaseRatePerYear = 0.005e18; // 2%
        uint256 ethMultiplierPerYear = 0.02e18; // 2.22%
        uint256 ethJumpMultiplierPerYear = 1.5e18;
        uint256 ethKink = 0.7e18; // 90%

        // // stable coin interest
        // uint256 stableBaseRatePerYear = 0.02e18;
        // uint256 stableMultiplierPerYear = 0.03e18; // 3%
        // uint256 stableStableJumpMultiplierPerYear = 1.5e18;
        // uint256 stableKink = 0.9e18; // 90%

        // // normal token interest
        // uint256 normalBaseRatePerYear = 0.02e18;
        // uint256 normalMultiplierPerYear = 0.03e18; // 3%
        // uint256 normalEthJumpMultiplierPerYear = 3.5e18;
        // uint256 normalKink = 0.7e18; // 70%

        JumpRateModel ethRateModel =
            new JumpRateModel(ethBaseRatePerYear, ethMultiplierPerYear, ethJumpMultiplierPerYear, ethKink);

        // JumpRateModel stableRateModel = new JumpRateModel(
        //     stableBaseRatePerYear, stableMultiplierPerYear, stableStableJumpMultiplierPerYear, stableKink
        // );

        // JumpRateModel normalRateModel = new JumpRateModel(
        //     normalBaseRatePerYear, normalMultiplierPerYear, normalEthJumpMultiplierPerYear, normalKink
        // );

        // JumpRateModel stableRateModel =
        //     new JumpRateModel(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink);
        // JumpRateModel normalRateModel = new JumpRateModel(0.02e18, 0.03e18, 4e18, 0.7e18);

        console.log("ethRateModel ", address(ethRateModel));
        // console.log("stableRateModel ", address(stableRateModel));
        // console.log("normalRateModel ", address(normalRateModel));
        // console.log("normalRateModel ", address(normalRateModel) );
    }
}
