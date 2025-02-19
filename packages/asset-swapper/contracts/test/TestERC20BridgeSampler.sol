// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/
pragma solidity ^0.6;
pragma experimental ABIEncoderV2;

import "../src/ERC20BridgeSampler.sol";
import "../src/interfaces/IKyberNetwork.sol";
import "../src/interfaces/IUniswapV2Router01.sol";


library LibDeterministicQuotes {

    address private constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 private constant RATE_DENOMINATOR = 1 ether;
    uint256 private constant MIN_RATE = RATE_DENOMINATOR / 100;
    uint256 private constant MAX_RATE = 100 * RATE_DENOMINATOR;
    uint8 private constant MIN_DECIMALS = 4;
    uint8 private constant MAX_DECIMALS = 20;

    function getDeterministicSellQuote(
        bytes32 salt,
        address sellToken,
        address buyToken,
        uint256 sellAmount
    )
        internal
        pure
        returns (uint256 buyAmount)
    {
        uint256 sellBase = uint256(10) ** getDeterministicTokenDecimals(sellToken);
        uint256 buyBase = uint256(10) ** getDeterministicTokenDecimals(buyToken);
        uint256 rate = getDeterministicRate(salt, sellToken, buyToken);
        return sellAmount * rate * buyBase / sellBase / RATE_DENOMINATOR;
    }

    function getDeterministicBuyQuote(
        bytes32 salt,
        address sellToken,
        address buyToken,
        uint256 buyAmount
    )
        internal
        pure
        returns (uint256 sellAmount)
    {
        uint256 sellBase = uint256(10) ** getDeterministicTokenDecimals(sellToken);
        uint256 buyBase = uint256(10) ** getDeterministicTokenDecimals(buyToken);
        uint256 rate = getDeterministicRate(salt, sellToken, buyToken);
        return buyAmount * RATE_DENOMINATOR * sellBase / rate / buyBase;
    }

    function getDeterministicTokenDecimals(address token)
        internal
        pure
        returns (uint8 decimals)
    {
        if (token == WETH_ADDRESS) {
            return 18;
        }
        bytes32 seed = keccak256(abi.encodePacked(token));
        return uint8(uint256(seed) % (MAX_DECIMALS - MIN_DECIMALS)) + MIN_DECIMALS;
    }

    function getDeterministicRate(bytes32 salt, address sellToken, address buyToken)
        internal
        pure
        returns (uint256 rate)
    {
        bytes32 seed = keccak256(abi.encodePacked(salt, sellToken, buyToken));
        return uint256(seed) % (MAX_RATE - MIN_RATE) + MIN_RATE;
    }
}

contract TestDeploymentConstants {

    // solhint-disable separate-by-one-line-in-contract

    // Mainnet addresses ///////////////////////////////////////////////////////
    /// @dev Mainnet address of the WETH contract.
    address constant private WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev Overridable way to get the WETH address.
    /// @return wethAddress The WETH address.
    function _getWethAddress()
        internal
        view
        returns (address wethAddress)
    {
        return WETH_ADDRESS;
    }

}

contract FailTrigger {

    // Give this address a balance to force operations to fail.
    address payable constant public FAILURE_ADDRESS = 0xe9dB8717BC5DFB20aaf538b4a5a02B7791FF430C;

    // Funds `FAILURE_ADDRESS`.
    function enableFailTrigger() external payable {
        FAILURE_ADDRESS.transfer(msg.value);
    }

    function _revertIfShouldFail() internal view {
        if (FAILURE_ADDRESS.balance != 0) {
            revert("FAIL_TRIGGERED");
        }
    }
}


