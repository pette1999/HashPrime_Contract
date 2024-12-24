// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

library CompoundInterest {
    /**
     * @notice Calculate compound interest over a given period.
     * @param principal The initial principal amount (borrow amount)
     * @param ratePerSecond The interest rate per second (e.g., 5e16 represents 5%)
     * @param timeInSeconds The time period over which interest is accumulated, in seconds
     * @return The final amount after applying compound interest
     */
    function calculateCompoundInterest(
        uint256 principal, // Principal amount
        uint256 ratePerSecond, // Interest rate per second
        uint256 timeInSeconds // Time in seconds
    ) public pure returns (uint256) {
        // The base for compound interest formula: 1 + r
        uint256 base = 1e18 + ratePerSecond;

        // Calculate (1 + r) ^ t using the rpow function
        uint256 compounded = rpow(base, timeInSeconds, 1e18);

        // Final amount: A = P * compounded
        uint256 finalAmount = (principal * compounded) / 1e18;
        return finalAmount;
    }

    /**
     * @notice Exponentiation function for calculating base^exp with fixed-point arithmetic.
     * @param x The base, typically (1 + r), in 18 decimal precision
     * @param n The exponent, typically the number of seconds or time period
     * @param base The precision base (e.g., 1e18)
     * @return z The result of (x^n) / base
     */
    function rpow(
        uint256 x, // Base (1 + interest rate)
        uint256 n, // Exponent (number of seconds)
        uint256 base // Precision base (e.g., 1e18)
    ) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : base;

        for (n /= 2; n != 0; n /= 2) {
            x = (x * x) / base;

            if (n % 2 != 0) {
                z = (z * x) / base;
            }
        }
    }
}
