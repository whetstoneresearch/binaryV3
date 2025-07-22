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
import {TickSearcher} from "../src/TickSearcher.sol";

contract TickSearcherTest is Test {
    TickSearcher searcher;

    function setUp() public {
        //forkId = vm.createSelectFork("https://base-mainnet.g.alchemy.com/v2/Ed8RgGP0O64bixqiVhSt1GONANrO7hjP", 21179722);
        searcher = new TickSearcher();
    }


    function test_run2() public {
        // create the string array to putting into ffi
        string[] memory runPyInputs = new string[](6);

        runPyInputs[0] = "uv";
        runPyInputs[1] = "run";
        runPyInputs[2] = "--with-requirements";
        runPyInputs[3] = "requirements.txt";
        runPyInputs[4] = "python3";
        runPyInputs[5] = "script/calc.py";

        bytes memory pythonResult = vm.ffi(runPyInputs);

        int256[2] memory pyOut;
        pyOut = abi.decode(pythonResult, (int256[2]));
        
        int24 tickLower = int24(pyOut[0]);
        int24 tickUpper = int24(pyOut[1]);

        // sort
        (tickLower, tickUpper) = tickLower < tickUpper ? (tickLower, tickUpper) : (tickUpper, tickLower);

        require(tickLower != tickUpper, "startingTick == endingTick");
        
        uint16 numPositions = 15;
        uint256 marketSupply = 9e26;
        (uint256 mid,,)  = searcher.searchParameters(tickLower, tickUpper, numPositions, false, marketSupply);

        console.log("startingTick", tickLower);
        console.log("endingTick", tickUpper);
        console.log("mid", mid);        
    }    
    // function test_run() public {
    //     (uint24 fee, int24 tickLower, int24 tickUpper, uint16 numPositions) = (10000, 172400, 225000, 15);

    //     uint256 supply = 9e26;

    //     (uint256 mid, uint256 delta0, uint256 delta1) = searcher.searchParameters(tickLower, tickUpper, numPositions, false, supply);
    //     console.log("mid", mid);
    //     console.log("tickLower", tickLower);
    //     console.log("tickUpper", tickUpper);
    // }
}
