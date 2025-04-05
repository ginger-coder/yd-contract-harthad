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

    // 授予 MINTER_ROLE ，让 CourseMarket 合约可以铸造代币
    const MINTER_ROLE = await courseCertificate.MINTER_ROLE();
    await courseCertificate.grantRole(MINTER_ROLE, courseMarket.target);
    console.log(`CourseMarket (${courseMarket.target}) granted MINTER_ROLE`);

    // 上传源码 
    await hre.run("verify:verify", {
        address: yiDengToken.target,
        constructorArguments: [],
    });
    await hre.run("verify:verify", {
        address: courseCertificate.target,
        constructorArguments: [],
    });
    await hre.run("verify:verify", {
        address: courseMarket.target,
        constructorArguments: [yiDengToken.target, courseCertificate.target],
    });
    console.log("Source code verified on Etherscan");

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
