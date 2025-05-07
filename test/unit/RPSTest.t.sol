// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RockPaperScissors} from "src/RockPaperScissors.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployRPS} from "script/DeployRPS.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Vm} from "forge-std/Vm.sol";
// import {MockVRFCoordinatorV2Plus} from "test/mocks/MockVRFCoordinatorV2Plus.sol";
// import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

contract RockPaperScissorsTest is Test {
    RockPaperScissors public rps;
    HelperConfig public helperConfig;

    address public vrfCoordinator;
    bytes32 public gasLane;
    uint256 public subscriptionId;
    uint32 public callbackGasLimit;

    address public PLAYER1 = makeAddr("PLAYER1");
    address public PLAYER2 = makeAddr("PLAYER2");
    address public PLAYER3 = makeAddr("PLAYER3");

    uint256 public constant JOIN_TIMEOUT = 10 minutes;
    uint256 public constant COMMIT_TIMEOUT = 5 minutes;
    uint256 public constant REVEAL_TIMEOUT = 3 minutes;
    uint256 public constant GAME_FEE_RATE = 95;
    uint256 public constant GAME_FEE_RATE_DENOMINATOR = 100;

    uint256 public constant STARTING_BALANCE = 1 ether;
    uint256 public BET_AMOUNT = 0.01 ether;

    function setUp() public {
        DeployRPS deployer = new DeployRPS();
        (rps, helperConfig) = deployer.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        // Deal some ether to players
        vm.deal(PLAYER1, STARTING_BALANCE);
        vm.deal(PLAYER2, STARTING_BALANCE);
        vm.deal(PLAYER3, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATE GAME TEST
    //////////////////////////////////////////////////////////////*/
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testRevertIfCreateBetAmountTooLow() public {
        vm.startPrank(PLAYER1);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__BetAmountsMustBeGreater.selector);
        rps.createGame{value: 0.001 ether}();
        vm.stopPrank();
    }

    function testRevertIfGameStateNotOpen() public {
        vm.prank(PLAYER1);
        rps.createGame{value: BET_AMOUNT}();

        vm.prank(PLAYER2);
        rps.joinGame{value: BET_AMOUNT}();

        vm.startPrank(PLAYER3);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__GameAlreadyClosed.selector);
        rps.createGame{value: BET_AMOUNT}();
        vm.stopPrank();
    }

    function testCanCreateGame() public skipFork {
        vm.startPrank(PLAYER1);
        // mockToken.approve(address(rps), betAmount);

        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.GameStateChanged(RockPaperScissors.GameState.Open);
        
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.PlayerCreatedGame(PLAYER1);
        
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.GameDetailsUpdated(block.timestamp, BET_AMOUNT, block.timestamp);
        
        rps.createGame{value: BET_AMOUNT}();
        rps.requestRandomSalt(PLAYER1);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(rps.getPlayerToRequestId(PLAYER1), address(rps));
        vm.stopPrank();

        assertEq(rps.getPlayer1(), PLAYER1);
        assertEq(address(rps).balance, BET_AMOUNT);
        assertEq(rps.getPlayerSaltStatus(PLAYER1), true);
        assertEq(uint256(rps.getGameState()), uint256(RockPaperScissors.GameState.Open));
    }

    /*//////////////////////////////////////////////////////////////
                             JOIN GAME TEST
    //////////////////////////////////////////////////////////////*/
    modifier gameCreated() {
        vm.startPrank(PLAYER1);
        rps.createGame{value: BET_AMOUNT}();
        rps.requestRandomSalt(PLAYER1);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(rps.getPlayerToRequestId(PLAYER1), address(rps));
        vm.stopPrank();
        _;
    }

    function testRevertIfGameAlreadyClosed() public gameCreated {
        vm.startPrank(PLAYER2);
        rps.joinGame{value: BET_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(PLAYER3);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__GameAlreadyClosed.selector);
        rps.joinGame{value: BET_AMOUNT}();
        vm.stopPrank();
    }

    function testRevertIfPlayerJoinsOwnGame() public gameCreated {
        vm.startPrank(PLAYER1);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__CannotJoinYourOwnGame.selector);
        rps.joinGame{value: BET_AMOUNT}();
        vm.stopPrank();
    }

    function testRevertIfJoinBetAmountNotSame() public gameCreated {
        vm.startPrank(PLAYER2);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__BetAmountsMustBeSame.selector);
        rps.joinGame{value: 0.001 ether}();
        vm.stopPrank();
    }

    function testJoinGame() public gameCreated skipFork {
        vm.startPrank(PLAYER2);
        
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.GameStateChanged(RockPaperScissors.GameState.Ready);
        
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.PlayerJoinedGame(PLAYER2);
        
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.GameDetailsUpdated(block.timestamp, BET_AMOUNT, block.timestamp);
        
        rps.joinGame{value: BET_AMOUNT}();
        rps.requestRandomSalt(PLAYER2);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(rps.getPlayerToRequestId(PLAYER2), address(rps));
        vm.stopPrank();

        console.log(rps.getPlayerToRequestId(PLAYER2));
        
        assertEq(rps.getPlayer2(), PLAYER2);
        assertEq(rps.getPlayerSaltStatus(PLAYER2), true);
        assertEq(uint256(rps.getGameState()), uint256(RockPaperScissors.GameState.Ready));
        assertEq(address(rps).balance, BET_AMOUNT*2);
    }

    /*//////////////////////////////////////////////////////////////
                             MAKE MOVE TEST
    //////////////////////////////////////////////////////////////*/
    modifier joinedGame() {
        vm.prank(PLAYER1);
        rps.createGame{value: BET_AMOUNT}();
        rps.requestRandomSalt(PLAYER1);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(rps.getPlayerToRequestId(PLAYER1), address(rps));

        vm.prank(PLAYER2);
        rps.joinGame{value: BET_AMOUNT}();
        rps.requestRandomSalt(PLAYER2);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(rps.getPlayerToRequestId(PLAYER2), address(rps));
        _;
    }

    function testRevertIfNotPlayer() public gameCreated {
        vm.startPrank(PLAYER3);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__PlayerNotInGame.selector);
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.stopPrank();
    }

    function testRevertIfGameNotReady() public gameCreated {
        vm.startPrank(PLAYER1);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__InvalidGameState.selector);
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.stopPrank();
    }

    function testRevertIfPlayerHasNotRecivedSalt() public gameCreated {
        vm.startPrank(PLAYER2);
        rps.joinGame{value: BET_AMOUNT}();
        vm.expectRevert(RockPaperScissors.RockPaperScissors__SaltNotSetYet.selector);
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.stopPrank();
    }

    function testRevertIfPlayerAlreadyMakeMove() public joinedGame {
        vm.startPrank(PLAYER1);
        rps.makeMove(RockPaperScissors.Move.Rock);

        vm.expectRevert(RockPaperScissors.RockPaperScissors__MoveAlreadyCommitted.selector);
        rps.makeMove(RockPaperScissors.Move.Paper);
        vm.stopPrank();
    }

    function testRevertIfMoveNotValid() public joinedGame {
        vm.startPrank(PLAYER1);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__InvalidMove.selector);
        rps.makeMove(RockPaperScissors.Move.None);
        vm.stopPrank();
    }

    function testCanMakeMove() public joinedGame skipFork {
        vm.startPrank(PLAYER1);
        
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.PlayerMadeMove(PLAYER1);
        
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.stopPrank();
        
        assertEq(rps.getPlayerCommitStatus(PLAYER1), true);
    }

    /*//////////////////////////////////////////////////////////////
                             GAME FLOW TEST
    //////////////////////////////////////////////////////////////*/
    function testFullGameFlows(uint8 move1, uint8 move2) public joinedGame skipFork {
        // Validation values: 1 = Rock, 2 = Paper, 3 = Scissors
        vm.assume(move1 >= 1 && move1 <= 3);
        vm.assume(move2 >= 1 && move2 <= 3);
    
        // Convert to enum
        RockPaperScissors.Move p1Move = RockPaperScissors.Move(move1);
        RockPaperScissors.Move p2Move = RockPaperScissors.Move(move2);
    
        // Commit moves
        vm.prank(PLAYER1);
        rps.makeMove(p1Move);
        vm.prank(PLAYER2);
        rps.makeMove(p2Move);
        assertEq(uint256(rps.getGameState()), uint256(RockPaperScissors.GameState.Committed));
    
        // Reveal PLAYER1
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.PlayerRevealedMove(PLAYER1, p1Move);
        vm.prank(PLAYER1);
        rps.revealMove(p1Move);
        
        // Determine winner
        uint256 expectedPrize = (2 * rps.getGameDetails().betAmount * 95) / 100;
        address winner;
        address loser;

        if (p1Move == p2Move) {
            // Draw - refund both players
            winner = address(0);
            loser = address(0);
        } else if (
            (p1Move == RockPaperScissors.Move.Rock && p2Move == RockPaperScissors.Move.Scissors) ||
            (p1Move == RockPaperScissors.Move.Paper && p2Move == RockPaperScissors.Move.Rock) ||
            (p1Move == RockPaperScissors.Move.Scissors && p2Move == RockPaperScissors.Move.Paper)
        ) {
            // Player 1 wins
            winner = PLAYER1;
            loser = PLAYER2;
        } else {
            // Player 2 wins
            winner = PLAYER2;
            loser = PLAYER1;
        }

        // Reveal PLAYER2
        vm.expectEmit(true, true, true, true);
        emit RockPaperScissors.GameStateChanged(RockPaperScissors.GameState.Revealed);
        emit RockPaperScissors.GameResult(winner, expectedPrize);
        emit RockPaperScissors.GameStateChanged(RockPaperScissors.GameState.Finished);
        emit RockPaperScissors.PlayerRevealedMove(PLAYER2, p2Move);
        vm.prank(PLAYER2);
        rps.revealMove(p2Move);
        

        // Check final balances
        if (winner != address(0)) {
            assertEq(winner.balance, STARTING_BALANCE - BET_AMOUNT + expectedPrize);
            assertEq(loser.balance, STARTING_BALANCE - BET_AMOUNT);
            assertEq(address(rps).balance, 2 * BET_AMOUNT - expectedPrize);
        } else {
            // draw
            assertEq(PLAYER1.balance, STARTING_BALANCE);
            assertEq(PLAYER2.balance, STARTING_BALANCE);
            assertEq(address(rps).balance, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SALT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    function testCannotMakeMoveBeforeSaltReceived() public gameCreated {
        // Try to make a move before salt is received
        vm.startPrank(PLAYER1);
        rps.createGame{value: BET_AMOUNT}();
        rps.requestRandomSalt(PLAYER1);
        vm.expectRevert(RockPaperScissors.RockPaperScissors__SaltNotSetYet.selector);
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.stopPrank();
    }

    // /*//////////////////////////////////////////////////////////////
    //                         TIMEOUT TESTS
    // //////////////////////////////////////////////////////////////*/
    function testJoinTimeout() public gameCreated {
        // Fast forward past JOIN_TIMEOUT
        vm.warp(block.timestamp + JOIN_TIMEOUT + 1);
        
        // Check upkeep needed
        (bool upkeepNeeded,) = rps.checkUpkeep("");
        assertTrue(upkeepNeeded);
        
        rps.performUpkeep(abi.encode(1));
        
        // Player1 should be refunded
        assertEq(PLAYER1.balance, STARTING_BALANCE);
        assertEq(uint256(rps.getGameState()), uint256(RockPaperScissors.GameState.Open));
    }

    function testCommitTimeoutNoMoves() public joinedGame {
        // Fast forward past COMMIT_TIMEOUT
        vm.warp(block.timestamp + COMMIT_TIMEOUT + 1);
        
        // Check upkeep needed
        (bool upkeepNeeded,) = rps.checkUpkeep("");
        assertTrue(upkeepNeeded);
        
        rps.performUpkeep(abi.encode(2));
        
        // Player1 should win by default
        assertEq(PLAYER1.balance, STARTING_BALANCE);
        assertEq(PLAYER2.balance, STARTING_BALANCE);
    }

    function testCommitTimeoutWhenOnlyOnePlayerCommits() public joinedGame {
        // Commit moves (Rock vs None = Player1 wins)
        vm.prank(PLAYER1);
        rps.makeMove(RockPaperScissors.Move.Rock);
        
        // Fast forward past COMMIT_TIMEOUT
        vm.warp(block.timestamp + COMMIT_TIMEOUT + 1);
        
        // Check upkeep needed
        (bool upkeepNeeded,) = rps.checkUpkeep("");
        assertTrue(upkeepNeeded);
        
        rps.performUpkeep(abi.encode(2));
        
        // Player1 should win by default (PLAYER2 failed to commit)
        assertEq(PLAYER1.balance, STARTING_BALANCE - BET_AMOUNT + (2 * BET_AMOUNT * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR);
        assertEq(PLAYER2.balance, STARTING_BALANCE - BET_AMOUNT);
    }

    function testRevealTimeoutResultsInDrawWhenNoOneReveals() public joinedGame {
        // Commit moves (Rock vs Rock = Draw)
        vm.prank(PLAYER1);
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.prank(PLAYER2);
        rps.makeMove(RockPaperScissors.Move.Rock);
        assertEq(uint256(rps.getGameState()), uint256(RockPaperScissors.GameState.Committed));

        // Fast forward past REVEAL_TIMEOUT
        vm.warp(block.timestamp + REVEAL_TIMEOUT + 1);
        
        // Check upkeep needed
        (bool upkeepNeeded,) = rps.checkUpkeep("");
        assertTrue(upkeepNeeded);
        
        rps.performUpkeep(abi.encode(3));
        
        // Both players should be refunded
        assertEq(PLAYER1.balance, STARTING_BALANCE);
        assertEq(PLAYER2.balance, STARTING_BALANCE);
    }

    function testRevealTimeoutWhenOnlyOnePlayerReveals() public joinedGame {
        // Commit moves (Rock vs Scissors = Player1 wins)
        vm.prank(PLAYER1);
        rps.makeMove(RockPaperScissors.Move.Rock);
        vm.prank(PLAYER2);
        rps.makeMove(RockPaperScissors.Move.Scissors);

        // Only player1 reveals
        vm.prank(PLAYER1);
        rps.revealMove(RockPaperScissors.Move.Rock);
        assertEq(rps.getPlayerRevealStatus(PLAYER1), true);
        assertEq(rps.getPlayerRevealStatus(PLAYER2), false);

        // Fast forward past REVEAL_TIMEOUT
        vm.warp(block.timestamp + REVEAL_TIMEOUT + 1);
        
        // Check upkeep needed
        (bool upkeepNeeded,) = rps.checkUpkeep("");
        assertTrue(upkeepNeeded);
        
        rps.performUpkeep(abi.encode(3));
        
        // Player1 should win by default (PLAYER2 failed to reveal)
        assertEq(PLAYER1.balance, STARTING_BALANCE - BET_AMOUNT + (2 * BET_AMOUNT * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR);
        assertEq(PLAYER2.balance, STARTING_BALANCE - BET_AMOUNT);
    }

    // /*//////////////////////////////////////////////////////////////
    //                         ERROR TESTS
    // //////////////////////////////////////////////////////////////*/
    // function testCannotRevealWrongMove() public {
    //     createGame();
    //     joinGame();
        
    //     vm.prank(player1);
    //     rps.makeMove(Move.Rock);
        
    //     vm.startPrank(player1);
    //     vm.expectRevert(RockPaperScissors.RockPaperScissors__InvalidMove.selector);
    //     rps.revealMove(Move.Paper); // Trying to reveal different move than committed
    //     vm.stopPrank();
    // }
    
    // function testCannotRevealTwice() public {
    //     createGame();
    //     joinGame();
    //     commitMoves(Move.Rock, Move.Paper);
        
    //     vm.prank(player1);
    //     rps.revealMove(Move.Rock);
        
    //     vm.startPrank(player1);
    //     vm.expectRevert(RockPaperScissors.RockPaperScissors__MoveAlreadyRevealed.selector);
    //     rps.revealMove(Move.Rock);
    //     vm.stopPrank();
    // }
    
    // function testNonPlayerCannotMakeMove() public {
    //     createGame();
    //     joinGame();
        
    //     address nonPlayer = makeAddr("nonPlayer");
    //     vm.startPrank(nonPlayer);
    //     vm.expectRevert(RockPaperScissors.RockPaperScissors__PlayerNotInGame.selector);
    //     rps.makeMove(Move.Rock);
    //     vm.stopPrank();
    // }

    // /*//////////////////////////////////////////////////////////////
    //                      EMERGENCY STOP TESTS
    // //////////////////////////////////////////////////////////////*/
    // function testEmergencyStop() public {
    //     createGame();
    //     joinGame();
        
    //     // Owner activates emergency stop
    //     vm.prank(owner);
    //     rps.setEmergencyStop(true);
        
    //     // Players should not be able to make moves
    //     vm.startPrank(player1);
    //     vm.expectRevert(RockPaperScissors.RockPaperScissors__EmergencyStop.selector);
    //     rps.makeMove(Move.Rock);
    //     vm.stopPrank();
        
    //     // Players should be refunded
    //     assertEq(mockToken.balanceOf(player1), 1000 ether, "Player1 should be refunded");
    //     assertEq(mockToken.balanceOf(PLAYER2), 1000 ether, "Player2 should be refunded");
    // }
    
    // function testDisableEmergencyStop() public {
    //     // Owner activates emergency stop
    //     vm.prank(owner);
    //     rps.setEmergencyStop(true);
        
    //     // Owner disables emergency stop
    //     vm.prank(owner);
    //     rps.setEmergencyStop(false);
        
    //     // Game should work again
    //     createGame();
    //     joinGame();
    //     commitMoves(Move.Rock, Move.Paper);
        
    //     vm.prank(player1);
    //     rps.revealMove(Move.Rock);
        
    //     vm.prank(PLAYER2);
    //     rps.revealMove(Move.Paper);
        
    //     // Game should complete normally
    //     uint256 expectedPrize = (2 * betAmount * 95) / 100;
    //     assertEq(mockToken.balanceOf(PLAYER2), 1000 ether - betAmount + expectedPrize, "Player2 should receive prize");
    // }

    // /*//////////////////////////////////////////////////////////////
    //                      ACCESS CONTROL TESTS
    // //////////////////////////////////////////////////////////////*/
    // function testOnlyOwnerCanSetEmergencyStop() public {
    //     vm.startPrank(player1);
    //     vm.expectRevert();  // Ownable error
    //     rps.setEmergencyStop(true);
    //     vm.stopPrank();
    // }
    
    // function testOnlyAutomationCanPerformUpkeep() public {
    //     vm.startPrank(player1);
    //     vm.expectRevert(RockPaperScissors.RockPaperScissors__NotAutomationRegistry.selector);
    //     rps.performUpkeep("");
    //     vm.stopPrank();
        
    //     // Owner can also perform upkeep
    //     vm.startPrank(owner);
    //     rps.performUpkeep("");
    //     vm.stopPrank();
    // }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        // vm.mockCall could be used here...
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(0, address(rps));

        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(rps));
    }
}