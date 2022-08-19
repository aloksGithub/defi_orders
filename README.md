# defi_orders

A service to bring finance orders such as stop loss and take profit to defi protocols

# Setup

1) Create a .env file using .env.example as a template
2) Run `yarn` or `npm install`

# Deploying

In order to deploy to a public network:

1) Change the variable ENVIRONMENT to 'prod'
2) Run `npx hardhat run --network <NETWORK> scripts/deploy.ts`

In order to deploy locally:

1) Change the variable ENVIRONMENT to 'test'. You can leave it as prod, but the deployment script will take considerably longer as it tries to initialize every pool of every masterchefs rather than the first few
2) Change the varieble CURRENTLY_FORKING to whichever network you would like to fork
3) Run `npx hardhat node`
4) `npx hardhat run --network localhost scripts/deploy.ts`

# Testing

1) Change the variable ENVIRONMENT to 'test'. You can leave it as prod, but the deployment script will take considerably longer as it tries to initialize every pool of every masterchefs rather than the first few
2) Change the varieble CURRENTLY_FORKING to whichever network's fork you would like to run tests on
3) Run `npx hardhat test`
