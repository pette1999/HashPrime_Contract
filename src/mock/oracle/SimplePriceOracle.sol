// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "src/HErc20.sol";
import "src/oracles/PriceOracle.sol";

contract SimplePriceOracle is PriceOracle {
    mapping(address => uint256) prices;

    event PricePosted(
        address asset, uint256 previousPriceMantissa, uint256 requestedPriceMantissa, uint256 newPriceMantissa
    );

    address public admin;

    constructor() {
        admin = msg.sender;
    }

    function getUnderlyingPrice(HToken hToken) public view override returns (uint256) {
        if (compareStrings(hToken.symbol(), "mGLMR")) {
            return 1e18;
        } else {
            return prices[address(HErc20(address(hToken)).underlying())];
        }
    }

    function setUnderlyingPrice(HToken hToken, uint256 underlyingPriceMantissa) public {
        require(msg.sender == admin, "Only admin can set the price");

        address asset = address(HErc20(address(hToken)).underlying());
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint256 price) public {
        require(msg.sender == admin, "Only admin can set the price");

        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint256) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
