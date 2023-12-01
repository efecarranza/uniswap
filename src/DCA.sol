// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

import {ERC20} from "open-zeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "open-zeppelin/access/Ownable.sol";

import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Factory, IUniswapV2Router02} from "./IUniswapV2.sol";

contract DCA is Ownable {
    /// @notice User is trying to withdraw too many tokens
    error ExceedsBalance();

    /// @notice The oracle is not currently returning a valid answer
    error InvalidOracleAnswer();

    /// @notice A value greater than zero is required to invest
    error MinimumAmountRequired();

    /// @notice A value greater than zero is required to invest per period
    error MinimumAmountRequiredPerPeriod();

    error PairNotCreated();

    /// @notice User is already investing in DCA strategy
    error UserAlreadyInvested();

    event NewInvestment(
        address indexed user,
        address indexed token,
        uint128 amount
    );

    event InvestmentFinished(address indexed user, address indexed token);

    event Purchased(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    enum Frequency {
        DAILY,
        WEEKLY,
        MONTHLY
    }

    struct Investment {
        uint128 toInvest;
        uint128 perPeriod;
        uint256 lastPurchase;
        Frequency frequency;
    }

    address public constant UNI_FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant UNI_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    AggregatorV3Interface public constant ethFeed =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    AggregatorV3Interface public immutable feed;

    address public immutable token;

    mapping(address user => Investment dca) private investments;

    constructor(address _swapToken, address _feed) Ownable(msg.sender) {
        token = _swapToken;
        feed = AggregatorV3Interface(_feed);

        address pair = IUniswapV2Factory(UNI_FACTORY).getPair(
            token,
            IUniswapV2Router02(UNI_ROUTER).WETH()
        );
        if (pair == address(0)) revert PairNotCreated();
    }

    function invest(uint128 perPeriod, Frequency frequency) external payable {
        if (msg.value == 0) revert MinimumAmountRequired();
        if (perPeriod == 0) revert MinimumAmountRequiredPerPeriod();
        if (investments[msg.sender].perPeriod != 0) {
            revert UserAlreadyInvested();
        }

        Investment memory newInvestment = Investment(
            uint128(msg.value),
            perPeriod,
            0,
            frequency
        );

        investments[msg.sender] = newInvestment;
    }

    function dcaUsers(address[] calldata users) external onlyOwner {
        uint256 usersLength = users.length;
        for (uint256 i = 0; i < usersLength; ++i) {
            if (users[i] == address(0)) continue;

            Investment memory tempInvestment = investments[users[i]];

            if (tempInvestment.toInvest == 0) continue;

            if (
                !_validateFrequency(
                    tempInvestment.frequency,
                    tempInvestment.lastPurchase
                )
            ) continue;

            uint128 toPurchase = tempInvestment.perPeriod >
                tempInvestment.toInvest
                ? tempInvestment.toInvest
                : tempInvestment.perPeriod;

            tempInvestment.toInvest -= toPurchase;

            address[] memory path = new address[](2);
            path[0] = IUniswapV2Router02(UNI_ROUTER).WETH();
            path[1] = token;

            uint[] memory amountsOut = IUniswapV2Router02(UNI_ROUTER)
                .swapExactETHForTokens{value: toPurchase}(
                getAmountOut(toPurchase),
                path,
                users[i],
                block.timestamp
            );

            tempInvestment.lastPurchase = uint128(block.timestamp);

            emit Purchased(users[i], token, amountsOut[1]);

            if (tempInvestment.toInvest == 0) {
                delete investments[users[i]];
                emit InvestmentFinished(users[i], token);
            } else {
                investments[users[i]] = tempInvestment;
            }
        }
    }

    function viewUserDetails(
        address user
    ) public view returns (Investment memory) {
        return investments[user];
    }

    function getOraclePrice(bool isEthFeed) public view returns (uint256) {
        (, int256 price, , , ) = isEthFeed
            ? ethFeed.latestRoundData()
            : feed.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }

    function getAmountOut(uint128 toPurchase) public view returns (uint256) {
        uint256 tokenPrice = getOraclePrice(false);
        uint256 ethPrice = getOraclePrice(true);

        /** 
            The actual calculation is a collapsed version of this to prevent precision loss:
            => amountOut = (amountEthWei / 10^ethDecimals) * (ethPrice / ethPrecision) * 10^tokenPrecision / tokenPrice
            => amountOut = (amountEthWei / 10^18) * (ethPrice / 10^8) * 10^8 / tokenPrice * 10^18
         */

        uint256 amountOut = (toPurchase * ethPrice) / tokenPrice; // In prod: handle where token price > ETH price.

        return (amountOut * 10000) / 10500; // Discount Chainlink Oracle a bit
    }

    function _validateFrequency(
        Frequency frequency,
        uint256 lastPurchase
    ) internal view returns (bool) {
        if (frequency == Frequency.DAILY) {
            return block.timestamp > (lastPurchase + 1 days);
        } else if (frequency == Frequency.WEEKLY) {
            return block.timestamp > (lastPurchase + 1 weeks);
        } else if (frequency == Frequency.MONTHLY) {
            return block.timestamp > lastPurchase + 30 days;
        }

        return false;
    }
}
