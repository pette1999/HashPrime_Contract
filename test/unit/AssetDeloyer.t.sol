// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/HToken.sol";
import "src/Comptroller.sol";
import "src/HErc20.sol";
import "src/utils/AssetDeployer.sol";
import "src/oracles/CompositeOracle.sol";
import "src/HErc20Delegate.sol";

contract MigrationTest is Test {
    string public rpc = vm.envString("SCROLL_RPC");
    // Addresses
    address unitroller = 0x8a67AB98A291d1AEA2E1eB0a79ae4ab7f2D76041;
    address MUL_SIG_WALLET = 0x2a9c973a2f5Cb494eA84Fd0811aA7701f4d56401;
    address oracleAddr = 0x653C2D3A1E4Ac5330De3c9927bb9BDC51008f9d5;

    Comptroller comptroller;
    Unitroller unitroller_;

    CompositeOracle oracle;

    function setUp() public {
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        comptroller = Comptroller(unitroller);
        unitroller_ = Unitroller(unitroller);

        oracle = CompositeOracle(oracleAddr);
    }

    function testy_lstETH_deploy() public {
        vm.startPrank(MUL_SIG_WALLET);

        address rwstETHAddr = 0xe4FC4C444efFB5ECa80274c021f652980794Eae6;
        address lstETHAddr = 0xBAC6DD1b1F186EF7cf4d64737235a9C53878cB27;
        HToken r_wst_eth = HToken(rwstETHAddr);
        address wst_eth_price_feed = oracle.getAssetAggregators(r_wst_eth)[0];

        HErc20Delegate tErc20Delegate = new HErc20Delegate();
        AssetDeployer assetDeployer = new AssetDeployer(
            MUL_SIG_WALLET, MUL_SIG_WALLET, address(tErc20Delegate), unitroller, unitroller, oracleAddr
        );

        oracle.transferOwnership(address(assetDeployer));
        unitroller_._setPendingAdmin(address(assetDeployer));

        EIP20Interface lstETHToken = EIP20Interface(lstETHAddr);
        uint8 decimals = lstETHToken.decimals();

        vm.stopPrank();
        address assetHolder = 0x15d392dCa9d3a0F74B46dFC36ADfB8b270C691ec;
        vm.startPrank(assetHolder);
        lstETHToken.approve(address(assetDeployer), 1);
        lstETHToken.transfer(address(assetDeployer), 1);
        vm.stopPrank();
        vm.startPrank(MUL_SIG_WALLET);

        uint256 initialExchangeRateMantissa = 1e18;
        string memory name = "HashPrime lstETH";
        string memory symbol = "rlstETH";
        uint256 collateralFactor = 0.7e18;
        uint256 reserveFactor = 0.25e18;
        uint256 seizeShare = 0.03e18;

        uint256 supplyCap = 300e18;
        uint256 borrowCap = 100e18;

        uint256 baseRatePerYear = 0.02 ether;
        uint256 multiplierPerYear = 0.05 ether;
        uint256 jumpMultiplierPerYear = 4 ether;
        uint256 kink = 0.75e18;

        address market = assetDeployer.deployAsset(
            lstETHAddr,
            name,
            symbol,
            decimals,
            initialExchangeRateMantissa,
            collateralFactor,
            reserveFactor,
            seizeShare,
            supplyCap,
            borrowCap,
            wst_eth_price_feed,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink
        );

        (, address marketAddr, address priceFeed) = assetDeployer.assets(lstETHAddr);

        HErc20 hTokenMarket = HErc20(market);
        TErc20Storage hTokenMarketStorage = TErc20Storage(market);

        assertEq(hTokenMarket.name(), name);
        assertEq(hTokenMarket.symbol(), symbol);
        assertEq(hTokenMarketStorage.underlying(), lstETHAddr);
        assertEq(marketAddr, market);
        assertEq(oracle.getAssetAggregators(HToken(market))[0], wst_eth_price_feed);
        assertEq(priceFeed, wst_eth_price_feed);

        assetDeployer.transferOwnership();
        address pendingAdmin = unitroller_.pendingAdmin();
        assertEq(MUL_SIG_WALLET, pendingAdmin);
    }
}
