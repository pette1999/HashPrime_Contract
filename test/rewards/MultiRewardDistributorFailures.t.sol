// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import "src/rewards/MultiRewardDistributor.sol";
import "src/rewards/IMultiRewardDistributor.sol";

import {HToken} from "src/HToken.sol";
import {SigUtils} from "test/helper/SigUtils.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {Comptroller} from "src/Comptroller.sol";
import {HErc20Delegate} from "src/HErc20Delegate.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {HErc20Immutable} from "src/mock/token/HErc20Immutable.sol";
import {SimplePriceOracle} from "src/mock/oracle/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "src/irm/WhitePaperInterestRateModel.sol";
import {InterestRateModel} from "src/irm/InterestRateModel.sol";

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract MultiRewardDistributorFailures is Test {
    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetTokenWithPermit faucetToken;
    FaucetTokenWithPermit emissionToken;
    HErc20Immutable hToken;
    InterestRateModel irModel;
    MultiRewardDistributor distributor;
    address constant pauseGuardian = address(100);
    address constant compAdmin = address(100);
    address public constant proxyAdmin = address(1337);

    function setUp() public {
        vm.prank(compAdmin);
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        faucetToken = new FaucetTokenWithPermit(0, "Testing", 18, "TEST");
        irModel = new WhitePaperInterestRateModel(0.1e18, 0.45e18);
        distributor = new MultiRewardDistributor();
        bytes memory initdata =
            abi.encodeWithSignature("initialize(address,address)", address(comptroller), pauseGuardian);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(distributor), proxyAdmin, initdata);
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        hToken = new HErc20Immutable(
            address(faucetToken),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test hToken",
            "hTEST",
            8,
            payable(address(this))
        );

        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(hToken);
        oracle.setUnderlyingPrice(hToken, 1e18);

        comptroller._setCollateralFactor(hToken, 0.5e18); // 50% CF

        emissionToken = new FaucetTokenWithPermit(0, "Emission Token", 18, "EMIT");
    }

    function testSetup() public view {
        assertEq(compAdmin, comptroller.admin());
        assertEq(distributor.emissionCap(), 100 ether);
        assertEq(distributor.initialIndexConstant(), 1e36);
        assertEq(pauseGuardian, distributor.pauseGuardian());
        assertEq(address(comptroller), address(distributor.comptroller()));
    }

    function testCannotReinitializeLogicContract() public {
        distributor = new MultiRewardDistributor();

        vm.expectRevert("Initializable: contract is already initialized");
        distributor.initialize(address(comptroller), pauseGuardian);
    }

    function testComptrollerZeroAddressFails() public {
        new MultiRewardDistributor();
        distributor = new MultiRewardDistributor();
        bytes memory initdata =
            abi.encodeWithSignature("initialize(address,address)", address(0), address(pauseGuardian));

        vm.expectRevert("Comptroller can't be the 0 address!");
        new TransparentUpgradeableProxy(address(distributor), proxyAdmin, initdata);
    }

    function testPauseGuardianZeroAddressFails() public {
        new MultiRewardDistributor();
        distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature("initialize(address,address)", address(this), address(0));

        vm.expectRevert("Pause Guardian can't be the 0 address!");
        new TransparentUpgradeableProxy(address(distributor), proxyAdmin, initdata);
    }

    function testNonComptrollerBindFails() public {
        distributor = new MultiRewardDistributor();
        bytes memory initdata =
            abi.encodeWithSignature("initialize(address,address)", address(this), address(pauseGuardian));

        vm.expectRevert("Can't bind to something that's not a comptroller!");
        new TransparentUpgradeableProxy(address(distributor), proxyAdmin, initdata);
    }

    function isComptroller() external pure returns (bool) {
        return false;
    }

    /// ACL tests

    function testSetPauseGuardianNonGuardianOrAdminFails() public {
        vm.expectRevert("Only the pause guardian or comptroller admin can call this function");
        distributor._setPauseGuardian(address(100000));
    }

    function testPauseRewardsNonGuardianOrAdminFails() public {
        vm.expectRevert("Only the pause guardian or comptroller admin can call this function");
        distributor._pauseRewards();
    }

    function testRescueFundsNonAdminFails() public {
        vm.expectRevert("Only the comptroller's administrator can do this!");
        vm.prank(address(1));
        distributor._rescueFunds(address(emissionToken), 1);
    }

    function test_unpauseRewardsNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller's administrator can do this!");
        distributor._unpauseRewards();
    }

    function testAddEmissionConfigNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller's administrator can do this!");
        distributor._addEmissionConfig(
            HToken(address(1)), compAdmin, address(emissionToken), 1e18, 1e18, vm.getBlockTimestamp() + 365 days
        );
    }

    function testSetEmissionCapNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller's administrator can do this!");
        distributor._setEmissionCap(1);
    }

    function testUpdateMarketSupplyIndexNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller or comptroller admin can call this function");
        distributor.updateMarketSupplyIndex(hToken);
    }

    function testDisburseSupplierRewardsNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller or comptroller admin can call this function");
        distributor.disburseSupplierRewards(hToken, address(1), true);
    }

    function testUpdateMarketBorrowIndexNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller or comptroller admin can call this function");
        distributor.updateMarketBorrowIndex(hToken);
    }

    function testDisburseBorrowerRewardsNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller or comptroller admin can call this function");
        distributor.disburseBorrowerRewards(hToken, address(1), true);
    }

    function testUpdateMarketBorrowIndexAndDisburseBorrowerRewardsNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller or comptroller admin can call this function");
        distributor.updateMarketBorrowIndexAndDisburseBorrowerRewards(hToken, address(1), true);
    }

    function testUpdateMarketSupplyIndexAndDisburseSupplierRewardsNonComptrollerAdminFails() public {
        vm.expectRevert("Only the comptroller or comptroller admin can call this function");
        distributor.updateMarketSupplyIndexAndDisburseSupplierRewards(hToken, address(1), true);
    }
}
