# LenderPool V3

![solidity](https://img.shields.io/badge/Solidity-e6e6e6?style=for-the-badge&logo=solidity&logoColor=black) ![openzeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?logo=OpenZeppelin&logoColor=fff&style=for-the-badge)

This repository contains the smart contracts for LenderPool V3, see [documentation](https://polytrade.gitbook.io/lender-v3/) for details.

Lender Pool Version 3 represents a revamped version of the current LenderPool V2 architecture that streamlines and automates the pool dynamics, providing lenders with greater control and flexibility. The cornerstone of LPV3 is the Lender Pool factory, which generates pool instances that meet various needs and specifications.

## 📝 Contracts

```bash
Contracts
├─ BondingCurve
│  ├─ Interface
│  │  └─ IBondingCurve.sol
│  └─ BondingCurve.sol
├─ Lender
│  ├─ Interface
│  │  ├─ IFixLender.sol
│  │  └─ IFlexLender.sol
│  ├─ FixLender.sol
│  └─ FlexLender.sol
├─ Strategy
│  ├─ Interface
│  │  ├─ IAaveLendingPool.sol
│  │  └─ IStrategy.sol
│  └─ Strategy.sol
├─ Token
│  ├─ Interface
│  │  └─ IToken.sol
│  └─ Token.sol
└─ Verification
   ├─ Interface
   │  ├─ IPolytradeProxy.sol
   │  └─ IVerification.sol
   ├─ Mock
   │  └─ PolytradeProxy.sol
   └─ Verification.sol
```

## 🛠️ Install Dependencies

```bash
npm install
npx hardhat compile
npx hardhat test
```

## ⚖️ License

All files in `/contracts` are licensed under MIT as indicated in their SPDX header.
