// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "./HToken.sol";
import "./ErrorReporter.sol";
import "./oracles/PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Comptroller Contract
 */
contract Comptroller is ComptrollerVXStorage, ComptrollerInterface, ComptrollerErrorReporter, ExponentialNoError {
    using SafeERC20 for IERC20;

    /// @notice Emitted when an admin supports a market
    event MarketListed(HToken hToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(HToken hToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(HToken hToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(HToken hToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(HToken hToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a hToken is changed
    event NewBorrowCap(HToken indexed hToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when supply cap for a hToken is changed
    event NewSupplyCap(HToken indexed hToken, uint256 newSupplyCap);

    /// @notice Emitted when supply cap guardian is changed
    event NewSupplyCapGuardian(address oldSupplyCapGuardian, address newSupplyCapGuardian);

    /// @notice Emitted when reward distributor is changed
    event NewRewardDistributor(
        IMultiRewardDistributor oldRewardDistributor, IMultiRewardDistributor newRewardDistributor
    );

    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint256 internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint256 internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    // authorized liquidator
    mapping(address => bool) public liquidatorWhiteList;

    // liquidator white list liquidatable flag
    bool public liquidatable;

    // asset redeemable
    mapping(address => bool) public redeemGuardianPaused;

    // blacklist account
    mapping(address => bool) public blackList;

    constructor() {
        admin = msg.sender;
    }

    /**
     * Assets You Are In **
     */

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (HToken[] memory) {
        HToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param hToken The hToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, HToken hToken) external view returns (bool) {
        return markets[address(hToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param hTokens The list of addresses of the hToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory hTokens) public override returns (uint256[] memory) {
        uint256 len = hTokens.length;

        uint256[] memory results = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            // Prevent paused asset enter market
            if (borrowGuardianPaused[hTokens[i]]) continue;

            HToken hToken = HToken(hTokens[i]);
            results[i] = uint256(addToMarketInternal(hToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param hToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(HToken hToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(hToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(hToken);

        emit MarketEntered(hToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param hTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address hTokenAddress) external override returns (uint256) {
        HToken hToken = HToken(hTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the hToken */
        (uint256 oErr, uint256 tokensHeld, uint256 amountOwed,) = hToken.getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint256 allowed = redeemAllowedInternal(hTokenAddress, msg.sender, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(hToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint256(Error.NO_ERROR);
        }

        /* Set hToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete hToken from the account’s list of assets */
        // load into memory for faster iteration
        HToken[] memory userAssetList = accountAssets[msg.sender];
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i = 0; i < len; i++) {
            if (userAssetList[i] == hToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        HToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(hToken, msg.sender);

        return uint256(Error.NO_ERROR);
    }

    /**
     * Policy Hooks **
     */

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param hToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address hToken, address minter, uint256 mintAmount) external override returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[hToken], "mint is paused");

        // Shh - currently unused
        mintAmount;

        if (!markets[hToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        if (blackList[minter]) {
            return uint256(Error.REJECTION);
        }

        uint256 supplyCap = supplyCaps[hToken];
        // Supply cap of 0 corresponds to unlimited supplying
        if (supplyCap != 0) {
            uint256 totalCash = HToken(hToken).getCash();
            uint256 totalBorrows = HToken(hToken).totalBorrows();
            uint256 totalReserves = HToken(hToken).totalReserves();
            // totalSupplies = totalCash + totalBorrows - totalReserves
            uint256 totalSupplies = sub_(add_(totalCash, totalBorrows), totalReserves);

            uint256 nextTotalSupplies = add_(totalSupplies, mintAmount);
            require(nextTotalSupplies < supplyCap, "market supply cap reached");
        }

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForToken(hToken, minter);
        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param hToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of hTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(address hToken, address redeemer, uint256 redeemTokens)
        external
        override
        returns (uint256)
    {
        uint256 allowed = redeemAllowedInternal(hToken, redeemer, redeemTokens);
        if (allowed != uint256(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForToken(hToken, redeemer);

        return uint256(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address hToken, address redeemer, uint256 redeemTokens)
        internal
        view
        returns (uint256)
    {
        require(!redeemGuardianPaused[hToken], "redeem is paused");

        if (blackList[redeemer]) {
            return uint256(Error.REJECTION);
        }

        if (!markets[hToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[hToken].accountMembership[redeemer]) {
            return uint256(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err,, uint256 shortfall) =
            getHypotheticalAccountLiquidityInternal(redeemer, HToken(hToken), redeemTokens, 0);
        if (err != Error.NO_ERROR) {
            return uint256(err);
        }
        if (shortfall > 0) {
            return uint256(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param hToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address hToken, address redeemer, uint256 redeemAmount, uint256 redeemTokens)
        external
        pure
        override
    {
        // Shh - currently unused
        hToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param hToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(address hToken, address borrower, uint256 borrowAmount)
        external
        override
        returns (uint256)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[hToken], "borrow is paused");

        if (!markets[hToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        if (blackList[borrower]) {
            return uint256(Error.REJECTION);
        }

        if (!markets[hToken].accountMembership[borrower]) {
            // only hTokens may call borrowAllowed if borrower not in market
            require(msg.sender == hToken, "sender must be hToken");

            // attempt to add borrower to the market
            Error addToMarketErr = addToMarketInternal(HToken(msg.sender), borrower);
            if (addToMarketErr != Error.NO_ERROR) {
                return uint256(addToMarketErr);
            }

            // it should be impossible to break the important invariant
            assert(markets[hToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(HToken(hToken)) == 0) {
            return uint256(Error.PRICE_ERROR);
        }

        uint256 borrowCap = borrowCaps[hToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint256 totalBorrows = HToken(hToken).totalBorrows();
            uint256 nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (Error err,, uint256 shortfall) =
            getHypotheticalAccountLiquidityInternal(borrower, HToken(hToken), 0, borrowAmount);
        if (err != Error.NO_ERROR) {
            return uint256(err);
        }
        if (shortfall > 0) {
            return uint256(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        updateAndDistributeBorrowerRewardsForToken(hToken, borrower);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param hToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(address hToken, address payer, address borrower, uint256 repayAmount)
        external
        override
        returns (uint256)
    {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (blackList[borrower]) {
            return uint256(Error.REJECTION);
        }

        if (!markets[hToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updateAndDistributeBorrowerRewardsForToken(hToken, borrower);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param hTokenBorrowed Asset which was borrowed by the borrower
     * @param hTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address hTokenBorrowed,
        address hTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external view override returns (uint256) {
        if (liquidatable && !liquidatorWhiteList[liquidator]) {
            return uint256(Error.UNAUTHORIZED);
        }

        if (!markets[hTokenBorrowed].isListed || !markets[hTokenCollateral].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        if (!markets[hTokenCollateral].accountMembership[borrower]) {
            return uint256(Error.MARKET_NOT_ENTERED);
        }

        uint256 borrowBalance = HToken(hTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(HToken(hTokenBorrowed))) {
            require(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (Error err,, uint256 shortfall) = getAccountLiquidityInternal(borrower);

            if (err != Error.NO_ERROR) {
                return uint256(err);
            }

            if (shortfall == 0) {
                return uint256(Error.INSUFFICIENT_SHORTFALL);
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint256 maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);

            if (repayAmount > maxClose) {
                return uint256(Error.TOO_MUCH_REPAY);
            }
        }
        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param hTokenCollateral Asset which was used as collateral and will be seized
     * @param hTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address hTokenCollateral,
        address hTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[hTokenCollateral].isListed || !markets[hTokenBorrowed].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        if (HToken(hTokenCollateral).comptroller() != HToken(hTokenBorrowed).comptroller()) {
            return uint256(Error.COMPTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        // Note: We don't update borrower indices here because as part of liquidations
        //       repayBorrowFresh is called, which in turn calls `borrowAllow`, which updates
        //       the liquidated borrower's indices.
        updateAndDistributeSupplierRewardsForToken(hTokenCollateral, borrower);
        updateAndDistributeSupplierRewardsForToken(hTokenCollateral, liquidator);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param hToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of hTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(address hToken, address src, address dst, uint256 transferTokens)
        external
        override
        returns (uint256)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint256 allowed = redeemAllowedInternal(hToken, src, transferTokens);
        if (allowed != uint256(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForToken(hToken, src);
        updateAndDistributeSupplierRewardsForToken(hToken, dst);

        return uint256(Error.NO_ERROR);
    }

    /**
     * Liquidity/Liquidation Calculations **
     */

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `hTokenCollateral` is the number of hTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;
        uint256 hTokenCollateral;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint256, uint256, uint256) {
        (Error err, uint256 liquidity, uint256 shortfall) =
            getHypotheticalAccountLiquidityInternal(account, HToken(address(0)), 0, 0);

        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (Error, uint256, uint256) {
        return getHypotheticalAccountLiquidityInternal(account, HToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param hTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
     *             hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address hTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) public view returns (uint256, uint256, uint256) {
        (Error err, uint256 liquidity, uint256 shortfall) =
            getHypotheticalAccountLiquidityInternal(account, HToken(hTokenModify), redeemTokens, borrowAmount);
        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param hTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral hToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
     *             hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        HToken hTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) internal view returns (Error, uint256, uint256) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint256 oErr;

        // For each asset the account is in
        HToken[] memory assets = accountAssets[account];
        for (uint256 i = 0; i < assets.length; i++) {
            HToken asset = assets[i];

            // Read the balances and exchange rate from the hToken
            (oErr, vars.hTokenCollateral, vars.borrowBalance, vars.exchangeRateMantissa) =
                asset.getAccountSnapshot(account);
            if (oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> glmr (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * hTokenCollateral
            vars.sumCollateral =
                mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.hTokenCollateral, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects =
                mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with hTokenModify
            if (asset == hTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects =
                    mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects =
                    mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in hToken.liquidateBorrowFresh)
     * @param hTokenBorrowed The address of the borrowed hToken
     * @param hTokenCollateral The address of the collateral hToken
     * @param actualRepayAmount The amount of hTokenBorrowed underlying to convert into hTokenCollateral tokens
     * @return (errorCode, number of hTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(address hTokenBorrowed, address hTokenCollateral, uint256 actualRepayAmount)
        external
        view
        override
        returns (uint256, uint256)
    {
        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedMantissa = oracle.getUnderlyingPrice(HToken(hTokenBorrowed));
        uint256 priceCollateralMantissa = oracle.getUnderlyingPrice(HToken(hTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint256(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateMantissa = HToken(hTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint256 seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa}), Exp({mantissa: priceBorrowedMantissa}));
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint256(Error.NO_ERROR), seizeTokens);
    }

    /**
     * Admin Functions **
     */

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint256) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure
     */
    function _setCloseFactor(uint256 newCloseFactorMantissa) external returns (uint256) {
        // Check caller is admin
        require(msg.sender == admin, "only admin can set close factor");

        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param hToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setCollateralFactor(HToken hToken, uint256 newCollateralFactorMantissa) external returns (uint256) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[address(hToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(hToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(hToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external returns (uint256) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint256 oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param hToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _supportMarket(HToken hToken) external returns (uint256) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(hToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        require(hToken.isRToken(), "Must be an HToken"); // Sanity check to make sure its really a HToken

        Market storage newMarket = markets[address(hToken)];
        newMarket.isListed = true;
        newMarket.collateralFactorMantissa = 0;

        _addMarketInternal(address(hToken));

        emit MarketListed(hToken);

        return uint256(Error.NO_ERROR);
    }

    function _addMarketInternal(address hToken) internal {
        for (uint256 i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != HToken(hToken), "market already added");
        }
        allMarkets.push(HToken(hToken));
    }

    /**
     * @notice Set the given borrow caps for the given hToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
     * @param hTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    function _setMarketBorrowCaps(HToken[] calldata hTokens, uint256[] calldata newBorrowCaps) external {
        require(
            msg.sender == admin || msg.sender == borrowCapGuardian,
            "only admin or borrow cap guardian can set borrow caps"
        );

        uint256 numMarkets = hTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for (uint256 i = 0; i < numMarkets; i++) {
            borrowCaps[address(hTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(hTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Set the given supply caps for the given hToken markets. Supplying that brings total supplies to or above supply cap will revert.
     * @dev Admin or supplyCapGuardian function to set the supply caps. A supply cap of 0 corresponds to unlimited supplying.
     * @param hTokens The addresses of the markets (tokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set. A value of 0 corresponds to unlimited supplying.
     */
    function _setMarketSupplyCaps(HToken[] calldata hTokens, uint256[] calldata newSupplyCaps) external {
        require(
            msg.sender == admin || msg.sender == supplyCapGuardian,
            "only admin or supply cap guardian can set supply caps"
        );

        uint256 numMarkets = hTokens.length;
        uint256 numSupplyCaps = newSupplyCaps.length;

        require(numMarkets != 0 && numMarkets == numSupplyCaps, "invalid input");

        for (uint256 i = 0; i < numMarkets; i++) {
            supplyCaps[address(hTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(hTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Supply Cap Guardian
     * @param newSupplyCapGuardian The address of the new Supply Cap Guardian
     */
    function _setSupplyCapGuardian(address newSupplyCapGuardian) external {
        require(msg.sender == admin, "only admin can set supply cap guardian");

        // Save current value for inclusion in log
        address oldSupplyCapGuardian = supplyCapGuardian;

        // Store supplyCapGuardian with value newSupplyCapGuardian
        supplyCapGuardian = newSupplyCapGuardian;

        // Emit NewSupplyCapGuardian(OldSupplyCapGuardian, NewSupplyCapGuardian)
        emit NewSupplyCapGuardian(oldSupplyCapGuardian, newSupplyCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint256) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Admin function to change the Reward Distributor
     * @param newRewardDistributor The address of the new Reward Distributor
     */
    function _setRewardDistributor(IMultiRewardDistributor newRewardDistributor) public {
        require(msg.sender == admin, "Unauthorized");

        IMultiRewardDistributor oldRewardDistributor = rewardDistributor;

        rewardDistributor = newRewardDistributor;

        emit NewRewardDistributor(oldRewardDistributor, newRewardDistributor);
    }

    function _setMintPaused(HToken hToken, bool state) public returns (bool) {
        require(markets[address(hToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(hToken)] = state;
        emit ActionPaused(hToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(HToken hToken, bool state) public returns (bool) {
        require(markets[address(hToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(hToken)] = state;
        emit ActionPaused(hToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @notice Sweep ERC-20 tokens from the comptroller to the admin
     * @param _tokenAddress The address of the token to transfer
     * @param _amount The amount of tokens to sweep, uint.max means everything
     */
    function _rescueFunds(address _tokenAddress, uint256 _amount) external {
        require(msg.sender == admin, "Unauthorized");

        IERC20 token = IERC20(_tokenAddress);
        // Similar to hTokens, if this is uint.max that means "transfer everything"
        if (_amount == type(uint256).max) {
            token.safeTransfer(admin, token.balanceOf(address(this)));
        } else {
            token.safeTransfer(admin, _amount);
        }
    }

    /**
     * Reward Distribution **
     */

    /**
     * @notice Call out to the reward distributor to update its supply index and this user's index too
     * @param hToken The market to synchronize indexes for
     * @param supplier The supplier to whom rewards are going
     */
    function updateAndDistributeSupplierRewardsForToken(address hToken, address supplier) internal {
        if (address(rewardDistributor) != address(0)) {
            rewardDistributor.updateMarketSupplyIndexAndDisburseSupplierRewards(HToken(hToken), supplier, false);
        }
    }

    /**
     * @notice Call out to the reward distributor to update its borrow index and this user's index too
     * @param hToken The market to synchronize indexes for
     * @param borrower The borrower to whom rewards are going
     */
    function updateAndDistributeBorrowerRewardsForToken(address hToken, address borrower) internal {
        if (address(rewardDistributor) != address(0)) {
            rewardDistributor.updateMarketBorrowIndexAndDisburseBorrowerRewards(HToken(hToken), borrower, false);
        }
    }

    /**
     * @notice Claim all the reward accrued by holder in all markets
     */
    function claimReward() public {
        claimReward(msg.sender, allMarkets);
    }

    /**
     * @notice Claim all the rewards accrued by specified holder in all markets
     * @param holder The address to claim rewards for
     */
    function claimReward(address holder) public {
        claimReward(holder, allMarkets);
    }

    /**
     * @notice Claim all the rewards accrued by holder in the specified markets
     * @param holder The address to claim rewards for
     * @param hTokens The list of markets to claim rewards in
     */
    function claimReward(address holder, HToken[] memory hTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimReward(holders, hTokens, true, true);
    }

    /**
     * @notice Claim all rewards for a specified group of users, tokens, and market sides
     * @param holders The addresses to claim for
     * @param hTokens The list of markets to claim in
     * @param borrowers Whether or not to claim earned by borrowing
     * @param suppliers Whether or not to claim earned by supplying
     */
    function claimReward(address[] memory holders, HToken[] memory hTokens, bool borrowers, bool suppliers) public {
        require(address(rewardDistributor) != address(0), "No reward distributor configured!");

        for (uint256 i = 0; i < hTokens.length; i++) {
            // Safety check that the supplied hTokens are active/listed
            HToken hToken = hTokens[i];
            require(markets[address(hToken)].isListed, "market must be listed");

            // Disburse supply side
            if (suppliers == true) {
                rewardDistributor.updateMarketSupplyIndex(hToken);
                for (uint256 holderIndex = 0; holderIndex < holders.length; holderIndex++) {
                    rewardDistributor.disburseSupplierRewards(hToken, holders[holderIndex], true);
                }
            }

            // Disburse borrow side
            if (borrowers == true) {
                rewardDistributor.updateMarketBorrowIndex(hToken);
                for (uint256 holderIndex = 0; holderIndex < holders.length; holderIndex++) {
                    rewardDistributor.disburseBorrowerRewards(hToken, holders[holderIndex], true);
                }
            }
        }
    }

    /**
     * @notice Enter all markets
     * @dev The automatic enter all markets.
     */
    function enterAllMarkets(address account) public override returns (uint256[] memory) {
        address[] memory assetsAddresses = new address[](allMarkets.length);

        bool isRTokenContract;

        for (uint256 i = 0; i < allMarkets.length; i++) {
            assetsAddresses[i] = address(allMarkets[i]);

            if (assetsAddresses[i] == msg.sender) {
                isRTokenContract = true;
            }
        }

        require(isRTokenContract, "Sender must be a HToken contract");

        uint256 len = assetsAddresses.length;

        uint256[] memory results = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            // Prevent paused asset enter market
            if (borrowGuardianPaused[assetsAddresses[i]]) continue;

            HToken hToken = HToken(assetsAddresses[i]);
            results[i] = uint256(addToMarketInternal(hToken, account));
        }

        return results;
    }

    /**
     * @notice chekc msg.sender is liquidator
     */
    function isInLiquidateWhiteList(address user) public view returns (bool) {
        return liquidatorWhiteList[user];
    }

    /**
     * @notice update new liquidator
     * @dev update new user liquidator to whitel ist
     */
    function updateLiquidateWhiteList(address user, bool state) public {
        require(msg.sender == admin, "Unauthorized");

        if (state) {
            require(!liquidatorWhiteList[user], "User is already in the white list");
        }

        liquidatorWhiteList[user] = state;
    }

    /**
     * @notice trigger liquidatable flag
     * @dev state liquidatable flag
     */
    function triggerLiquidation(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        liquidatable = state;
        return state;
    }

    /**
     * @notice set asset redemption paused
     * @dev state asset redemption paused flag
     */
    function _setRedeemPaused(HToken hToken, bool state) public returns (bool) {
        require(markets[address(hToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");

        redeemGuardianPaused[address(hToken)] = state;
        emit ActionPaused(hToken, "Redeem", state);
        return state;
    }

    /**
     * @notice set asset redemption paused
     * @dev state of account is add blacklist flag
     */
    function _setBlackList(address account_, bool state) public {
        require(msg.sender == admin, "only admin can set blacklist");
        blackList[account_] = state;
    }

    /**
     * @notice paused protocal all markets
     * @dev state paused flag
     */
    function _setProtocalPaused() public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");

        for (uint256 i = 0; i < allMarkets.length; i++) {
            HToken hToken_ = allMarkets[i];
            address hToken = address(hToken_);
            borrowGuardianPaused[hToken] = true;
            mintGuardianPaused[hToken] = true;
            redeemGuardianPaused[hToken] = true;

            emit ActionPaused(hToken_, "Mint", true);
            emit ActionPaused(hToken_, "Borrow", true);
            emit ActionPaused(hToken_, "Redeem", true);
        }

        transferGuardianPaused = true;
        seizeGuardianPaused = true;
        return true;
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (HToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns true if the given hToken market has been deprecated
     * @dev All borrows in a deprecated hToken market can be immediately liquidated
     * @param hToken The market to check if deprecated
     */
    function isDeprecated(HToken hToken) public view returns (bool) {
        return markets[address(hToken)].collateralFactorMantissa == 0 && borrowGuardianPaused[address(hToken)] == true
            && hToken.reserveFactorMantissa() == 1e18;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_locked != 1, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _locked = 1;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _locked = 0;
    }
}
