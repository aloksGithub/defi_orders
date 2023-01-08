# defi_orders

A service to bring finance orders such as stop loss and take profit to defi protocols

# Setup

1. Create a .env file using .env.example as a template
2. Run `yarn` or `npm install`
3. run `npx hardhat compile`

# Deploying

1. Run `yarn deploy --network <NETWORK>`
2. Run `yarn verify --network <NETWORK> --api-key <API_KEY>`
2. If deploying locally, you can create a bunch of test positions by running `npx hardhat run --network localhost scripts/createPositions.ts`

# Testing

1. Change the variable CURRENTLY_FORKING in the .env file to whichever network's fork you would like to run tests on
2. Run `yarn test`
