// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/HToken.sol";
import "src/Comptroller.sol";
import "src/HErc20.sol";
import "src/oracles/CompositeOracle.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {HErc20Delegate} from "src/HErc20Delegate.sol";
import "src/oracles/AggregatorV3Interface.sol";
import "./CompoundInterest.sol";

contract HashPrimeBaseTest is Test {
    address public alice = vm.addr(0x123);
    address public bob = vm.addr(0x1234);
    address public deployerAddress = vm.envAddress("DEPLOYER");
    address public mulSigWallet = vm.envAddress("MUL_SIG_WALLET");
    uint256 public mintAmount = 2e6;

    Comptroller comptroller = Comptroller(0x8a67AB98A291d1AEA2E1eB0a79ae4ab7f2D76041);
    Unitroller unitroller = Unitroller(0x8a67AB98A291d1AEA2E1eB0a79ae4ab7f2D76041);
    CompositeOracle oracle = CompositeOracle(0x653C2D3A1E4Ac5330De3c9927bb9BDC51008f9d5);

    function mintRTokenSucceedsTest(address hTokenAddr) public {
        address sender = alice;

        HErc20Delegator hToken = HErc20Delegator(payable(hTokenAddr));
        IERC20 token = IERC20(hToken.underlying());

        vm.startPrank(sender);
        // uint256 startingTokenBalance = token.balanceOf(address(hToken));
        deal(address(token), sender, mintAmount);
        token.approve(address(hToken), mintAmount);
        assertEq(hToken.mint(mintAmount), 0);
        assertEq(token.balanceOf(sender), 0);
        /// ensure successful mint
        vm.stopPrank();

        vm.startPrank(bob);
        deal(address(token), bob, mintAmount);
        token.approve(address(hToken), mintAmount);
        assertEq(hToken.mint(mintAmount), 0);
        assertEq(token.balanceOf(bob), 0);

        uint256 expectRTokenAmount = mintAmount * 1e18 / hToken.exchangeRateCurrent();

        /// ensure successful mint
        assertApproxEqRel(hToken.balanceOf(sender), expectRTokenAmount, 0.0001e18);
        assertApproxEqRel(hToken.balanceOf(bob), expectRTokenAmount, 0.0001e18);
    }

    function borrowRTokenSucceedsTest(address hTokenAddr) public {
        mintRTokenSucceedsTest(hTokenAddr);
        address sender = mulSigWallet;

        HErc20Delegator hToken = HErc20Delegator(payable(hTokenAddr));
        IERC20 token = IERC20(hToken.underlying());
        address[] memory hTokens = new address[](1);
        hTokens[0] = address(hToken);

        vm.startPrank(mulSigWallet);
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
        assertEq(token.balanceOf(alice), borrowAmount);
    }

    function redeemTest(address hTokenAddr) public {
        mintRTokenSucceedsTest(hTokenAddr);
        vm.stopPrank();
        vm.startPrank(alice);
        HErc20Delegator hToken = HErc20Delegator(payable(hTokenAddr));
        IERC20 token = IERC20(hToken.underlying());
        hToken.redeemUnderlying(mintAmount);

        assertApproxEqRel(token.balanceOf(alice), mintAmount, 0.00001e18);
    }

    function repayTest(address hTokenAddr) public {
        // 1. Call mintRTokenSucceedsTest to initialize
        mintRTokenSucceedsTest(hTokenAddr);

        // 2. Simulate one month (30 days = 30*24*60*60 seconds)
        uint256 oneMonthInSeconds = 30 days;

        // 3. Alice borrows some amount
        vm.startPrank(alice);
        HErc20Delegator hToken = HErc20Delegator(payable(hTokenAddr));
        IERC20 token = IERC20(hToken.underlying());
        uint256 borrowAmount = 0.7e6;

        // Before borrowing, get the current total debt
        uint256 initialBorrowBalance = hToken.borrowBalanceCurrent(alice);

        assertEq(initialBorrowBalance, 0);
        assertEq(hToken.borrow(borrowAmount), 0);

        uint256 borrowBalance_after = hToken.borrowBalanceCurrent(alice);

        assertEq(borrowBalance_after, borrowAmount);

        // Simulate time passage of one month
        vm.warp(block.timestamp + oneMonthInSeconds);
        vm.roll(block.number + oneMonthInSeconds / 4);

        uint256 borrowRatePerSecond = hToken.borrowRatePerBlock(); // Assuming this returns per second rate

        // Use the CompoundInterest library to calculate total after one month
        uint256 totalBorrowedAfterOneMonth =
            CompoundInterest.calculateCompoundInterest(borrowAmount, borrowRatePerSecond, oneMonthInSeconds);

        // Check if the total debt is as expected
        uint256 actualBorrowBalanceAfterOneMonth = hToken.borrowBalanceCurrent(alice);
        assertApproxEqRel(actualBorrowBalanceAfterOneMonth, totalBorrowedAfterOneMonth, 0.01e18);

        deal(address(token), alice, actualBorrowBalanceAfterOneMonth);

        token.approve(address(hToken), actualBorrowBalanceAfterOneMonth);
        hToken.repayBorrow(actualBorrowBalanceAfterOneMonth);

        // Ensure the borrow balance is zero
        assertEq(hToken.borrowBalanceCurrent(alice), 0);
        assertEq(token.balanceOf(alice), 0);

        vm.stopPrank();
    }
}
