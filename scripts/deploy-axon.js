// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
    const [signer] = await hre.ethers.getSigners();
    const ORAAxonManager = await hre.ethers.getContractFactory("ORAAxonManager");
    const tokenEmitterAddress = "0x0000000000000000000000000000000000000000"; // Use the zero address as a hex string
    const axonManager = await ORAAxonManager.deploy(tokenEmitterAddress, signer);

    await axonManager.waitForDeployment();

    console.log(
        `Axon Manager deployed to: ${await axonManager.getAddress()}`
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