contract TestERC20BridgeSamplerUniswapExchange is
    IUniswapExchangeQuotes,
    TestDeploymentConstants,
    FailTrigger
{
    bytes32 constant private BASE_SALT = 0x1d6a6a0506b0b4a554b907a4c29d9f4674e461989d9c1921feb17b26716385ab;

    address public tokenAddress;
    bytes32 public salt;

    constructor(address _tokenAddress) public {
        tokenAddress = _tokenAddress;
        salt = keccak256(abi.encodePacked(BASE_SALT, _tokenAddress));
    }

    // Deterministic `IUniswapExchangeQuotes.getEthToTokenInputPrice()`.
    function getEthToTokenInputPrice(
        uint256 ethSold
    )
        override
        external
        view
        returns (uint256 tokensBought)
    {
        _revertIfShouldFail();
        return LibDeterministicQuotes.getDeterministicSellQuote(
            salt,
            tokenAddress,
            _getWethAddress(),
            ethSold
        );
    }

    // Deterministic `IUniswapExchangeQuotes.getEthToTokenOutputPrice()`.
    function getEthToTokenOutputPrice(
        uint256 tokensBought
    )
        override
        external
        view
        returns (uint256 ethSold)
    {
        _revertIfShouldFail();
        return LibDeterministicQuotes.getDeterministicBuyQuote(
            salt,
            _getWethAddress(),
            tokenAddress,
            tokensBought
        );
    }

    // Deterministic `IUniswapExchangeQuotes.getTokenToEthInputPrice()`.
    function getTokenToEthInputPrice(
        uint256 tokensSold
    )
        override
        external
        view
        returns (uint256 ethBought)
    {
        _revertIfShouldFail();
        return LibDeterministicQuotes.getDeterministicSellQuote(
            salt,
            tokenAddress,
            _getWethAddress(),
            tokensSold
        );
    }

    // Deterministic `IUniswapExchangeQuotes.getTokenToEthOutputPrice()`.
    function getTokenToEthOutputPrice(
        uint256 ethBought
    )
        override
        external
        view
        returns (uint256 tokensSold)
    {
        _revertIfShouldFail();
        return LibDeterministicQuotes.getDeterministicBuyQuote(
            salt,
            _getWethAddress(),
            tokenAddress,
            ethBought
        );
    }
}


contract TestERC20BridgeSamplerUniswapV2Router01 is
    IUniswapV2Router01,
    TestDeploymentConstants,
    FailTrigger
{
    bytes32 constant private SALT = 0xadc7fcb33c735913b8635927e66896b356a53a912ab2ceff929e60a04b53b3c1;

    // Deterministic `IUniswapV2Router01.getAmountsOut()`.
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        override
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "PATH_TOO_SHORT");
        _revertIfShouldFail();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; ++i) {
            amounts[i + 1] = LibDeterministicQuotes.getDeterministicSellQuote(
                SALT,
                path[i],
                path[i + 1],
                amounts[i]
            );
        }
    }

    // Deterministic `IUniswapV2Router01.getAmountsInt()`.
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        override
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "PATH_TOO_SHORT");
        _revertIfShouldFail();
        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; --i) {
            amounts[i - 1] = LibDeterministicQuotes.getDeterministicBuyQuote(
                SALT,
                path[i - 1],
                path[i],
                amounts[i]
            );
        }
    }
}


