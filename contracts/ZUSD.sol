// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/ERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Tether.sol";
import "./interfaces/SafeERC20.sol";
import "./interfaces/YVault.sol";
import "./interfaces/PriceFeed.sol";
import "./interfaces/IAdmin.sol";

contract ZUSD is ERC20 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20[4] public tokens;

    uint[4] public tokenDecimals;

    YVault[4] public yVaults;

    PriceFeed public priceFeed;

    IAdmin public admin;

    address public ZETAStake;

    event Mint (
        address indexed account,
        uint userValue,
        uint totalValue,
        uint mintAmount
    );

    event Redeem(
        address indexed account,
        uint userValue,
        uint totalValue,
        uint burnAmount
    );

    uint public feePercentage = 9995;
    uint public totalPercentage = 10000;


    constructor (address adminAddress, address priceFeedAddress) ERC20("ZUSD", "ZUSD") public {

        admin = IAdmin(adminAddress);
        tokens[0] = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); //dai
        tokens[1] = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); //usdc
        tokens[2] = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7); //usdt
        tokens[3] = IERC20(0x0000000000085d4780B73119b644AE5ecd22b376); //tusd

        yVaults[0] = YVault(0xACd43E627e64355f1861cEC6d3a6688B31a6F952); //y vault dai
        yVaults[1] = YVault(0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e); //y vault usdc
        yVaults[2] = YVault(0x2f08119C6f07c006695E079AAFc638b8789FAf18); //y vault usdt
        yVaults[3] = YVault(0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a); //y vault tusd

        tokenDecimals[0] = 1;
        tokenDecimals[1] = 1e12;
        tokenDecimals[2] = 1e12;
        tokenDecimals[3] = 1;

        priceFeed = PriceFeed(priceFeedAddress);
    }

    function changePriceFeed(address addr) external {
        require(msg.sender == admin.admin(), "Not admin");
        priceFeed = PriceFeed(addr);
    }

    function changeZETAStake(address addr) external {
        require(msg.sender == admin.admin(), "Not admin");
        ZETAStake = addr;
    }

    function changeFeePercentage(uint _feePercentage, uint _totalPercentage) external {
        require(msg.sender == admin.admin(), "Not admin");
        feePercentage = _feePercentage;
        totalPercentage = _totalPercentage;
    }

    function getAmountWithoutFee(uint tokenBalance) private view returns (uint) {
        return tokenBalance.mul(feePercentage).div(totalPercentage);
    }

    function toValue(uint amount, uint price, uint decimal) private pure returns (uint) {
        //value = y token amount * token price with decimal sync
        return amount.mul(price).mul(decimal);
    }

    //mint ZUSD and deposit tokens to vault
    function mint(uint[4] memory amounts) external {
        uint userValue;
        uint totalValue;
        uint mintAmount;
        uint totalSupply = totalSupply();
        for (uint idx = 0; idx < 4; idx++) {
            uint amount = amounts[idx];
            YVault yVault = yVaults[idx];
            IERC20 token = tokens[idx];
            IERC20 yToken = IERC20(address(yVault));
            uint latestPrice = priceFeed.getLatestPrice(idx);
            uint _before = yToken.balanceOf(address(this));
            totalValue = totalValue.add(
                toValue(_before, latestPrice, tokenDecimals[idx])
            );

            uint tokenBalance;
            if (amount > 0) {
                //move tokens and approve to vault
                if (idx==2) {
                    IERC20Tether tether = IERC20Tether(address(token));
                    tether.transferFrom(msg.sender, address(this), amount);
                    tokenBalance = token.balanceOf(address(this));
                    tether.approve(address(yVault), tokenBalance);
                } else {
                    token.safeTransferFrom(msg.sender, address(this), amount);
                    tokenBalance = token.balanceOf(address(this));
                    token.approve(address(yVault), tokenBalance);
                }

                yVault.deposit(tokenBalance);

                userValue = userValue.add(
                    toValue(
                        yToken.balanceOf(address(this)).sub(_before),
                        latestPrice,
                        tokenDecimals[idx]));
            }
        }
        if (totalSupply == 0) {
            mintAmount = userValue.div(100000000);
        } else {
            mintAmount = totalSupply.mul(userValue).div(totalValue);
        }
        mintInternal(mintAmount, totalValue, userValue);
    }

    function mintInternal(uint mintAmount, uint totalValue, uint userValue) private {
        _mint(msg.sender, mintAmount);
        emit Mint (
            msg.sender,
            userValue,
            totalValue,
            mintAmount
        );
    }

    //burn ZUSD and withdraw tokens from vault
    function redeem(uint burnAmount, uint[4] memory amounts) external {
        uint userValue;
        uint totalValue;
        for (uint idx = 0; idx < 4; idx++) {
            YVault yVault = yVaults[idx];
            IERC20 token = tokens[idx];
            uint amount = amounts[idx];

            uint latestPrice = priceFeed.getLatestPrice(idx);

            totalValue = totalValue.add(
                toValue(
                    IERC20(address(yVault)).balanceOf(address(this)),
                    latestPrice,
                    tokenDecimals[idx])
            );

            if (amount > 0) {
                userValue = userValue.add(toValue(amount, latestPrice, tokenDecimals[idx]));

                yVault.withdraw(amount);
                uint _after = token.balanceOf(address(this));

                //send withdrawn token to user
                if (idx==2) {
                    IERC20Tether(address(token)).transfer(msg.sender, _after);
                } else {
                    token.safeTransfer(msg.sender, _after);
                }
            }
        }

        redeemInternal(burnAmount, totalValue, userValue);
    }

    function redeemInternal(uint burnAmount, uint totalValue, uint userValue) private {
        uint totalSupply = totalSupply();
        uint burnAmountWithoutFee = getAmountWithoutFee(burnAmount);
        uint actualBurnAmount = totalSupply.mul(userValue).div(totalValue);
        require(actualBurnAmount <= burnAmountWithoutFee, "Too much to redeem");

        _burn(msg.sender, actualBurnAmount);
        _mint(address(this), burnAmount.sub(burnAmountWithoutFee));

        emit Redeem(
            msg.sender,
            userValue,
            totalValue,
            actualBurnAmount
        );
    }

    //transfer ZUSD to ZETA staking contract for rewards
    function sendReward() public {
        require(msg.sender == ZETAStake, "Not stake contract");
        uint rewardAmount = balanceOf(address(this));
        _burn(address(this), rewardAmount);
        _mint(ZETAStake, rewardAmount);
    }

    //get y token amounts from token amounts
    function getYTokenWithToken(uint[4] memory amounts) public view returns (uint[4] memory) {
        uint[4] memory ret;
        for (uint idx=0; idx<4; idx++) {
            ret[idx] = IERC20(address(yVaults[idx])).totalSupply()
                .mul(amounts[idx])
                .div(yVaults[idx].balance());
        }
        return ret;
    }

    function getVaultBalances() public view returns (uint[4] memory) {
        uint[4] memory ret;
        for (uint idx=0; idx<4; idx++) {
            ret[idx] = yVaults[idx].balance();
        }
        return ret;
    }

    function getVaultTotalSupply() public view returns (uint[4] memory) {
        uint[4] memory ret;
        for (uint idx=0; idx<4; idx++) {
            ret[idx] = IERC20(address(yVaults[idx])).totalSupply();
        }
        return ret;
    }

    //get all prices of tokens
    function getAllPrices() public view returns (uint[4] memory){
        uint[4] memory ret;
        for (uint idx=0; idx<4; idx++) {
            ret[idx] = priceFeed.getLatestPrice(idx);
        }
        return ret;
    }

    //get total value
    function getTotalValue() public view returns (uint) {
        uint ret;
        for (uint idx=0; idx<4; idx++) {
            ret = ret.add(toValue(
                    IERC20(address(yVaults[idx])).balanceOf(address(this)),
                    priceFeed.getLatestPrice(idx),
                    tokenDecimals[idx]
                ));
        }
        return ret;
    }

    //get each y token amounts
    function getTotalYToken() public view returns (uint[4] memory) {
        uint[4] memory ret;
        for (uint idx=0; idx<4; idx++) {
            ret[idx] = IERC20(address(yVaults[idx])).balanceOf(address(this));
        }
        return ret;
    }

    //get total value
    function getTokenValueWithYToken() public view returns (uint) {
        uint ret;
        for (uint idx=0; idx<4; idx++) {
            ret = ret.add(
                toValue(
                    yVaults[idx].balance()
                        .mul(IERC20(address(yVaults[idx])).balanceOf(address(this)))
                        .div(IERC20(address(yVaults[idx])).totalSupply()),
                    priceFeed.getLatestPrice(idx),
                    tokenDecimals[idx])
                );
        }
        return ret;
    }

    function getTokensOfVaults() public view returns (uint[4] memory) {
        uint[4] memory ret;
        for (uint idx=0; idx<4; idx++) {
            ret[idx] = tokens[idx].balanceOf(address(yVaults[idx]));
        }
        return ret;
    }
}
