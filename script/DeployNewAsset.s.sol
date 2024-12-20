// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import "src/Comptroller.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {HToken} from "src/HToken.sol";
import {JumpRateModel} from "src/irm/JumpRateModel.sol";
import {EIP20Interface} from "src/EIP20Interface.sol";
import {MockChainlinkAggregator} from "src/mock/oracle/MockChainlinkAggregator.sol";
import {FaucetToken} from "src/mock/token/FaucetToken.sol";
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";
import {LinkedAssetAggregator} from "src/oracles/LinkedAssetAggregator.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "src/HErc20Delegate.sol";
import "src/utils/AssetDeployer.sol";

contract Deploy is Script {
    address public deployerAddress = vm.envAddress("DEPLOYER");
    address public multisigWallet = vm.envAddress("MUL_SIG_WALLET");
    CompositeOracle oracle = CompositeOracle(0x653C2D3A1E4Ac5330De3c9927bb9BDC51008f9d5);
    Unitroller unitroller = Unitroller(0x8a67AB98A291d1AEA2E1eB0a79ae4ab7f2D76041);

    function run() public {
        vm.startBroadcast(deployerAddress);
        deploy_ylstETH();
    }

    function deploy_ylstETH() public {
        address rwstETHAddr = 0xe4FC4C444efFB5ECa80274c021f652980794Eae6;
        address ylstETHAddr = 0xBAC6DD1b1F186EF7cf4d64737235a9C53878cB27;
        HToken r_wst_eth = HToken(rwstETHAddr);
        address[] memory wst_eth_price_feed = oracle.getAssetAggregators(r_wst_eth);

        // TODO -
        // HErc20Delegate tErc20Delegate = HErc20Delegate(0x441f85c5d607c254475B97B760cb944970d8Bec4);
        // AssetDeployer assetDeployer = new AssetDeployer(
        //     deployerAddress,
        //     multisigWallet,
        //     address(tErc20Delegate),
        //     address(unitroller),
        //     address(unitroller),
        //     address(oracle)
        // );
        AssetDeployer assetDeployer = AssetDeployer(0xfd40f60E412F59aa38a70E3bA895eb23bC9c7C4E);

        EIP20Interface lstETHToken = EIP20Interface(ylstETHAddr);
        uint8 decimals = lstETHToken.decimals();

        lstETHToken.approve(address(assetDeployer), 1);
        lstETHToken.transfer(address(assetDeployer), 1);

        uint256 initialExchangeRateMantissa = 1e18;
        string memory name = "HashPrime CIAN yield layer stETH";
        string memory symbol = "rylstETH";
        uint256 collateralFactor = 0.5e18;
        uint256 reserveFactor = 0.25e18;
        uint256 seizeShare = 0.03e18;

        uint256 supplyCap = 2;
        uint256 borrowCap = 0;

        uint256 baseRatePerYear = 0.02 ether;
        uint256 multiplierPerYear = 0.05 ether;
        uint256 jumpMultiplierPerYear = 4 ether;
        uint256 kink = 0.75e18;

        assetDeployer.deployAsset(
            ylstETHAddr,
            name,
            symbol,
            decimals,
            initialExchangeRateMantissa,
            collateralFactor,
            reserveFactor,
            seizeShare,
            supplyCap,
            borrowCap,
            wst_eth_price_feed[0],
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink
        );

        print_log(ylstETHAddr, assetDeployer);
    }

    function print_log(address underlyingAddr, AssetDeployer assetDeployer) public view {
        (address interestModelAddr, address marketAddr, address priceFeed) = assetDeployer.assets(underlyingAddr);
        HErc20 market = HErc20(marketAddr);
        JumpRateModel interestModel = JumpRateModel(interestModelAddr);

        console.log("market name: ", market.name());
        console.log("market symbol: ", market.symbol());
        console.log("market decimals: ", market.decimals());
        console.log("market initialExchangeRateMantissa: ", market.exchangeRateStored());
        console.log("market address: ", address(market));
        console.log("market priceFeed: ", priceFeed);
        console.log("underlyingAsset ", underlyingAddr);

        console.log("market interestModel address: ", interestModelAddr);
        console.log("market kink: ", interestModel.kink());
        console.log("market baseRatePerTimestamp: ", interestModel.timestampsPerYear());
        console.log("market jumpMultiplierPerTimestamp: ", interestModel.jumpMultiplierPerTimestamp());
    }
}
