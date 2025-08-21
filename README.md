# ⚡ Outlog - On-Chain Power Outage Reports

A decentralized smart contract system for verified incident logging and automated compensation for power outages built on Stacks blockchain.

## 🎯 Overview

Outlog enables utility companies to transparently report power outages while providing automated compensation to affected users through community verification. The system ensures accountability and fair compensation distribution through blockchain transparency.

## ✨ Features

- 🏢 **Utility Authorization**: Only authorized utility companies can report outages
- 📊 **Incident Reporting**: Detailed outage logging with severity levels and affected areas  
- 🔍 **Community Verification**: Users can verify outages to trigger compensation
- 💰 **Automated Compensation**: Calculate and distribute compensation based on outage duration and severity
- 🛡️ **Fraud Prevention**: Multiple verification requirements and utility deposits
- 📈 **Transparent Analytics**: Real-time outage statistics and compensation tracking

## 🚀 Quick Start

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Installation

```bash
git clone <repository-url>
cd On-Chain-Power-Outage-Reports
clarinet check
```

## 💼 Usage

### For Contract Owner

**Authorize Utility Companies:**
```clarity
(contract-call? .outlog authorize-utility 'SP1UTILITY-ADDRESS "PowerCorp Inc")
```

**Update Compensation Settings:**
```clarity
(contract-call? .outlog update-compensation-rate u2000000)
(contract-call? .outlog update-verification-threshold u5)
```

### For Utility Companies

**Deposit Compensation Fund:**
```clarity
(contract-call? .outlog deposit-compensation u10000000)
```

**Report Power Outage:**
```clarity
(contract-call? .outlog report-outage "Downtown District" u3 "Transformer failure affecting 500 homes" u500)
```

**Resolve Outage:**
```clarity
(contract-call? .outlog resolve-outage u1)
```

### For Community Members

**Verify Outage:**
```clarity
(contract-call? .outlog verify-outage u1)
```

**Claim Compensation:**
```clarity
(contract-call? .outlog claim-compensation u1)
```

## 📋 Contract Functions

### Public Functions

| Function | Description | Access |
|----------|-------------|---------|
| `authorize-utility` | Add authorized utility company | Owner only |
| `revoke-utility` | Remove utility authorization | Owner only |
| `deposit-compensation` | Add funds to compensation pool | Utilities |
| `report-outage` | Report new power outage | Utilities |
| `resolve-outage` | Mark outage as resolved | Reporter |
| `verify-outage` | Verify reported outage | Community |
| `claim-compensation` | Claim compensation for outage | Community |
| `update-compensation-rate` | Adjust base compensation rate | Owner only |
| `update-verification-threshold` | Set required verifications | Owner only |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-outage-details` | Get complete outage information |
| `get-user-verification` | Check user's verification status |
| `get-user-claim` | Get user's compensation claim |
| `is-utility-authorized` | Check utility authorization |
| `get-total-compensation-pool` | Get available compensation funds |
| `calculate-compensation` | Calculate compensation amount |
| `get-outage-duration` | Get outage duration in blocks |
| `is-outage-verified` | Check if outage meets verification threshold |

## 🔧 Configuration

### Severity Levels
- **1**: Minor (localized issues)
- **2**: Moderate (neighborhood outages) 
- **3**: Significant (district-wide)
- **4**: Major (city-wide)
- **5**: Critical (regional emergency)

### Compensation Calculation
```
compensation = base-rate × severity × duration-blocks × min(affected-users, 1000)
```

### Default Settings
- Base compensation rate: `1,000,000` microSTX
- Verification threshold: `3` verifications
- Maximum affected users multiplier: `1,000`

## 🛠️ Development

### Testing
```bash
clarinet test
```

### Console Session
```bash
clarinet console
```

### Deploy
```bash
clarinet deploy --testnet
```

## 📊 Example Scenario

1. **PowerCorp** reports downtown outage affecting 500 users (severity 3)
2. **3 community members** verify the outage 
3. **PowerCorp** resolves outage after 100 blocks
4. **Affected users** claim compensation: `1,000,000 × 3 × 100 × 500 = 150,000,000` microSTX each

## 🔒 Security Features

- **Authorization checks** for all critical functions
- **Duplicate prevention** for verifications and claims  
- **Fund validation** before compensation distribution
- **Status validation** preventing double-claims
- **Utility deposits** ensuring compensation availability

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)  
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For support and questions:
- Open an issue on GitHub
- Contact the development team
- Check documentation for common issues

---

*Built with ❤️ for transparent utility accountability*
