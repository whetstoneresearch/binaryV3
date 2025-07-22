from eth_abi import encode
import math
import sys
import numpy as np


###### State Variables ######
startingTgtMarketCapUSD = 5_000
endingTgtMarketCapUSD = 10_000

fee = 10_000 # important for binning the ticks
tokenSupply = 1_000_000_000
numeraireUSD = 3723

## -1 = downward, 0 = true, 1 = upward
roundingDirection = -1

feeToTS = {10_000: 200}

# helpers
def mcToRatio(mcUSD, supply, numeraire):
    tokenPrice = mcUSD / supply

    # this makes assumption that token is t1
    # we will flip this in the future if not true
    return (numeraire / tokenPrice) 

def ratioToTick(ratio):
    return np.log(ratio) / np.log(1.0001)

def getTSFromFee(fee):
    ts = feeToTS.get(fee, None)

    assert ts != None, "fee missing from mapping"

    return ts

startingTick = ratioToTick(mcToRatio(startingTgtMarketCapUSD, tokenSupply, numeraireUSD))
endingTick = ratioToTick(mcToRatio(endingTgtMarketCapUSD, tokenSupply, numeraireUSD))

ts = getTSFromFee(fee)

# intentional lossy math and type conversion back to standard int
startingTick = int(((startingTick // ts) + (roundingDirection * -1)) * ts)
endingTick = int(((endingTick // ts) + (roundingDirection * -1)) * ts)

realizedStartingMarketCap = (numeraireUSD / 1.0001 ** (startingTick)) * tokenSupply
realizedEndingMarketCap = (numeraireUSD / 1.0001 ** (endingTick)) * tokenSupply

var = sys.stdout
data = [startingTick, endingTick]
out = encode(['int256[2]'], [data])
var.write(out.hex())
