// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StandardToken} from "src/mock/token/FaucetToken.sol";
import {CoreScript} from "script/staging/Core.sol";
import "src/rewards/IMultiRewardDistributor.sol";
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";

contract Deploy is CoreScript {
    address public deployerAddress = vm.envAddress("DEPLOYER");
    IMultiRewardDistributor public distributor;
    CompositeOracle public oracle;

    // protocal asset
    HToken public hWHSK;
    HToken public hUSDC;
    HToken public hUSDT;

    // unnderlying asset
    IERC20 public USDC;
    IERC20 public USDT;
    IERC20 public WHSK;

    function run() public {
        vm.startBroadcast(deployerAddress);
        deployTestnet(deployerAddress);
        setupAsset();
        setNewAssetPrice();
        setUpEmissionToken(deployerAddress);
    }

    function setupAsset() public {
        oracle = CompositeOracle(getAddress("PRICE_FEED_ORACLE"));
        distributor = IMultiRewardDistributor(getAddress("MRD_PROXY"));

        hWHSK = HToken(getAddress("hWHSK"));
        hUSDC = HToken(getAddress("hUSDC"));
        hUSDT = HToken(getAddress("hUSDT"));

        WHSK = IERC20(getAddress("WHSK"));
        USDC = IERC20(getAddress("USDC"));
        USDT = IERC20(getAddress("USDT"));
    }

    function deployTestnet(address _deployerAddress) public {
        setupHtokenList();
        deployCore(_deployerAddress);
        deployAsset(_deployerAddress);
        // supportCrocPair();
        build();

        // transferOwnership(deployerAddress);
        save();
    }

    function setUpEmissionToken(address _deployerAddress) internal {
        USDC.approve(address(distributor), 10000000e6);
        USDC.transfer(address(distributor), 10000000e6);
        distributor._addEmissionConfig(
            hWHSK, address(_deployerAddress), address(USDC), 0.1e6, 0.1e6, block.timestamp + 1 days
        );
    }

    function setNewAssetPrice() internal {
        address[] memory aggregators = oracle.getAssetAggregators(hWHSK);
        oracle.setOracle(HToken(address(WHSK)), aggregators);

        aggregators = oracle.getAssetAggregators(hUSDT);
        oracle.setOracle(HToken(address(USDT)), aggregators);

        aggregators = oracle.getAssetAggregators(hUSDC);
        oracle.setOracle(HToken(address(USDC)), aggregators);
    }
}
