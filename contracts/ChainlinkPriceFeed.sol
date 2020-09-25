// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./interfaces/SafeMath.sol";
import "./interfaces/IAdmin.sol";

interface AggregatorV3Interface {

    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
    external
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function latestRoundData()
    external
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

}

contract ChainlinkPriceFeed {
    using SafeMath for uint;

    AggregatorV3Interface[] internal priceFeed;
    AggregatorV3Interface internal priceFeedETHToUSD;
    IAdmin public admin;

    constructor(address adminAddress) public {
        priceFeed.push(AggregatorV3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4)); //dai to eth
        priceFeed.push(AggregatorV3Interface(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4)); //usdc to eth
        priceFeed.push(AggregatorV3Interface(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46)); //usdt to eth
        priceFeed.push(AggregatorV3Interface(0x3886BA987236181D98F2401c507Fb8BeA7871dF2)); //tusd to eth
        priceFeedETHToUSD = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); //eth to usd
        admin = IAdmin(adminAddress);
    }

    function addPriceFeed(address addr) public {
        require(msg.sender == admin.admin(), "Not admin");
        priceFeed.push(AggregatorV3Interface(addr));
    }

    function getLatestPrice(uint idx) public view returns (uint) {
        require(idx < priceFeed.length, "No price feed");
        (,int priceETH,,uint timeStampETH,) = priceFeed[idx].latestRoundData();
        (,int priceUSD,,uint timeStampUSD,) = priceFeedETHToUSD.latestRoundData();
        require(timeStampETH > 0 && timeStampUSD > 0, "Price feed round not complete");
        return uint(priceETH).mul(uint(priceUSD)).div(1e18);
    }
}