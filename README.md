# defi_orders

A service to bring finance orders such as stop loss and take profit to defi protocols

# Setup

    -Create a .env file using .env.example as a template
    -Run `yarn` or `npm install`

# Deploying

In order to deploy to a public network:

    - Change the variable ENVIRONMENT to 'prod'
    - Run `npx hardhat run --network <NETWORK> scripts/deploy.ts`

In order to deploy locally:

    - Change the variable ENVIRONMENT to 'test'. You can leave it as prod, but the deployment script will take considerably longer as it tries to initialize every pool of every masterchefs rather than the first few
    - Change the varieble CURRENTLY_FORKING to whichever network you would like to fork
    - Run `npx hardhat node`
    - Run `npx hardhat run --network localhost scripts/deploy.ts`

# Testing

    - Change the variable ENVIRONMENT to 'test'. You can leave it as prod, but the deployment script will take considerably longer as it tries to initialize every pool of every masterchefs rather than the first few
    - Change the varieble CURRENTLY_FORKING to whichever network's fork you would like to run tests on
    - Run `npx hardhat test`
