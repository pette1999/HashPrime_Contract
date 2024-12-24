// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "../HToken.sol";
import "../ExponentialNoError.sol";
import "./MultiRewardDistributorCommon.sol";

interface IMultiRewardDistributor is MultiRewardDistributorCommon {
    // Public views
    function getAllMarketConfigs(HToken _hToken) external view returns (MarketConfig[] memory);
    function getConfigForMarket(HToken _hToken, address _emissionToken) external view returns (MarketConfig memory);
    function getOutstandingRewardsForUser(address _user) external view returns (RewardWithHToken[] memory);
    function getOutstandingRewardsForUser(HToken _hToken, address _user) external view returns (RewardInfo[] memory);
    function getCurrentEmissionCap() external view returns (uint256);

    // Administrative functions
    function _addEmissionConfig(
        HToken _hToken,
        address _owner,
        address _emissionToken,
        uint256 _supplyEmissionPerSec,
        uint256 _borrowEmissionsPerSec,
        uint256 _endTime
    ) external;
    function _rescueFunds(address _tokenAddress, uint256 _amount) external;
    function _setPauseGuardian(address _newPauseGuardian) external;
    function _setEmissionCap(uint256 _newEmissionCap) external;

    // Comptroller API
    function updateMarketSupplyIndex(HToken _hToken) external;
    function disburseSupplierRewards(HToken _hToken, address _supplier, bool _sendTokens) external;
    function updateMarketSupplyIndexAndDisburseSupplierRewards(HToken _hToken, address _supplier, bool _sendTokens)
        external;
    function updateMarketBorrowIndex(HToken _hToken) external;
    function disburseBorrowerRewards(HToken _hToken, address _borrower, bool _sendTokens) external;
    function updateMarketBorrowIndexAndDisburseBorrowerRewards(HToken _hToken, address _borrower, bool _sendTokens)
        external;

    // Pause guardian functions
    function _pauseRewards() external;
    function _unpauseRewards() external;

    // Emission schedule admin functions
    function _updateSupplySpeed(HToken _hToken, address _emissionToken, uint256 _newSupplySpeed) external;
    function _updateBorrowSpeed(HToken _hToken, address _emissionToken, uint256 _newBorrowSpeed) external;
    function _updateOwner(HToken _hToken, address _emissionToken, address _newOwner) external;
    function _updateEndTime(HToken _hToken, address _emissionToken, uint256 _newEndTime) external;

    function getGlobalSupplyIndex(address hToken, uint256 index) external view returns (uint256);
    function pauseGuardian() external view returns (address);
    function initialIndexConstant() external view returns (uint224);
    function emissionCap() external view returns (uint256);
    function getCurrentOwner(HToken _hToken, address _emissionToken) external view returns (address);
}
