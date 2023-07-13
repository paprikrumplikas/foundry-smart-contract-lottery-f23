//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
//and, to test our deployments, we need to import the config script
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    //events are not types like enums and structs, so we cannot import them, we have to add them here as well
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_USER_BALANCE); //give the player some money
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); //RHS says that on any Raffle contract, get the open value for the RaffleState enum
    }

    ////////////////////////////////
    // enterRaffle                //
    ////////////////////////////////

    function testRaffleRevertWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER); //pretend to be the player
        //Act / Assert
        //Enums and structs are types, and as such, we can simply import them by name e.g. Raffle.Raffle__NotEnoughEthSent
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector); //expectRevert is a foundry cheat code. We did not learn about function selectors yet
        raffle.enterRaffle(); //not sending any value
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        //assert
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        //expectEmit is a foundry cheat code. How it works:
        //after its line we have to manually emit the event that we expect to be emitted
        //subsequently provide the line which should emit that event
        vm.expectEmit(true, false, false, false, address(raffle)); //4th arg is the address that will emit the event
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //in a forked chain, we can set the block no. and time to whatever we want
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp

        raffle.performUpkeep(""); //this will put the raffle in the calculating state

        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////////////////////
    // checkUpkeep                //
    ////////////////////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep(""); //raffle set up in the set up function

        //Assert
        assert(!upkeepNeeded); //== upkeepNeeded == false
    }

    function testCheclUpkeepReturnsFalseIfRaffleNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp
        raffle.performUpkeep(""); //this will put the raffle in the calculating state

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep(""); //raffle set up in the set up function

        //Assert
        assert(!upkeepNeeded); //== upkeepNeeded == false
    }

    function testCheckUpkeepReturnsFalseIEnoughTimeHasntPassed() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp

        //act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParamsAreGood() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        assert(upkeepNeeded);
    }

    ////////////////////////////////
    // performkUpkeep            //
    ////////////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp

        //Act / Assert
        raffle.performUpkeep("");
    }

    function testPerfromUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint numPlayers = 0;
        uint raffleState = 0;

        //Act / Assert
        //vm.expectRevert(Raffle.Raffle__NoUpkeepNeeded.selector);
        //if we want our custom error to revert with the return params:
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NoUpkeepNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not a must have, but it's good practice to roll the block number after you warp
        _;
    }

    //What if I need to test using the ouput of an event?
    //A regular smart contract cant do that, but during testing in Foundry we can
    //Testing emits is important as e.g. the vrfCoordinator emits an event which the Chainlink nodes listen to, this is how random number generation is working
    function testPerformUpkeepUpdatesRaffleStateandEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        //Arrange: we are using a modifier

        //Act
        vm.recordLogs(); //will automatically save all logs and emits in a data structure that we can read with getRecordedLogs
        raffle.performUpkeep(""); //will emit the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //Log[] is a special type which comes with Foundry tests. To get it, we need to import vm type
        //But what is the order of the logs, where is the emit we are looking for? We cheat a bit, we know that the its gonna be the second one emitted by this trx
        //all logs are recorded as bytes32 in Foundry
        bytes32 requestId = entries[1].topics[1]; //the 0th topic refers to the entire event

        Raffle.RaffleState rState = raffle.getRaffleState();

        //Assert
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1); //1 is for calculating
    }

    ////////////////////////////////
    // performkUpkeep            //
    ////////////////////////////////

    modifier skipTestonForkedNetwork() {
        if (block.chainid != 31337) {
            //if chainId is not the ANVIL chainid, just return
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep()
        public
        raffleEnteredAndTimePassed
        skipTestonForkedNetwork
    {
        //Arrange
        //we use 2 modifiers
        //we are skipping this test if we are on a forked NW, as the real VRF coordinator is more complex than our mock
        vm.expectRevert("nonexistent request"); //this custom error is defined in VRFCoodrinatorV2Mock
        //Here we are pretending to be vrfCoordinator. On a testnet this would not work
        //The first input param of fulfillRandomWords is the RequestId.
        //We need to make sure that this call fails at any requestId: 0, 1, 2, 3....
        //FUZZ test:
        //1. define randomRequestId
        //2. Foundry will create a random number for this and will make this call with a number of random numbers
        uint256 randomRequestId;

        //Act / Assert
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    //big test
    function testFulfillRandomWordsPicksARandomWinnnerAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipTestonForkedNetwork
    {
        //Arrange
        //we use 2 modifiers
        //we are skipping this test if we are on a forked NW, as we are gonna pretend we are the vrfCoordinator which is not working on a forked real testnet
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        //to have multiple players:
        for (
            uint256 i = startingIndex;
            i < additionalEntrants + startingIndex;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE); //hoax = prank + deal
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        //pretend to be chainlink vrf to get the random number
        //fulfillRandomwords takes 2 params: requestId and the consumer
        //consumer is gonna be the raffle contract
        //to get the requestId:
        vm.recordLogs();
        raffle.performUpkeep(""); //will emit the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; //the 0th topic refers to the entire event

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        //Act
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
        assert(raffle.getLengthOfPlayers() == 0);
        assert(raffle.getLastTimeStamp() > previousTimeStamp);
    }

    /*Tried to write it myself, but it's not working
    function testEmitsWinner() public raffleEnteredAndTimePassed {
        //Arrange
        // we use a modifier PLUS:

        //to get the requestId from the emits:
        vm.recordLogs();
        raffle.performUpkeep(""); //will emit the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; //the 0th topic refers to the entire event

        vm.expectEmit(true, false, false, false, address(raffle)); //4th arg is the address that emits the event
        emit PickedWinner(raffle.getRecentWinner());
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
    }*/
}
