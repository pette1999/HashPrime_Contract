// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Comptroller, ComptrollerVXStorage} from "src/Comptroller.sol";
import {Unitroller} from "src/Unitroller.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";
import {HErc20Delegate} from "src/HErc20Delegate.sol";
import {HToken} from "src/HToken.sol";
import {Rate} from "src/Rate.sol";
import {HErc20} from "src/HErc20.sol";
import {HTokenInterface} from "src/HTokenInterfaces.sol";
import {FaucetToken} from "src/mock/token/FaucetToken.sol";
import {Deploy} from "script/DeployStaging.s.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";

contract SystemCoreTest is Test, Deploy {
    address public alice = vm.addr(0x123);
    address public bob = vm.addr(0x1234);
    address public rewardToken;
    // MultiRewardDistributor public mrd;
    Comptroller public comptroller;
    // MultiRewardDistributor mrd;
    // Comptroller comptroller;
    // Addresses addresses;
    // address public well;
    uint256 supplyIndex = 0;
    uint256 borrowIndex = 0;

    function setUp() public {
        vm.startPrank(deployerAddress);
        vm.warp(block.timestamp + 3600 * 2);

        setupHtokenList();
        deployCore(deployerAddress);
        deployAsset(deployerAddress);
        build();

        comptroller = Comptroller(getAddress("UNITROLLER"));
    }

    function testMintRTokenSucceeds() public {
        address sender = alice;
        uint256 mintAmount = 1e6;

        IERC20 token = IERC20(getAddress("USDC"));
        HErc20Delegator hToken = HErc20Delegator(payable(getAddress("tUSDC")));

        vm.startPrank(sender);
        // uint256 startingTokenBalance = token.balanceOf(address(hToken));
        deal(address(token), sender, mintAmount);
        token.approve(address(hToken), mintAmount);
        assertEq(hToken.mint(mintAmount), 0);
        /// ensure successful mint
        vm.stopPrank();

        vm.startPrank(bob);
        deal(address(token), bob, mintAmount);
        token.approve(address(hToken), mintAmount);
        assertEq(hToken.mint(mintAmount), 0);
        /// ensure successful mint

        assertTrue(hToken.balanceOf(sender) > 0);

        /// ensure balance is gt 0
        assertTrue(hToken.balanceOf(bob) > 0);
    }

    function testBorrowRTokenSucceeds() public {
        testMintRTokenSucceeds();
        address sender = deployerAddress;

        // IERC20 token = IERC20(getAddress("USDC"));
        HErc20Delegator hToken = HErc20Delegator(payable(getAddress("tUSDC")));

        address[] memory hTokens = new address[](1);
        hTokens[0] = address(hToken);

        vm.startPrank(sender);
        comptroller._supportMarket(HToken(address(hToken)));
        comptroller.enterMarkets(hTokens);

        (bool isListed,) = comptroller.markets(address(hToken));

        assertTrue(isListed);

        assertTrue(comptroller.checkMembership(sender, HToken(address(hToken))));
        /// ensure sender and hToken is in market
        vm.stopPrank();

        vm.startPrank(alice);

        // console.log("alice balance", hToken.balanceOf(alice));
        uint256 borrowAmount = 0.7e6;

        assertEq(hToken.borrow(borrowAmount), 0);

        /// ensure successful borrow
        assertEq(hToken.balanceOf(alice), 1e6);
    }

    function testRedeem() public {
        testMintRTokenSucceeds();
        vm.stopPrank();
        vm.startPrank(alice);
        HErc20Delegator hToken = HErc20Delegator(payable(getAddress("tUSDC")));
        hToken.redeem(1e6);

        assertEq(hToken.balanceOf(alice), 0);
    }

    function testBorrowInterest() public {
        testBorrowRTokenSucceeds();

        vm.stopPrank();
        vm.startPrank(alice);

        vm.warp(block.timestamp + 365 days + 3600 * 2);
        HErc20Delegator hToken = HErc20Delegator(payable(getAddress("tUSDC")));

        uint256 aliceDebt = hToken.borrowBalanceCurrent(alice);

        assertGt(aliceDebt, 0.72e6);
        assertLt(aliceDebt, 0.74e6);
    }
}
