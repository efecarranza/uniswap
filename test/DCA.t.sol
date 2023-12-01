// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";

import {DCA} from "../src/DCA.sol";

contract DCATest is Test {
    event InvestmentFinished(address indexed user, address indexed token);

    event Purchased(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    address public constant UNI_FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant UNI_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant ETH_USD_FEED =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant AAVE_USD_FEED =
        0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    DCA public dca;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 18693369);
        dca = new DCA(
            AAVE,
            AAVE_USD_FEED,
            ETH_USD_FEED,
            UNI_FACTORY,
            UNI_ROUTER
        );
    }
}

contract ConstructorTest is DCATest {
    function test_revertsIf_pairDoesNotExist() public {
        vm.expectRevert(DCA.PairNotCreated.selector);
        new DCA(
            makeAddr("does-not-exist"),
            AAVE_USD_FEED,
            ETH_USD_FEED,
            UNI_FACTORY,
            UNI_ROUTER
        );
    }

    function test_successful() public {
        DCA newDca = new DCA(
            AAVE,
            AAVE_USD_FEED,
            ETH_USD_FEED,
            UNI_FACTORY,
            UNI_ROUTER
        );
        assertEq(newDca.token(), AAVE);
        assertEq(address(newDca.feed()), AAVE_USD_FEED);
    }
}

contract InvestTest is DCATest {
    function test_revertsIf_msgValueIsZero() public {
        vm.expectRevert(DCA.MinimumAmountRequired.selector);
        dca.invest{value: 0}(1 ether, DCA.Frequency.WEEKLY);
    }

    function test_revertsIf_perPeriodIsZero() public {
        vm.expectRevert(DCA.MinimumAmountRequiredPerPeriod.selector);
        dca.invest{value: 1 ether}(0, DCA.Frequency.WEEKLY);
    }

    function test_revertsIf_userAlreadyInvested() public {
        dca.invest{value: 1 ether}(0.5 ether, DCA.Frequency.WEEKLY);

        vm.expectRevert(DCA.UserAlreadyInvested.selector);
        dca.invest{value: 1 ether}(0.5 ether, DCA.Frequency.WEEKLY);
    }

    function test_successful() public {
        dca.invest{value: 1 ether}(0.5 ether, DCA.Frequency.WEEKLY);

        DCA.Investment memory userInvestment = dca.viewUserDetails(
            address(this)
        );

        assertTrue(userInvestment.frequency == DCA.Frequency.WEEKLY);
        assertEq(userInvestment.toInvest, 1 ether);
        assertEq(userInvestment.perPeriod, 0.5 ether);
        assertEq(userInvestment.lastPurchase, 0);
    }
}

contract DCAUsersTest is DCATest {
    function test_addressZeroIsSkipped() public {
        address[] memory users = new address[](1);
        users[0] = address(0);
        dca.dcaUsers(users);
    }

    function test_emptyArrayNothingHappens() public {
        address[] memory users = new address[](1);
        dca.dcaUsers(users);
    }

    function test_usersHasNothingToInvest() public {
        address[] memory users = new address[](1);
        users[0] = makeAddr("random-address");
        dca.dcaUsers(users);
    }

    function test_dcaOnceSuccessful() public {
        dca.invest{value: 1 ether}(0.5 ether, DCA.Frequency.WEEKLY);

        address[] memory users = new address[](1);
        users[0] = address(this);

        vm.expectEmit(true, true, true, true);
        emit Purchased(address(this), AAVE, 10349021787011245697);

        dca.dcaUsers(users);

        DCA.Investment memory userInvestment = dca.viewUserDetails(
            address(this)
        );

        assertEq(userInvestment.toInvest, 0.5 ether);
        assertEq(userInvestment.lastPurchase, block.timestamp);
    }

    function test_dcaTwiceCannotHappen() public {
        dca.invest{value: 1 ether}(0.5 ether, DCA.Frequency.WEEKLY);

        address[] memory users = new address[](1);
        users[0] = address(this);

        dca.dcaUsers(users);

        DCA.Investment memory userInvestment = dca.viewUserDetails(
            address(this)
        );

        assertEq(userInvestment.toInvest, 0.5 ether);
        assertEq(userInvestment.lastPurchase, block.timestamp);

        vm.warp(block.timestamp + 6 days);

        dca.dcaUsers(users);

        DCA.Investment memory userInvestmentAfter = dca.viewUserDetails(
            address(this)
        );

        assertEq(userInvestmentAfter.toInvest, userInvestment.toInvest);
        assertEq(userInvestmentAfter.lastPurchase, userInvestment.lastPurchase);
    }

    function test_dcaUserIsRemovedAfterFinishing() public {
        dca.invest{value: 1 ether}(0.5 ether, DCA.Frequency.WEEKLY);

        address[] memory users = new address[](1);
        users[0] = address(this);

        dca.dcaUsers(users);

        DCA.Investment memory userInvestment = dca.viewUserDetails(
            address(this)
        );

        assertEq(userInvestment.toInvest, 0.5 ether);
        assertEq(userInvestment.lastPurchase, block.timestamp);

        vm.warp(block.timestamp + 8 days);

        vm.expectEmit(true, true, true, true);
        emit InvestmentFinished(address(this), AAVE);
        dca.dcaUsers(users);

        DCA.Investment memory userInvestmentAfter = dca.viewUserDetails(
            address(this)
        );

        assertEq(userInvestmentAfter.toInvest, 0);
        assertEq(userInvestmentAfter.perPeriod, 0);
        assertEq(userInvestmentAfter.lastPurchase, 0);
    }
}

contract GetOraclePrice is DCATest {
    function test_ethResult() public {
        uint256 price = dca.getOraclePrice(true);
        assertEq(price, 209405906218); // ETH price ~2,000
    }

    function test_tokenResult() public {
        uint256 price = dca.getOraclePrice(false);
        assertEq(price, 10096894592); // AAVE price ~100
    }
}

contract GetAmountOutTest is DCATest {
    function test_getAmountOut() public {
        uint256 amountOut = dca.getAmountOut(1e18);
        assertEq(amountOut, 19752033120768785984); // ETH ~2,000, AAVE ~ 100 so 20 AAVE per ETH
    }
}
