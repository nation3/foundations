import { wallet, dec, save } from "./helpers";
import { ethers, BigNumber, Contract } from "ethers";
import { formatUnits } from "@ethersproject/units"

import { exec } from "child_process";

import Nation from '../out/NATION.sol/NATION.json';
import VotingEscrow from '../out/VotingEscrow.vy/VotingEscrow.json';
import LiquidityDistributor from '../out/BoostedLiquidityDistributor.sol/BoostedLiquidityDistributor.json';
import MockERC20 from '../out/MockERC20.sol/MockERC20.json';
import MerkleDistributorV2 from '../out/MerkleDistributorV2.sol/MerkleDistributorV2.json';
import Passport from '../out/Passport.sol/Passport.json';
import PassportIssuer from '../out/PassportIssuer.sol/PassportIssuer.json';

const getContractFactory = (artifact: any) => {
  return new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, wallet);
}

const deployContract = async ({ name, deployer, factory, args }: { name: string, deployer: ethers.Wallet, factory: ethers.ContractFactory, args: Array<any> }) => {
  console.log(`Deploying ${name}..`)
  const contract = await factory.connect(deployer).deploy(...args);
  await contract.deployed();
  console.log(`Deployed ${name} to: ${contract.address}`)
  return contract;
}


const deployNation = async () => {
  const supply: BigNumber = BigNumber.from(process.env.NATION_SUPPLY ?? dec(42069, 18));
  const Factory = getContractFactory(Nation);

  const nationToken = await deployContract({
    name: "NATION",
    deployer: wallet,
    factory: Factory,
    args: []
  });

  await nationToken.connect(wallet).mint(wallet.address, supply);
  console.log(`Minted ${formatUnits(supply, 18)} tokens to deployer address`)

  return nationToken;
}
const verifyNationContract = async (address: string, path: string, constructorArgs: Array<any>) => {
  exec(
    ["forge verify-contract", address, path, "--chain-id", 11155111].join(" "),
    (error, stdout, stderr) => {
      console.log(error)
      console.log(stdout)
      console.log(stderr)
    }
  );

}

const deployVeNation = async (nationToken: Contract) => {
  const Factory = getContractFactory(VotingEscrow);

  const veNATION = await deployContract({
    name: "veNATION",
    deployer: wallet,
    factory: Factory,
    args: [nationToken.address, "Vote-escrowed NATION", "veNATION", "veNATION_1.0.0"]
  })

  return veNATION;
}

const deployAirdropDistributor = async (nationToken: Contract, root: string) => {
  const Factory = getContractFactory(MerkleDistributorV2);
  const dropAmount = BigNumber.from(process.env.AIRDROP_AMOUNT ?? dec(314, 18));

  const airdropDistributor = await deployContract({
    name: "nationDropContract",
    deployer: wallet,
    factory: Factory,
    args: []
  })
  await airdropDistributor.setUp(wallet.address, nationToken.address, root);

  await nationToken.connect(wallet).approve(airdropDistributor.address, dropAmount);
  console.log(`Approved ${formatUnits(dropAmount, 18)} tokens for drop`);

  return airdropDistributor;
}

const deployLiquidityDistributor = async (rewardsToken: Contract, boostToken: Contract) => {
  const contractFactory = getContractFactory(LiquidityDistributor);
  const tokenFactory = getContractFactory(MockERC20);
  const supply = BigNumber.from(dec(314, 18));
  const rewards = BigNumber.from(dec(500, 18));
  const rewardsPeriod = 1196308; // 6 months of blocks approx

  const lpToken = await deployContract({
    name: "lpToken",
    deployer: wallet,
    factory: tokenFactory,
    args: ["80NATION-20WETH", "80NATION-20WETH", supply]
  })

  const distributor = await deployContract({
    name: "lpRewardsContract",
    deployer: wallet,
    factory: contractFactory,
    args: []
  })

  await distributor.connect(wallet).initialize(rewardsToken.address, lpToken.address, boostToken.address);

  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
  const blockNumber = await provider.getBlockNumber();
  // Setup rewards
  await rewardsToken.connect(wallet).mint(distributor.address, rewards);
  const startBlock = blockNumber + 5;
  const endBlock = startBlock + rewardsPeriod;

  await distributor.connect(wallet).setRewards(rewards, startBlock, endBlock);
  console.log(`Set ${formatUnits(rewards, 18)} NATIONs as rewards from block ${startBlock} to ${endBlock}`)

  return { "lpToken": lpToken, "lpRewardsContract": distributor }
}

const verifyLpToken = async (address: string, path: string) => {
  const tokenFactory = getContractFactory(MockERC20);
  const args = tokenFactory.interface.encodeDeploy(["80NATION-20WETH", "80NATION-20WETH", BigNumber.from(dec(314, 18))])
  exec(
    ["forge verify-contract", address, path, "--constructor-args", args, "--chain-id", 11155111].join(" "),
    (error, stdout, stderr) => {
      console.log(error)
      console.log(stdout)
      console.log(stderr)
    }
  );
}

