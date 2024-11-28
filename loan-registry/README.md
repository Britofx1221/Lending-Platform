# Debt Market Smart Contract

## About
A decentralized lending and borrowing protocol implemented in Clarity for the Stacks blockchain. This smart contract enables users to participate in a peer-to-peer lending marketplace with collateralized loans, automated liquidations, and flexible interest rates.

## Features
- Lending pool management
- Collateralized borrowing
- Interest rate mechanics
- Automated liquidations
- Built-in safety mechanisms
- Real-time state tracking

## Protocol Parameters

### Default Settings
- Minimum Collateral Ratio: 150% (15000 basis points)
- Base Interest Rate: 5% per year (500 basis points)
- Liquidation Threshold: 130% (13000 basis points)

### Safety Mechanisms
- Collateral requirements
- Minimum deposit amounts
- Liquidation triggers
- Access controls

## Core Functions

### Lending Operations
```clarity
(deposit-funds-to-lending-pool (deposit-amount-ustx uint))
(withdraw-funds-from-lending-pool (withdrawal-amount-ustx uint))
```

### Borrowing Operations
```clarity
(create-collateralized-loan-request (requested-principal-ustx uint) (offered-collateral-ustx uint))
(repay-outstanding-loan (protocol-loan-id uint) (repayment-amount-ustx uint))
```

### Liquidation Operations
```clarity
(initiate-undercollateralized-loan-liquidation (protocol-loan-id uint))
```

### Administrative Functions
```clarity
(update-protocol-collateral-requirement (new-minimum-collateral-ratio-bps uint))
(update-protocol-interest-rate (new-yearly-interest-rate-bps uint))
```

### Read-Only Functions
```clarity
(get-loan-details (protocol-loan-id uint))
(get-user-account-details (user-address principal))
(get-protocol-interest-rate)
(get-protocol-collateral-requirement)
```

## Error Codes

| Code | Description |
|------|-------------|
| u100 | Caller not authorized |
| u101 | Insufficient wallet balance |
| u102 | Collateral below minimum requirement |
| u103 | Requested loan not found |
| u104 | Invalid monetary amount |
| u105 | Loan not eligible for liquidation |

## Data Structures

### Protocol Loan Registry
```clarity
{
    protocol-loan-id: uint,
    borrower-address: principal,
    loan-principal-amount: uint,
    deposited-collateral-amount: uint,
    applied-interest-rate-bps: uint,
    loan-origination-block: uint,
    current-loan-state: (string-ascii 20)
}
```

### User Account State
```clarity
{
    current-lending-pool-balance: uint,
    current-borrowed-principal: uint,
    current-locked-collateral: uint
}
```

## Usage Examples

### Depositing Funds
```clarity
;; Deposit 1000 uSTX to the lending pool
(contract-call? .debt-market deposit-funds-to-lending-pool u1000)
```

### Creating a Loan
```clarity
;; Request 1000 uSTX loan with 1500 uSTX collateral
(contract-call? .debt-market create-collateralized-loan-request u1000 u1500)
```

### Repaying a Loan
```clarity
;; Repay loan #1 with 1050 uSTX (including interest)
(contract-call? .debt-market repay-outstanding-loan u1 u1050)
```

## Security Considerations

### Best Practices
- Always verify loan terms before borrowing
- Maintain sufficient collateral ratio
- Monitor liquidation thresholds
- Keep track of interest accrual

### Risks
- Market volatility affecting collateral value
- Interest rate fluctuations
- Liquidation events
- Smart contract risks

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request
4. Follow coding standards:
   - Use descriptive variable names
   - Add comprehensive comments
   - Include test cases