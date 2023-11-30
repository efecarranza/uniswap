// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

import {ERC20} from "open-zeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "open-zeppelin/access/Ownable.sol";

import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "./IUniswapV2.sol";

contract DCA is Ownable {
    /// @notice User is trying to withdraw too many tokens
    error ExceedsBalance();

    /// @notice A value greater than zero is required to invest
    error MinimumAmountRequired();

    /// @notice A value greater than zero is required to invest per period
    error MinimumAmountRequiredPerPeriod();

    /// @notice User is already investing in DCA strategy
    error UserAlreadyInvested();

    event NewInvestment(
        address indexed user,
        address indexed token,
        uint128 amount
    );

    event InvestmentFinished(address indexed user, address indexed token);

    enum Frequency {
        DAILY,
        WEEKLY,
        MONTHLY
    }

    struct Investment {
        uint256 toInvest;
        uint128 perPeriod;
        uint128 lastPurchase;
        Frequency frequency;
    }

    address public constant UNI_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    AggregatorV3Interface public immutable feed;

    address public immutable token;

    mapping(address user => Investment dca) private investments;

    constructor(address _swapToken, address _feed) Ownable(msg.sender) {
        token = _swapToken;
        feed = AggregatorV3Interface(_feed);
    }

    function invest(uint128 perPeriod, Frequency frequency) external payable {
        if (msg.value == 0) revert MinimumAmountRequired();
        if (perPeriod == 0) revert MinimumAmountRequiredPerPeriod();
        if (investments[msg.sender].perPeriod != 0) {
            revert UserAlreadyInvested();
        }

        Investment memory newInvestment = Investment(
            msg.value,
            perPeriod,
            0,
            frequency
        );

        investments[msg.sender] = newInvestment;
    }

    function dca(address[] calldata users) external onlyOwner {
        uint256 usersLength = users.length;
        for (uint256 i = 0; i < usersLength; ) {
            Investment memory tempInvestment = investments[users[i]];

            if (tempInvestment.toInvest == 0) continue;

            uint128 toPurchase = tempInvestment.perPeriod >
                tempInvestment.toInvest
                ? tempInvestment.toInvest
                : tempInvestment.perPeriod;

            tempInvestment.toInvest -= toPurchase;

            address[] memory path = new address[](2);
            path[0] = IUniswapV2Router02(UNI_ROUTER).WETH();
            path[1] = token;

            uint256 oraclePrice = getOraclePrice();

            /** 
            The actual calculation is a collapsed version of this to prevent precision loss:
            => amountOut = (amountCRVWei / 10^crvDecimals) * (chainlinkPrice / chainlinkPrecision) * 10^usdcDecimals
            => amountOut = (amountCRVWei / 10^18) * (chainlinkPrice / 10^8) * 10^6
         */

            uint256 amountOut = (_amountIn * getOraclePrice()) / 10 ** 20;
            // 10 bps arbitrage incentive
            return (amountOut * 10010) / 10000;

            uint[] memory amountsOut = IUniswapV2Router02(UNI_ROUTER)
                .swapExactETHForTokens{value: toPurchase}(
                amountOutMin,
                path,
                users[i],
                block.timestamp
            );

            tempInvestment.lastPurchase = uint128(block.timestamp);

            investments[msg.sender] = tempInvestment;

            unchecked {
                ++i;
            }
        }
    }

    function viewUserDetails(
        address user
    ) public view returns (Investment memory) {
        return investments[user];
    }

    function getOraclePrice() public view returns (uint256) {
        (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }
}