const verifyLiquidityDistributor = async (address: string, path: string) => {
  exec(
    ["forge verify-contract", address, path, "--chain-id", 11155111].join(" "),
    (error, stdout, stderr) => {
      console.log(error)
      console.log(stdout)
      console.log(stderr)
    }
  );
}

const deployPassport = async (governanceToken: Contract) => {
  const agreementStatement = "By claiming a Nation3 passport I agree to the terms defined in the following URL";
  const agreementURI = "https://bafkreiadlf3apu3u7blxw7t2yxi7oyumeuzhoasq7gqmcbaaycq342xq74.ipfs.dweb.link";

  const passportFactory = getContractFactory(Passport);
  const passportIssuerFactory = getContractFactory(PassportIssuer);

  const passportToken = await deployContract({
    name: "Passport",
    deployer: wallet,
    factory: passportFactory,
    args: ["Nation3 Passport", "PASS3"]
  })

  const passportIssuer = await deployContract({
    name: "PassportIssuer",
    deployer: wallet,
    factory: passportIssuerFactory,
    args: []
  })

  await passportToken.connect(wallet).transferControl(passportIssuer.address);
  // TODO: Set renderer

  await passportIssuer.connect(wallet).initialize(governanceToken.address, passportToken.address, 420);
  await passportIssuer.connect(wallet).setParams(0, 0);
  await passportIssuer.connect(wallet).setStatement(agreementStatement);
  await passportIssuer.connect(wallet).setTermsURI(agreementURI);
  await passportIssuer.connect(wallet).setEnabled(true);

  return { "passportToken": passportToken, "passportIssuer": passportIssuer, "agreementStatement": agreementStatement, "agreementURI": agreementURI }
}

const verifyPassport = async (address: string, path: string) => {
  const passportFactory = getContractFactory(Passport);
  const args = passportFactory.interface.encodeDeploy(["Nation3 Passport", "PASS3"])
  exec(
    ["forge verify-contract", address, path, "--constructor-args", args, "--chain-id", 11155111].join(" "),
    (error, stdout, stderr) => {
      console.log(error)
      console.log(stdout)
      console.log(stderr)
    }
  );
}

const verifyPassportIssuer = async (address: string, path: string) => {
  exec(
    ["forge verify-contract", address, path, "--chain-id", 11155111].join(" "),
    (error, stdout, stderr) => {
      console.log(error)
      console.log(stdout)
      console.log(stderr)
    }
  );
}

const main = async () => {
  console.log(`Using deployer: ${wallet.address}`);

  const NATION = await deployNation();
  const veNATION = await deployVeNation(NATION);
  const lpContracts = await deployLiquidityDistributor(NATION, veNATION);
  const nationDropA = await deployAirdropDistributor(NATION, "0xed145aa219b18aa3f2dc56afb2c4e0b148e429ca93b9c5f2c7a29d2101685aee");
  const nationDropB = await deployAirdropDistributor(NATION, "0xb8d662135979ae3791167c967cba4bf6fb681c665d0c03372745c483fe5089f8");

  const passportContracts = await deployPassport(veNATION);

  const deployment = {
    "nationToken": NATION.address,
    "veNationToken": veNATION.address,
    "balancerLPToken": lpContracts.lpToken.address,
    "lpRewardsContract": lpContracts.lpRewardsContract.address,
    "nationDropContracts": [nationDropA.address, nationDropB.address],
    "nationPassportNFT": passportContracts.passportToken.address,
    "nationPassportNFTIssuer": passportContracts.passportIssuer.address,
    "nationPassportAgreementStatement": passportContracts.agreementStatement,
    "nationPassportAgreementURI": passportContracts.agreementURI,
  }

  const manifestFile = "./deployments/local.json";
  save(deployment, manifestFile);

  console.log(`Deployment manifest saved to ${manifestFile}`)

  console.log("Contract verification...")

  await verifyNationContract("0x23Ca3002706b71a440860E3cf8ff64679A00C9d7", "src/tokens/NATION.sol:NATION", [])
  await verifyLpToken("0x6417755C00d5c17DeC196Df00a6F151E448B1471", "src/test/utils/mocks/MockERC20.sol:MockERC20")
  await verifyLiquidityDistributor("0x534AB4F195Ac166B78d9edCdbeA04802392711aA", "src/distributors/BoostedLiquidityDistributor.sol:BoostedLiquidityDistributor")
  await verifyLiquidityDistributor("0x534AB4F195Ac166B78d9edCdbeA04802392711aA", "src/distributors/BoostedLiquidityDistributor.sol:BoostedLiquidityDistributor")
  await verifyPassport("0x11f30642277A70Dab74C6fAF4170a8b340BE2f98", "src/passport/Passport.sol:Passport")
  await verifyPassportIssuer("0xdad32e13E73ce4155a181cA0D350Fee0f2596940", "src/passport/PassportIssuer.sol:PassportIssuer")
}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
