// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//deployed this to Sepolia:
//https://sepolia.etherscan.io/address/0xB527E253319C722b25a684025E8a63a0261f967C

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title A sample raffle contract
 * @author Norbert Orgovan
 * @notice This contract is for creating a siVRFmple raffle
 * @dev Implements Chainlink VRFv2
 */

//before importing, intall this: forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit
//then add this to the foundry.toml: remappings = ['@chainlink/contracts/=lib/chainlink-brownie-contracts/contracts/']
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    /** custom errrors */
    error Raffle__NotEnoughEthSent();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__NoUpkeepNeeded(
        uint256 currentBalance,
        uint256 numberOfPlayers,
        uint256 raffleState
    ); //we can give arguments to custom errors which can than be used for debugging

    /* type declarations */
    //this could be done with a bool as well, but only until we have 2 states, so for future proofing, we use an enum
    //enums are custom types w a finite set of constant values
    //they can be explicitly converted to and from all integer types
    enum RaffleState {
        OPEN, //0
        CALCULATING //1
    }

    /** state vars */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1; //no of random numbers

    uint256 private immutable i_entranceFee;
    uint private immutable i_interval;
    VRFCoordinatorV2Interface immutable i_vrfCoordinator; //this is different on every chain
    bytes32 private immutable i_gasLane; //also chain dep
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players; //we use addresses as mappings cannot be looped through, so we use an array
    uint256 private s_lastTimeStamp;
    address private s_mostRecentWinner; //to keep track
    RaffleState private s_raffleState;

    /** events 
        - Events are part of the EVM transaction log
        - Events are not accessible from within contracts
        - We can write important things to the event log. 3 can be indexed, these are the topics. The rest goes to data.
        - We wanna use events whenever we update a state variable
        benefits of events
        1. Makes migration easier
        2. Makes front end "indexing" easier*/
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        //values for these are defined in HelperConfig.sol
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    )
        VRFConsumerBaseV2(vrfCoordinator) //we need to include this because we inherit from VRFConsumerBaseV2, which has a constructor itself with 1 param
    {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator); //typecasting vrfCoordinator address as a VRFCoordinatorV2Interface
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN; //we set the initial state to open
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        //external because we are not gonna have anything calling it from within this contract and external is more gas-efficient than public
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        //we dont want anyone to enter the raffle while we are calculating the winner
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    //this is the first function we need for Chainlink automation (for automatically picking a winner)
    //checks if it is time for picking a winner
    /**
     *
     * @dev this is the function that the chainklink Automation nodes call
     * to see if it is time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval has passed between the faffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (i.e. players)
     * 4. (Implicit) The subscription is funded with LINK
     */
    //if a func need an input param bt we dont need it, we can just wrap it like below
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        //check to see if enough time has passed
        bool timeHasPased = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPased && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); //with the second one we are saying its a blank bytes object
    }

    //this is the second function we need for Chainlink automation. Chainlink automation nodes will make the call for us
    //external so anybody can call this. For this reason, we need to perform a check by calling the checkUpkeep function
    //We have to create an Upkeep on Chainklink (automation.chain.link), so that Chainlink nodes can call this function, we wont have to interact with it manually
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            //notice how the condition is written
            revert Raffle__NoUpkeepNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING; //so that ppl cannot enter the raffle during calculation

        //getting a random number is a 2-transaction function
        //1. request the RNG
        //2. get the random number

        //this is the chainlink vrf call (copied than refactored)
        //we make a request here to the chainlink node to give us a random number, its gonna generate the ran num
        uint256 requestId = i_vrfCoordinator.requestRandomWords( //this is actually the function call from https://docs.chain.link/vrf/v2/subscription/examples/get-a-random-number and the Chainlink address we make our request to
            i_gasLane, //gas Lane, also dependent on the chain
            i_subscriptionId, //chainlink ID that we funded with link in order to make this req
            REQUEST_CONFIRMATIONS, //no of block confirmation for our random num to be considered good
            i_callbackGasLimit,
            NUM_WORDS //number of random numbers
        );

        //this is redundant sinse our vrfCoordinatorV2Mock already emits the requestId
        emit RequestedRaffleWinner(requestId);
    }

    //this is the function the chainlink node is gonna call to give us back the random number
    //we inherit this function from the VRFConsumerBaseV2 contract, so we have to import it and make our contract inherit from it
    //design pattern we use: CEI - checks, effects (within our own contract), interactions (with other contracts)
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length; // % is the modulo operator, it gives us the remainder of the division
        address payable winner = s_players[indexOfWinner];
        s_mostRecentWinner = winner;
        s_raffleState = RaffleState.OPEN; //we open the raffle again
        s_players = new address payable[](0); //we reset the players array
        s_lastTimeStamp = block.timestamp;

        emit PickedWinner(winner); //CEI: place it before external intercations, since this is an effect

        //pay out the winner
        (bool success, ) = winner.call{value: address(this).balance}(""); //("") represets blank for the object
        if (success != true) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_mostRecentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
