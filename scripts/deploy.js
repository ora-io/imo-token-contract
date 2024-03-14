// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
    const token = await hre.ethers.deployContract("ERC7641", ["Subnet 6 RevShare Token", "SN6", 1000000000, 80, 648000]);

    await token.waitForDeployment();

    console.log(
        `Token deployed to: ${await token.getAddress()} with the following parameters:
        Name: ${await token.name()}
        Symbol: ${await token.symbol()}
        Total Supply: ${await token.totalSupply()}
        Decimals: ${await token.decimals()}
        Percent Claimable: ${await token.percentClaimable()}
        Snapshot Interval: ${await token.snapshotInterval()}
        `
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
