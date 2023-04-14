# Early Adopter Pool Contract Refactored

Refactored the source code of EarlyAdopterPool deployed [at](https://etherscan.io/address/0x7623e9dc0da6ff821ddb9ebaba794054e078f8c4?method=Deposit~0x47e7ef24#code), to achieve some substantial gas savings across major functions.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
npx hardhat test
npx hardhat node
HARDHAT_NETWORK=test npx hardhat run scripts/deploy.js
```

### Test Output

![Test reult along with gas costs](https://github.com/Akkii4/etherfi_refactored/blob/main/test_result.png)

### Test Coverage

![Coverage of test on each contract](https://github.com/Akkii4/etherfi_refactored/blob/main/test_coverage.png)
