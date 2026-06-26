# Meme Launchpad Rebuild

This folder is a learning rebuild of the parent Solidity project. The original
contracts stay untouched.

## Roadmap

1. Token + CREATE2 factory
2. Core initialization, roles, and dependency wiring
3. Signed token creation request
4. Bonding curve buy/sell flow
5. Initial buy and vesting
6. Graduation and DEX liquidity flow
7. Admin controls, pause, blacklist, and fee updates

## Checkpoints

### Step 1: Token + CREATE2 Factory

- `LearningMEMEToken`: ERC20 token minted to the core address with transfer modes.
- `LearningMEMEFactory`: CREATE2 factory with predictable token addresses.
- `Step01FactoryAndToken.t.sol`: tests for deployment, address prediction, roles,
  and transfer restrictions.

### Step 2: Core Wiring + Roles

- `LearningMEMECore`: initializer-style setup for factory/helper/vesting-facing
  dependencies, role assignment, chain ID, and default fee parameters.
- `deployTokenForLearning`: a temporary learning function that proves the runtime
  call path is `admin -> core -> factory -> token`.
- `Step02CoreWiring.t.sol`: tests for one-time initialization, roles, defaults,
  factory permissions, and admin-only dependency updates.

### Step 3: Signed Token Creation

- `CreateTokenParams`: the ABI-encoded request that a trusted backend signer
  authorizes and any user can submit.
- `createToken`: verifies the signature, request expiry, replay ID, creation fee,
  and basic token parameters before deploying through the factory.
- The signed digest includes `data`, `chainId`, and the core address, so the same
  signature cannot be reused for a different request, chain, or core contract.
- `Step03SignedTokenCreation.t.sol`: tests successful creation and registration,
  fee forwarding/refunds, invalid signatures, expiration, and replay protection.

Run it with:

```bash
forge test --root meme-launchpad-rebuild
```
