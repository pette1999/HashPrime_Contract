pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {HToken} from "src/HToken.sol";
import {SigUtils} from "test/helper/SigUtils.sol";
import {Comptroller} from "src/Comptroller.sol";
import {HErc20Immutable} from "src/mock/token/HErc20Immutable.sol";
import {SimplePriceOracle} from "src/mock/oracle/SimplePriceOracle.sol";
import {InterestRateModel} from "src/irm/InterestRateModel.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {ComptrollerErrorReporter} from "src/ErrorReporter.sol";
import {JumpRateModel} from "src/irm/JumpRateModel.sol";

interface InstrumentedExternalEvents {
    event PricePosted(
        address asset, uint256 previousPriceMantissa, uint256 requestedPriceMantissa, uint256 newPriceMantissa
    );
    event NewCollateralFactor(HToken hToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Mint(address minter, uint256 mintAmount, uint256 mintTokens);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}

contract TErc20UnitTest is Test, InstrumentedExternalEvents, ComptrollerErrorReporter {
    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetTokenWithPermit faucetToken;
    HErc20Immutable hToken;
    InterestRateModel irModel;
    SigUtils sigUtils;

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        faucetToken = new FaucetTokenWithPermit(1e18, "Testing", 18, "TEST");
        irModel = new JumpRateModel(0.02e18, 0.15e18, 3e18, 0.6e18);

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

        sigUtils = new SigUtils(faucetToken.DOMAIN_SEPARATOR());

        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(hToken);
        oracle.setUnderlyingPrice(hToken, 1e18);
    }

    function testMintWithPermit() public {
        uint256 userPK = 0xA11CE;
        address user = vm.addr(userPK);

        faucetToken.allocateTo(user, 1e18);

        // Make sure our user has some tokens, but not hTokens
        assertEq(faucetToken.balanceOf(user), 1e18);
        assertEq(hToken.balanceOf(user), 0);

        uint256 deadline = 1 minutes;
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: user, spender: address(hToken), value: 1e18, nonce: 0, deadline: deadline});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPK, digest);

        // Ensure an Approval event was emitted as expected
        vm.expectEmit(true, true, true, true, address(faucetToken));
        emit Approval(user, address(hToken), 1e18);

        // Ensure an Mint event was emitted as expected
        vm.expectEmit(true, true, true, true, address(hToken));
        emit Mint(user, 1e18, 1e18);

        // Ensure an Transfer event was emitted as expected
        vm.expectEmit(true, true, true, true, address(hToken));
        emit Transfer(address(hToken), user, 1e18);

        // Go mint as a user with permit
        vm.prank(user);
        hToken.mintWithPermit(1e18, deadline, v, r, s);

        // Make sure our ending state was as expected
        assertEq(faucetToken.balanceOf(user), 0);
        assertEq(hToken.balanceOf(user), 1e18);
    }
}
