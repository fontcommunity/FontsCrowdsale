// scripts/deploy.js
async function main() {
  // We get the contract to deploy
  const FontsCrowdsale = await ethers.getContractFactory("FontsCrowdsale");
  console.log("Deploying FontsCrowdsale...");
  const _fontsCrowdsale = await FontsCrowdsale.deploy("0xf021d77ac81d1da155de9c356e568f7583552080", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
  await _fontsCrowdsale.deployed();
  console.log("FontsCrowdsale deployed to:", _fontsCrowdsale.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });