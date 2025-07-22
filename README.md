## binaryV3

Helps calculate the sale values required for arbitrary tokens, sale amounts, and starting market caps

## Usage

Ensure the state and token variables at the top of script/calc.py are correct and then run

```shell
$ forge script script/TickSearcher.s.sol --ffi
```

The script will output (for example)

```
  startingTick 197400
  endingTick 204400
  mid 546109336523993953
```

These values can be provided to the Doppler-SDK in the `v3PoolConfig`

```
  "v3PoolConfig": {
    "startTick": 197400,
    "endTick": 204400,
    "numPositions": 15,
    "maxShareToBeSold": "546109336523993953",
    "fee": 10000
  }
```
