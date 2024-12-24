# HashPrime

The HashPrime protocol is a Scroll smart contract for supplying or borrowing assets. Through the hToken contracts, accounts on the blockchain supply capital (SEI or ERC-20 tokens) to receive hTokens or borrow assets from the protocol (holding other assets as collateral). The HashPrime hToken contracts track these balances and algorithmically set interest rates for borrowers.

# Contracts

We detail a few of the core contracts in the HashPrime protocol.

- **HToken, HErc20:** The HashPrime hTokens, which are self-contained borrowing and lending contracts. HToken contains the core logic and HErc20 add public interfaces for Erc20 tokens and ether, respectively. Each HToken is assigned an interest rate and risk model (see InterestRateModel and Comptroller sections), and allows accounts to _mint_ (supply capital), _redeem_ (withdraw capital), _borrow_ and _repay a borrow_. Each HToken is an ERC-20 compliant token where balances represent ownership of the market.

- **Unitroller:** A proxy contract that delegates calls to the Comptroller contract. This contract is used to upgrade the Comptroller contract and hold all state.

- **Comptroller:** The risk model contract, which validates permissible user actions and disallows actions if they do not fit certain risk parameters. For instance, the Comptroller enforces that each borrowing user must maintain a sufficient collateral balance across all hTokens.

- **InterestRateModel:** Contracts which define interest rate models. These models algorithmically determine interest rates based on the current utilization of a given market (that is, how much of the supplied assets are liquid versus borrowed).

- **JumpRateModel:**: Jump rate model contract that automatically adjusts the interest rate based on the utilization rate.

- **CompositeOracle:**: A composite oracle contract that allows the system to fetch the price of assets on the network. Maps the underlying token symbol to a chainlink feed address for easy lookups of price.

- **Rate:** The HashPrime token (TKL).

- **MultiRewardDistributor:** Reward distributor contract that allows the system to distribute rewards for supplying and borrowing in multiple reward tokens per HToken. This contract is used by the Comptroller contract. This contract's admin is the Comptroller's admin.

- **TERC20Delegator:**: A proxy contract that delegates calls to the TERC20Delegate contract. This contract is used to upgrade the TERC20Delegate contract and holds all states.

- **TERC20Delegate:** A logic contract that handles the business logic of the TERC20Delegator contract. This contract inherits the HToken contract and provides all the functionality of the HToken contract.

- **Careful Math:** Based on OpenZeppelin's SafeMath, the CarefulMath Library returns errors instead of reverting.

- **ErrorReporter:** Library for tracking error codes and failure conditions.

- **Exponential:** Library for handling fixed-point decimal numbers.

# Deployment

## Build

Built with [Foundry](https://book.getfoundry.sh/).

```shell
$ forge build
```

## Deploy

```shell
$ forge script scripts/<your_script> --rpc-url <your_rpc_url> --private-key <your_private_key>
```
