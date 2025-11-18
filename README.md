# 🔄 Rollup Transaction Simulator

> 🎯 **Educational smart contract demonstrating rollup technology through transaction batching and settlement**

## 📋 Overview

The Rollup Transaction Simulator is a Clarity smart contract that teaches rollup concepts by aggregating multiple transfers into single settlement operations. This MVP demonstrates how rollup technology works by batching transactions for efficient processing.

## ✨ Features

- 💰 **User Balance Management** - Deposit and withdraw STX tokens
- 📝 **Transaction Queuing** - Queue multiple transfers before execution  
- 📦 **Batch Creation** - Aggregate transactions into batches
- ⚡ **Settlement Processing** - Execute batched transactions efficiently
- 🔍 **Transaction History** - Track all settlements and batch operations
- 👤 **Operator Controls** - Administrative functions for batch management

## 🚀 Quick Start

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity smart contracts

### Installation

1. Clone this repository
```bash
git clone <repository-url>
cd Rollup-Transaction-Simulator
```

2. Initialize the contract
```bash
clarinet console
```

3. Deploy and initialize
```clarity
(contract-call? .rollup-transaction-simulator initialize)
```

## 📖 Usage Guide

### 🏦 Managing Balances

**Deposit STX tokens:**
```clarity
(contract-call? .rollup-transaction-simulator deposit u1000)
```

**Check balance:**
```clarity
(contract-call? .rollup-transaction-simulator get-user-balance 'ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE)
```

**Withdraw tokens:**
```clarity
(contract-call? .rollup-transaction-simulator withdraw u500)
```

### 📝 Queueing Transfers

**Add transfer to queue:**
```clarity
(contract-call? .rollup-transaction-simulator queue-transfer 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG u100)
```

**View pending transfers:**
```clarity
(contract-call? .rollup-transaction-simulator get-pending-transfers 'ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE)
```

### 📦 Batch Operations (Operator Only)

**Create new batch:**
```clarity
(contract-call? .rollup-transaction-simulator create-batch)
```

**Add transaction to batch:**
```clarity
(contract-call? .rollup-transaction-simulator add-to-batch 
  u1 
  'ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE 
  'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG 
  u100)
```

**Settle batch:**
```clarity
(contract-call? .rollup-transaction-simulator settle-batch u1)
```

**Execute pending transfers:**
```clarity
(contract-call? .rollup-transaction-simulator execute-pending-transfers 'ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE)
```

### 🔍 Querying Information

**Get batch information:**
```clarity
(contract-call? .rollup-transaction-simulator get-batch-info u1)
```

**View settlement history:**
```clarity
(contract-call? .rollup-transaction-simulator get-settlement-history u1)
```

**Get contract statistics:**
```clarity
(contract-call? .rollup-transaction-simulator get-contract-stats)
```

## 🏗️ Contract Architecture

### Core Components

1. **👤 User Management**
   - Balance tracking with `user-balances` map
   - Deposit/withdrawal functionality

2. **📋 Transaction Queue**  
   - `pending-transactions` map stores queued transfers
   - Up to 10 pending transactions per user

3. **📦 Batch Processing**
   - `batch-transactions` map manages batches
   - Maximum 50 transactions per batch
   - Minimum 10 block settlement delay

4. **⚖️ Settlement Engine**
   - Atomic batch processing
   - Settlement history tracking
   - Event logging for transparency

### Key Functions

| Function | Purpose | Access |
|----------|---------|--------|
| `deposit` | Add STX to user balance | Public |
| `withdraw` | Remove STX from balance | Public |
| `queue-transfer` | Add transfer to queue | Public |
| `create-batch` | Create new batch | Operator |
| `settle-batch` | Execute batch settlement | Operator |
| `get-user-balance` | Check user balance | Read-only |

## ⚙️ Configuration

- **Max Batch Size:** 50 transactions
- **Min Settlement Delay:** 10 blocks  
- **Max Pending Transfers:** 10 per user
- **Settlement Fee:** Configurable by owner

## 🔒 Security Features

- ✅ Owner-only administrative functions
- ✅ Balance validation before transfers
- ✅ Batch size limits
- ✅ Settlement delay requirements
- ✅ Input validation for all parameters

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

Example test scenarios:
- Deposit and withdrawal flows
- Transaction queuing and batch processing
- Settlement validation
- Access control verification

## 🎓 Educational Value

This contract demonstrates:
- **Rollup Concepts:** Transaction aggregation and batch settlement
- **State Management:** Complex data structure handling in Clarity
- **Access Control:** Multi-role permission system
- **Event Logging:** Transparent operation tracking
- **Error Handling:** Comprehensive error management

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

Built with ❤️ using Clarinet and the Stacks blockchain ecosystem.

---

**⚠️ Disclaimer:** This is an educational project. Use at your own risk in production environments.
