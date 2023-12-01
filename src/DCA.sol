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

    /// @dev Emitted when a user registered to DCA
    event NewInvestment(
        address indexed user,
        address indexed token,
        uint128 amount
    );

    /// @dev Emitted when a user's funds are depleted
    event InvestmentFinished(address indexed user, address indexed token);

    /// @dev Emitted each time a DCA purchase happens
    event Purchased(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    /// @dev Different frequencies for DCA
    enum Frequency {
        DAILY,
        WEEKLY,
        MONTHLY
    }

    /// @dev Stores the user's investment information
    struct Investment {
        uint128 toInvest;
        uint128 perPeriod;
        uint256 lastPurchase;
        Frequency frequency;
    }

    /// @dev UniswapV2 Factory
    address public immutable factory;

    /// @dev UniswapV2 Router
    address public immutable router;

    /// @dev Chainlink's ETH/USD feed
    AggregatorV3Interface public immutable ethFeed;

    /// @dev Chainlink's TOKEN/USD feed
    AggregatorV3Interface public immutable feed;

    /// @dev Address of token to purchase via DCA
    address public immutable token;

    /// @notice Mapping of users to their investment information
    mapping(address user => Investment dca) private investments;

    /// @notice Creates a new DCA contract
    /// @param _swapToken The address of the token to acquire via DCA
    /// @param _feed The Chainlink TOKEN/USD feed
    /// @param _ethFeed The Chainlink ETH/USD feed
    /// @param _uniFactory The UniswapV2 Factory address
    /// @param _uniRouter The UniswapV2 Router address
    constructor(
        address _swapToken,
        address _feed,
        address _ethFeed,
        address _uniFactory,
        address _uniRouter
    ) Ownable(msg.sender) {
        token = _swapToken;
        feed = AggregatorV3Interface(_feed);
        ethFeed = AggregatorV3Interface(_ethFeed);
        factory = _uniFactory;
        router = _uniRouter;

        address pair = IUniswapV2Factory(factory).getPair(
            token,
            IUniswapV2Router02(router).WETH()
        );
        if (pair == address(0)) revert PairNotCreated();
    }

    /// @notice Registers user in the system to DCA into token
    /// @param perPeriod How many tokens to spend per period
    /// @param frequency The frequency in which to DCA
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

    /// @notice Function called to DCA users
    /// @param users Addresses of users to DCA for
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
            path[0] = IUniswapV2Router02(router).WETH();
            path[1] = token;

            uint[] memory amountsOut = IUniswapV2Router02(router)
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

    /// @notice Returns the user's investment information
    /// @return User's last purchase timestamp, per period purchase and remaining funds
    function viewUserDetails(
        address user
    ) public view returns (Investment memory) {
        return investments[user];
    }

    /// @notice Returns the oracle's current price
    /// @param isEthFeed Whether to return ETH/USD or TOKEN/USD
    /// @return The current value of the oracle
    function getOraclePrice(bool isEthFeed) public view returns (uint256) {
        (, int256 price, , , ) = isEthFeed
            ? ethFeed.latestRoundData()
            : feed.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }

    /// @notice Returns the expected amount out (used to prevent issues with price)
    /// @param toPurchase The amount of ETH to use
    /// @return The amount of tokens to expect at a minimum
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

    /// @dev Function used to validate DCA frequencies. Used to avoid operator from
    /// DCA'ing multiple times to exhaust user's funds.
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
