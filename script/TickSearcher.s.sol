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
import {Script, console, console2} from "forge-std/Script.sol";
import {TickSearcher} from "../src/TickSearcher.sol";

contract TickSearcherTest is Script {

    function run() public {
        TickSearcher searcher = new TickSearcher();

        string[] memory runPyInputs = new string[](6);

        runPyInputs[0] = "uv";
        runPyInputs[1] = "run";
        runPyInputs[2] = "--with-requirements";
        runPyInputs[3] = "requirements.txt";
        runPyInputs[4] = "python3";
        runPyInputs[5] = "script/calc.py";

        bytes memory pythonResult = vm.ffi(runPyInputs);

        int256[3] memory pyOut;
        pyOut = abi.decode(pythonResult, (int256[3]));
        
        int24 tickLower = int24(pyOut[0]);
        int24 tickUpper = int24(pyOut[1]);
        uint256 marketSupply = uint256(pyOut[2]);

        // sort
        (tickLower, tickUpper) = tickLower < tickUpper ? (tickLower, tickUpper) : (tickUpper, tickLower);

        require(tickLower != tickUpper, "startingTick == endingTick");
        
        uint16 numPositions = 15;
        (uint256 mid,,)  = searcher.searchParameters(tickLower, tickUpper, numPositions, false, marketSupply);

        console.log("startingTick", tickLower);
        console.log("endingTick", tickUpper);
        console.log("mid", mid);   
    }

} 