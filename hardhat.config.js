/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require('@nomiclabs/hardhat-ethers');
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");


const { alchemyApiKey, mnemonic, pvt1key } = require('./sregate');

module.exports = {
  networks: {
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${alchemyApiKey}`,
      accounts: {mnemonic: mnemonic}
    },
    /*mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
      accounts: [pvt1key],
      chainId: 1,
      live: true,
      saveDeployments: true,
    },*/
  },
  etherscan: {
    apiKey: "F77KW26RW1EMRY3GY62XWH3AW719RPW9CF"
  },  
  solidity: "0.7.3",
  gasReporter: {
    currency: 'USD',
    gasPrice: 210,
    enabled: true,
  }  
};
