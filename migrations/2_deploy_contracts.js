var DEFI_Insurance = artifacts.require("./DEFI_Insurance.sol");
var TravelCrowdsurance = artifacts.require("./TravelCrowdsurance.sol");

module.exports = async function (deployer) {
  await deployer.deploy(DEFI_Insurance);
  const dfip = await DEFI_Insurance.deployed();

  await deployer.deploy(TravelCrowdsurance, dfip.address, 0, false, 0);
  const travelCrowdsurance = await TravelCrowdsurance.deployed();

  await dfip.approve(travelCrowdsurance.address, "300000000000000000");
};
