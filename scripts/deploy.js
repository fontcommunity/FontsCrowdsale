// scripts/deploy.js
async function main() {
  // We get the contract to deploy
  const FontsPresale = await ethers.getContractFactory("FontsPresale");
  console.log("Deploying FontsPresale...");
  const _fontsPresale = await FontsPresale.deploy();
  await _fontsPresale.deployed();
  console.log("FontsPresale deployed to:", _fontsPresale.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });