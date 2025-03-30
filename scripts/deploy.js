const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);

    // 部署 YiDengToken
    const YiDengToken = await hre.ethers.getContractFactory("YiDengToken");
    const yiDengToken = await YiDengToken.deploy();
    await yiDengToken.waitForDeployment();
    console.log("YiDengToken deployed to:", yiDengToken.target);

    // 部署 CourseCertificate
    const CourseCertificate = await hre.ethers.getContractFactory(
        "CourseCertificate"
    );
    const courseCertificate = await CourseCertificate.deploy();
    await courseCertificate.waitForDeployment();
    console.log("CourseCertificate deployed to:", courseCertificate.target);

    // 部署 CourseMarket
    const CourseMarket = await hre.ethers.getContractFactory("CourseMarket");
    const courseMarket = await CourseMarket.deploy(
        yiDengToken.target,
        courseCertificate.target
    );
    await courseMarket.waitForDeployment();
    console.log("CourseMarket deployed to:", courseMarket.target);

    // 可选：初始化 YiDengToken 的初始分配
    // const teamWallet = "0xYourTeamWalletAddress";
    // const marketingWallet = "0xYourMarketingWalletAddress";
    // const communityWallet = "0xYourCommunityWalletAddress";
    // await yiDengToken.distributeInitialTokens(
    //     teamWallet,
    //     marketingWallet,
    //     communityWallet
    // );
    // console.log("Initial token distribution completed");

    // 输出合约地址
    console.log("\nDeployed contract addresses:");
    console.log("YiDengToken:", yiDengToken.target);
    console.log("CourseCertificate:", courseCertificate.target);
    console.log("CourseMarket:", courseMarket.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
