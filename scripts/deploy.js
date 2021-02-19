// scripts/deploy.js
async function main() {
  // We get the contract to deploy
  const FontsPresale = await ethers.getContractFactory("FontsPresale");
  console.log("Deploying FontsPresale...");
  const _fontsPresale = await FontsPresale.deploy("0xf021d77ac81d1da155de9c356e568f7583552080", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
  await _fontsPresale.deployed();
  console.log("FontsPresale deployed to:", _fontsPresale.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });