//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";
//we need mocks but chainlink alsready has one for us, so import
import {VRFCoordinatorV2Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract HelperConfig is Script {
    /** type declarations */

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        address link; //this is an extra line we added for the address of the LINK token. Will be needed to fund the subscription
        uint256 deployerKey;
    }

    //pasting an private key here is ONLY OK for ANVIL
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30, //seconds
                vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
                gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, //from https://docs.chain.link/vrf/v2/subscription/supported-networks
                subscriptionId: 3472,
                callbackGasLimit: 500000, //500,000 gas
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, //Sepolia address for Chiainlink's LINK token contract
                deployerKey: vm.envUint("PRIVATE_KEY") //in order for out tests to work, we have to be the owner of the addConsumer address. In the vm.startBroadcast statements, we can pass a private key we want to use. We dfine that here by getting it from the -env fil.
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        //followin 2 params are nedded as input for VRFCoordinatorV2Mock constructor
        uint96 baseFee = 0.25 ether; //which is really 0.25 LINK
        uint96 gasPriceLink = 1e9; //1 gwei LINK

        vm.startBroadcast(); //need this to actually deploy to any NW
        VRFCoordinatorV2Mock vrfCoordinatorMock = new VRFCoordinatorV2Mock(
            baseFee,
            gasPriceLink
        );
        LinkToken link = new LinkToken();
        vm.stopBroadcast();

        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30, //seconds
                vrfCoordinator: address(vrfCoordinatorMock),
                gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, //does not matter
                subscriptionId: 0, //our script will add this
                callbackGasLimit: 500000, //500,000 gas
                link: address(link),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
