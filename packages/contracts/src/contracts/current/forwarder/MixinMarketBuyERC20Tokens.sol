pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./MixinForwarderCore.sol";
import "./MixinForwarderExpectedResults.sol";
import "./MixinERC20.sol";

contract MixinMarketBuyERC20Tokens is
    MixinForwarderCore,
    MixinForwarderExpectedResults,
    MixinERC20
{
    /// @dev Market buys ERC20 tokens, performing fee abstraction if required. This does not support ERC721 tokens. This function is payable
    ///      and will convert all incoming ETH into WETH and perform the trade on behalf of the caller.
    ///      This function allows for a deduction of a proportion of incoming ETH sent to the feeRecipient.
    ///      The caller is sent all tokens from the operation.
    ///      If the purchased token amount does not meet an acceptable threshold then this function reverts.
    /// @param orders An array of Order struct containing order specifications.
    /// @param signatures An array of Proof that order has been created by maker.
    /// @param feeOrders An array of Order struct containing order specifications for fees.
    /// @param feeSignatures An array of Proof that order has been created by maker for the fee orders.
    /// @param feeProportion A proportion deducted off the incoming ETH and sent to feeRecipient. The maximum value for this
    ///        is 1000, aka 10%. Supports up to 2 decimal places. I.e 0.59% is 59.
    /// @param feeRecipient An address of the fee recipient whom receives feeProportion of ETH.
    /// @return FillResults amounts filled and fees paid by maker and taker.
    function marketBuyTokens(
        Order[] memory orders,
        bytes[] memory signatures,
        Order[] memory feeOrders,
        bytes[] memory feeSignatures,
        uint16  feeProportion,
        address feeRecipient
    )
        payable
        public
        returns (Exchange.FillResults memory totalFillResults)
    {
        require(
            msg.value > 0,
            VALUE_GREATER_THAN_ZERO
        );
        // Deduct the fee from the total amount of ETH sent in
        uint256 remainingTakerTokenAmount = payAndDeductFee(msg.value, feeProportion, feeRecipient);
        // Deposit the remaining to be used for trading
        ETHER_TOKEN.deposit.value(remainingTakerTokenAmount)();
        // Populate the known assetData, as it is always WETH the caller can provide null bytes to save gas
        // marketSellOrders fills the remaining
        address makerTokenAddress = readAddress(orders[0].makerAssetData, 0);
        orders[0].takerAssetData = WETH_ASSET_DATA;
        if (makerTokenAddress == address(ZRX_TOKEN)) {
            // If this is ZRX then we market sell from the orders, rather than a 2 step of buying ZRX fees from feeOrders
            // then buying ZRX from orders
            totalFillResults = marketSellTokensForZRXInternal(orders, signatures, remainingTakerTokenAmount);
        } else {
            totalFillResults = marketSellTokensForERC20Internal(orders, signatures, feeOrders, feeSignatures, remainingTakerTokenAmount);
        }
        // Ensure no WETH is left in this contract
        require(
            remainingTakerTokenAmount == totalFillResults.takerAssetFilledAmount,
            UNACCEPTABLE_THRESHOLD
        );
        // Transfer all tokens to msg.sender
        transferToken(makerTokenAddress, msg.sender, totalFillResults.makerAssetFilledAmount);
        return totalFillResults;
    }

    /// @dev Market sells WETH for ERC20 tokens.
    /// @param orders An array of Order struct containing order specifications.
    /// @param signatures An array of Proof that order has been created by maker.
    /// @param feeOrders An array of Order struct containing order specifications for fees.
    /// @param feeSignatures An array of Proof that order has been created by maker for the fee orders.
    /// @param sellTokenAmount The amount of WETH to sell.
    /// @return FillResults amounts filled and fees paid by maker and taker.
    function marketSellTokensForERC20Internal(
        Order[] memory orders,
        bytes[] memory signatures,
        Order[] memory feeOrders,
        bytes[] memory feeSignatures,
        uint256 sellTokenAmount
    )
        internal
        returns (Exchange.FillResults memory totalFillResults)
    {
        uint256 takerTokenBalance = sellTokenAmount;
        Exchange.FillResults memory calculatedMarketSellResults = calculateMarketSellFillResults(orders, sellTokenAmount);
        if (calculatedMarketSellResults.takerFeePaid > 0) {
            // Fees are required for these orders. Buy enough ZRX to cover the future market buy
            Exchange.FillResults memory feeTokensResults = buyFeeTokensInternal(
                feeOrders,
                feeSignatures,
                calculatedMarketSellResults.takerFeePaid
            );
            // Ensure the token abstraction was fair if fees were proportionally too high, we fail
            require(
                isAcceptableThreshold(sellTokenAmount, safeSub(sellTokenAmount, feeTokensResults.takerAssetFilledAmount)),
                UNACCEPTABLE_THRESHOLD
            );
            takerTokenBalance = safeSub(takerTokenBalance, feeTokensResults.takerAssetFilledAmount);
            totalFillResults.takerFeePaid = feeTokensResults.takerFeePaid;
            totalFillResults.takerAssetFilledAmount = feeTokensResults.takerAssetFilledAmount;
        }
        // Make our market sell to buy the requested tokens with the remaining balance
        Exchange.FillResults memory requestedTokensResults = EXCHANGE.marketSellOrders(orders, takerTokenBalance, signatures);
        // Update our return FillResult with the market sell
        addFillResults(totalFillResults, requestedTokensResults);
        return totalFillResults;
    }

    /// @dev Market sells WETH for ZRX tokens.
    /// @param orders An array of Order struct containing order specifications.
    /// @param signatures An array of Proof that order has been created by maker.
    /// @param sellTokenAmount The amount of WETH to sell.
    /// @return FillResults amounts filled and fees paid by maker and taker.
    function marketSellTokensForZRXInternal(
        Order[] memory orders,
        bytes[] memory signatures,
        uint256 sellTokenAmount
    )
        internal
        returns (Exchange.FillResults memory totalFillResults)
    {
        // Make our market sell to buy the requested tokens with the remaining balance
        totalFillResults = EXCHANGE.marketSellOrders(orders, sellTokenAmount, signatures);
        // Exchange does not special case ZRX in the makerAssetFilledAmount, if fees were deducted then using this amount
        // for future transfers is invalid.
        uint256 totalZRXAmount = safeSub(totalFillResults.makerAssetFilledAmount, totalFillResults.takerFeePaid);
        require(
            isAcceptableThreshold(totalFillResults.makerAssetFilledAmount, totalZRXAmount),
            UNACCEPTABLE_THRESHOLD
        );
        totalFillResults.makerAssetFilledAmount = totalZRXAmount;
        return totalFillResults;
    }

}
