// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IUniswapV3Factory} from "@v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@v3-core/interfaces/callback/IUniswapV3MintCallback.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@v4-core-test/utils/LiquidityAmounts.sol";
import {SqrtPriceMath} from "@v4-core/libraries/SqrtPriceMath.sol";
import {FullMath} from "@v4-core/libraries/FullMath.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Test, console, console2} from "forge-std/Test.sol";

contract TickSearcher is Test {
    /// @dev Constant used to increase precision during calculations
    uint256 constant WAD = 1e18;

    /// @dev Maximum number of searchers to run in the bisection search
    uint256 constant numMaxSearchers = 100;

    struct LpPosition {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint16 id;
    }

    struct CallbackData {
        address asset;
        address numeraire;
        uint24 fee;
    }

    function searchParameters(int24 tickLower, int24 tickUpper, uint16 numPositions, bool isToken0, uint256 supply)
        public
        pure
        returns (uint256, uint256, uint256)
    {
        uint256 top = WAD;
        uint256 bottom = 0;
        int24 tickSpacing = 200;

        uint256 mid;
        uint256 delta0;
        uint256 delta1;
        for (uint256 i; i < numMaxSearchers; i++) {
            mid = (top + bottom) / 2;

            uint256 numTokensToSell = FullMath.mulDiv(supply, mid, WAD);

            // reserves are the other side that has been bootstrapped
            (, uint256 reserves) = calculateLogNormalDistribution(
                tickLower, tickUpper, tickSpacing, isToken0, numPositions, numTokensToSell
            );

            (delta0, delta1) = calculateLpTail(tickLower, tickUpper, isToken0, reserves, supply - numTokensToSell);

            // execute the bisection search sorting
            {
                uint256 delta0Tolerance;
                uint256 delta1Tolerance;
                if (isToken0) {
                    delta0Tolerance = 1e8;
                    delta1Tolerance = 1e4;
                } else {
                    delta0Tolerance = 1e4;
                    delta1Tolerance = 1e8;
                }

                if (delta0 > delta0Tolerance) {
                    (bottom, top) = (bottom, mid);
                } else if (delta1 > delta1Tolerance) {
                    (bottom, top) = (mid, top);
                } else {
                    break;
                }
            }
        }

        return (mid, delta0, delta1);
    }

    function alignTickToTickSpacing(bool isToken0, int24 tick, int24 tickSpacing) internal pure returns (int24) {
        if (isToken0) {
            // Round down if isToken0
            if (tick < 0) {
                // If the tick is negative, we round up (negatively) the negative result to round down
                return (tick - tickSpacing + 1) / tickSpacing * tickSpacing;
            } else {
                // Else if positive, we simply round down
                return tick / tickSpacing * tickSpacing;
            }
        } else {
            // Round up if isToken1
            if (tick < 0) {
                // If the tick is negative, we round down the negative result to round up
                return tick / tickSpacing * tickSpacing;
            } else {
                // Else if positive, we simply round up
                return (tick + tickSpacing - 1) / tickSpacing * tickSpacing;
            }
        }
    }

    /// @notice Calculates the final LP position that extends from the far tick to the pool's min/max tick
    /// @dev This position ensures price equivalence between Uniswap v2 and v3 pools beyond the LBP range
    function calculateLpTail(
        int24 tickLower,
        int24 tickUpper,
        bool isToken0,
        uint256 reserves,
        uint256 bondingAssetsRemaining
    ) internal pure returns (uint256 delta0, uint256 delta1) {
        int24 tailTick = isToken0 ? tickUpper : tickLower;

        uint160 sqrtPriceAtTail = TickMath.getSqrtPriceAtTick(tailTick);

        uint128 lpTailLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceAtTail,
            TickMath.MIN_SQRT_PRICE,
            TickMath.MAX_SQRT_PRICE,
            isToken0 ? bondingAssetsRemaining : reserves,
            isToken0 ? reserves : bondingAssetsRemaining
        );

        uint256 amount1In =
            LiquidityAmounts.getAmount1ForLiquidity(TickMath.MIN_SQRT_PRICE, sqrtPriceAtTail, lpTailLiquidity);
        uint256 amount0In =
            LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceAtTail, TickMath.MAX_SQRT_PRICE, lpTailLiquidity);

        delta0 = isToken0 ? bondingAssetsRemaining - amount0In : reserves - amount0In;
        delta1 = isToken0 ? reserves - amount1In : bondingAssetsRemaining - amount1In;
    }

    /// @notice Calculates the distribution of liquidity positions across tick ranges
    /// @dev For example, with 1000 tokens and 10 bins starting at tick 0:
    ///      - Creates positions: [0,10], [1,10], [2,10], ..., [9,10]
    ///      - Each position gets an equal share of tokens (100 tokens each)
    ///      This creates a linear distribution of liquidity across the tick range
    function calculateLogNormalDistribution(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        bool isToken0,
        uint16 totalPositions,
        uint256 totalAmtToBeSold
    ) internal pure returns (LpPosition[] memory, uint256) {
        int24 farTick = isToken0 ? tickUpper : tickLower;
        int24 closeTick = isToken0 ? tickLower : tickUpper;

        int24 spread = tickUpper - tickLower;

        uint160 farSqrtPriceX96 = TickMath.getSqrtPriceAtTick(farTick);
        uint256 amountPerPosition = FullMath.mulDiv(totalAmtToBeSold, WAD, totalPositions * WAD);
        uint256 totalAssetsSold;
        LpPosition[] memory newPositions = new LpPosition[](totalPositions + 1);
        uint256 reserves;

        for (uint256 i; i < totalPositions; i++) {
            // calculate the ticks position * 1/n to optimize the division
            int24 startingTick = isToken0
                ? closeTick + int24(uint24(FullMath.mulDiv(i, uint256(uint24(spread)), totalPositions)))
                : closeTick - int24(uint24(FullMath.mulDiv(i, uint256(uint24(spread)), totalPositions)));

            // round the tick to the nearest bin
            startingTick = alignTickToTickSpacing(isToken0, startingTick, tickSpacing);

            if (startingTick != farTick) {
                uint160 startingSqrtPriceX96 = TickMath.getSqrtPriceAtTick(startingTick);

                // if totalAmtToBeSold is 0, we skip the liquidity calculation as we are burning max liquidity
                // in each position
                uint128 liquidity;
                if (totalAmtToBeSold != 0) {
                    liquidity = isToken0
                        ? LiquidityAmounts.getLiquidityForAmount0(startingSqrtPriceX96, farSqrtPriceX96, amountPerPosition)
                        : LiquidityAmounts.getLiquidityForAmount1(farSqrtPriceX96, startingSqrtPriceX96, amountPerPosition);

                    totalAssetsSold += (
                        isToken0
                            ? SqrtPriceMath.getAmount0Delta(startingSqrtPriceX96, farSqrtPriceX96, liquidity, true)
                            : SqrtPriceMath.getAmount1Delta(farSqrtPriceX96, startingSqrtPriceX96, liquidity, true)
                    );

                    // note: we keep track how the theoretical reserves amount at that time to then calculate the breakeven liquidity amount
                    // once we get to the end of the loop, we will know exactly how many of the reserve assets have been raised, and we can
                    // calculate the total amount of reserves after the endTick which makes swappers and LPs indifferent between Uniswap v2 (CPMM) and Uniswap v3 (CLAMM)
                    // we can then bond the tokens to the Uniswap v2 pool by moving them over to the Uniswap v3 pool whenever possible, but there is no rush as it goes up
                    reserves += (
                        isToken0
                            ? SqrtPriceMath.getAmount1Delta(
                                farSqrtPriceX96,
                                startingSqrtPriceX96,
                                liquidity,
                                false // round against the reserves to undercount eventual liquidity
                            )
                            : SqrtPriceMath.getAmount0Delta(
                                startingSqrtPriceX96,
                                farSqrtPriceX96,
                                liquidity,
                                false // round against the reserves to undercount eventual liquidity
                            )
                    );
                }

                newPositions[i] = LpPosition({
                    tickLower: farSqrtPriceX96 < startingSqrtPriceX96 ? farTick : startingTick,
                    tickUpper: farSqrtPriceX96 < startingSqrtPriceX96 ? startingTick : farTick,
                    liquidity: liquidity,
                    id: uint16(i)
                });
            }
        }

        return (newPositions, reserves);
    }

    function mintPositions(
        address asset,
        address numeraire,
        uint24 fee,
        address pool,
        LpPosition[] memory newPositions,
        uint16 numPositions
    ) internal {
        for (uint256 i; i <= numPositions; i++) {
            IUniswapV3Pool(pool).mint(
                address(this),
                newPositions[i].tickLower,
                newPositions[i].tickUpper,
                newPositions[i].liquidity,
                abi.encode(CallbackData({asset: asset, numeraire: numeraire, fee: fee}))
            );
        }
    }
}
