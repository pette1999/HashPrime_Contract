// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /**
     * Assets You Are In **
     */
    function enterMarkets(address[] calldata hTokens) external virtual returns (uint256[] memory);
    function exitMarket(address hToken) external virtual returns (uint256);

    /**
     * Policy Hooks **
     */
    function mintAllowed(address hToken, address minter, uint256 mintAmount) external virtual returns (uint256);

    function redeemAllowed(address hToken, address redeemer, uint256 redeemTokens) external virtual returns (uint256);

    // Do not remove, still used by HToken
    function redeemVerify(address hToken, address redeemer, uint256 redeemAmount, uint256 redeemTokens)
        external
        pure
        virtual;

    function borrowAllowed(address hToken, address borrower, uint256 borrowAmount) external virtual returns (uint256);

    function enterAllMarkets(address account) external virtual returns (uint256[] memory);

    function repayBorrowAllowed(address hToken, address payer, address borrower, uint256 repayAmount)
        external
        virtual
        returns (uint256);

    function liquidateBorrowAllowed(
        address hTokenBorrowed,
        address hTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external view virtual returns (uint256);

    function seizeAllowed(
        address hTokenCollateral,
        address hTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external virtual returns (uint256);

    function transferAllowed(address hToken, address src, address dst, uint256 transferTokens)
        external
        virtual
        returns (uint256);

    /**
     * Liquidity/Liquidation Calculations **
     */
    function liquidateCalculateSeizeTokens(address hTokenBorrowed, address hTokenCollateral, uint256 repayAmount)
        external
        view
        virtual
        returns (uint256, uint256);
}

// The hooks that were patched out of the comptroller to make room for the supply caps, if we need them
abstract contract ComptrollerInterfaceWithAllVerificationHooks is ComptrollerInterface {
    function mintVerify(address hToken, address minter, uint256 mintAmount, uint256 mintTokens) external virtual;

    // Included in ComptrollerInterface already
    // function redeemVerify(address hToken, address redeemer, uint redeemAmount, uint redeemTokens) virtual external;

    function borrowVerify(address hToken, address borrower, uint256 borrowAmount) external virtual;

    function repayBorrowVerify(
        address hToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 borrowerIndex
    ) external virtual;

    function liquidateBorrowVerify(
        address hTokenBorrowed,
        address hTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 seizeTokens
    ) external virtual;

    function seizeVerify(
        address hTokenCollateral,
        address hTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external virtual;

    function transferVerify(address hToken, address src, address dst, uint256 transferTokens) external virtual;
}