// solhint-disable space-after-comma
contract TestERC20BridgeSamplerKyberNetwork is
    TestDeploymentConstants,
    FailTrigger
{
    bytes32 constant private SALT = 0x0ff3ca9d46195c39f9a12afb74207b4970349fb3cfb1e459bbf170298d326bc7;
    address constant public ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    enum TradeType {BestOfAll, MaskIn, MaskOut, Split}
    enum ProcessWithRate {NotRequired, Required}

    // IKyberHintHandler
    function buildTokenToEthHint(
        address tokenSrc,
        TradeType /* tokenToEthType */,
        bytes32[] calldata /* tokenToEthReserveIds */,
        uint256[] calldata /* tokenToEthSplits */
    ) external view returns (bytes memory hint)
    {
        return abi.encode(tokenSrc);
    }

    function buildEthToTokenHint(
        address tokenDest,
        TradeType /* ethToTokenType */,
        bytes32[] calldata /* ethToTokenReserveIds */,
        uint256[] calldata /* ethToTokenSplits */
    ) external view returns (bytes memory hint)
    {
        return abi.encode(tokenDest);
    }

    // IKyberHintHandler
    function buildTokenToTokenHint(
        address tokenSrc,
        TradeType /* tokenToEthType */,
        bytes32[] calldata /* tokenToEthReserveIds */,
        uint256[] calldata /* tokenToEthSplits */,
        address /* tokenDest  */,
        TradeType /* EthToTokenType */,
        bytes32[] calldata /* EthToTokenReserveIds */,
        uint256[] calldata /* EthToTokenSplits */
    ) external view returns (bytes memory hint)
    {
        return abi.encode(tokenSrc);
    }

    // IKyberHintHandler
    function getTradingReserves(
        address tokenSrc,
        address tokenDest,
        bool isTokenToToken,
        bytes calldata hint
    )
        external
        view
        returns (
            bytes32[] memory reserveIds,
            uint256[] memory splitValuesBps,
            ProcessWithRate processWithRate
        )
    {
        reserveIds = new bytes32[](1);
        reserveIds[0] = bytes32(uint256(1));
        splitValuesBps = new uint256[](0);
        processWithRate = ProcessWithRate.NotRequired;
    }

    // Deterministic `IKyberNetworkProxy.getExpectedRateAfterFee()`.
    function getExpectedRateAfterFee(
        address fromToken,
        address toToken,
        uint256 /* srcQty */,
        uint256 /* fee */,
        bytes calldata /* hint */
    )
        external
        view
        returns
        (uint256 expectedRate)
    {
        _revertIfShouldFail();
        fromToken = fromToken == ETH_ADDRESS ? _getWethAddress() : fromToken;
        toToken = toToken == ETH_ADDRESS ? _getWethAddress() : toToken;
        expectedRate = LibDeterministicQuotes.getDeterministicRate(
            SALT,
            fromToken,
            toToken
        );
    }

    // Deterministic `IKyberNetworkProxy.getExpectedRate()`.
    function getExpectedRate(
        address fromToken,
        address toToken,
        uint256
    )
        external
        view
        returns (uint256 expectedRate, uint256)
    {
        _revertIfShouldFail();
        fromToken = fromToken == ETH_ADDRESS ? _getWethAddress() : fromToken;
        toToken = toToken == ETH_ADDRESS ? _getWethAddress() : toToken;
        expectedRate = LibDeterministicQuotes.getDeterministicRate(
            SALT,
            fromToken,
            toToken
        );
    }
}


contract TestERC20BridgeSamplerUniswapExchangeFactory is
    IUniswapExchangeFactory
{
    mapping (address => IUniswapExchangeQuotes) private _exchangesByToken;

    // Creates Uniswap exchange contracts for tokens.
    function createTokenExchanges(address[] calldata tokenAddresses)
        external
    {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address tokenAddress = tokenAddresses[i];
            _exchangesByToken[tokenAddress] =
                new TestERC20BridgeSamplerUniswapExchange(tokenAddress);
        }
    }

    // `IUniswapExchangeFactory.getExchange()`.
    function getExchange(address tokenAddress)
        override
        external
        view
        returns (address)
    {
        return address(_exchangesByToken[tokenAddress]);
    }
}


contract TestERC20BridgeSampler is
    ERC20BridgeSampler,
    FailTrigger
{
    TestERC20BridgeSamplerUniswapExchangeFactory public uniswap;
    TestERC20BridgeSamplerUniswapV2Router01 public uniswapV2Router;
    TestERC20BridgeSamplerKyberNetwork public kyber;

    uint8 private constant MAX_ORDER_STATUS = uint8(IExchange.OrderStatus.CANCELLED) + 1;

    constructor() public ERC20BridgeSampler() {
        uniswap = new TestERC20BridgeSamplerUniswapExchangeFactory();
        uniswapV2Router = new TestERC20BridgeSamplerUniswapV2Router01();
        kyber = new TestERC20BridgeSamplerKyberNetwork();
    }

    // Creates Uniswap exchange contracts for tokens.
    function createTokenExchanges(address[] calldata tokenAddresses)
        external
    {
        uniswap.createTokenExchanges(tokenAddresses);
    }

    // Overridden to return deterministic states.
    function getLimitOrderFillableTakerAmount(
        IExchange.LimitOrder memory order,
        IExchange.Signature memory,
        IExchange
    )
        override
        public
        view
        returns (uint256 fillableTakerAmount)
    {
        return uint256(keccak256(abi.encode(order.salt))) % order.takerAmount;
    }

    // Overriden to return deterministic decimals.
    function _getTokenDecimals(address tokenAddress)
        override
        internal
        view
        returns (uint8 decimals)
    {
        return LibDeterministicQuotes.getDeterministicTokenDecimals(tokenAddress);
    }
}
