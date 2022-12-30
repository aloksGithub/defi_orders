# defi_orders

A service to bring finance orders such as stop loss and take profit to defi protocols

# Setup

1. Create a .env file using .env.example as a template
2. Run `yarn` or `npm install`
3. run `npx hardhat compile`

# Deploying

In order to deploy to a public network:

1. Change the variable ENVIRONMENT in the .env file to 'prod'
2. Run `npx hardhat run --network <NETWORK> scripts/deploy.ts`
3. The addresses of the deployed contracts as well as the hashes of the deployment transactions should show up in deployments/NETWORK where NETWORK is the chain you deployed to

In order to deploy locally:

1. Change the variable ENVIRONMENT in the .env file to 'dev'. You can leave it as prod, but the deployment script will take considerably longer as it tries to initialize every pool of every masterchefs rather than the first few
2. Change the varieble CURRENTLY_FORKING in the .env file to whichever network you would like to fork
3. Run `npx hardhat node`
4. `npx hardhat run --network localhost scripts/deploy.ts`
5. The addresses of the deployed contracts as well as the hashes of the deployment transactions should show up in deployments/localhost
6. Run `npx hardhat run --network localhost scripts/createPositions.ts` to create a bunch of positions for testing.

# Testing

1. Change the variable ENVIRONMENT in the .env file to 'dev'. You can leave it as prod, but the deployment script will take considerably longer as it tries to initialize every pool of every masterchefs rather than the first few
2. Change the variable CURRENTLY_FORKING in the .env file to whichever network's fork you would like to run tests on
3. Run `npx hardhat test`
