// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
// import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {ConfirmedOwnerWithProposal} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwnerWithProposal.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts//utils/ReentrancyGuard.sol";

contract RockPaperScissors is VRFConsumerBaseV2Plus, ReentrancyGuard {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RockPaperScissors__GameAlreadyClosed();
    error RockPaperScissors__BetAmountsMustBeGreater();
    error RockPaperScissors__BetAmountsMustBeSame();
    error RockPaperScissors__CannotJoinYourOwnGame();
    error RockPaperScissors__JoinTimeoutReached();
    error RockPaperScissors__BothPlayersMustMakeMove();
    error RockPaperScissors__PlayerNotInGame();
    error RockPaperScissors__InvalidMove();
    error RockPaperScissors__SaltNotSetYet();
    error RockPaperScissors__MoveAlreadyCommitted();
    error RockPaperScissors__MoveAlreadyRevealed();
    error RockPaperScissors__NotTheOwner();
    // error RockPaperScissors__EmergencyStop();
    error RockPaperScissors__InvalidGameState();
    error RockPaperScissors__TokenTransferFailed();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum GameState {
        Open,       // Game created, waiting for player2
        Ready,      // Both players joined, waiting for commitments
        Committed,  // Both players committed, waiting for reveals
        Revealed,   // Both players revealed, result determined
        Finished     // Game finished
    }
    
    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

    struct GameDetails {
        uint256 createdAt;       // When game was created
        uint256 lastActionAt;    // Timestamp of last action (used for timeouts)
        uint256 betAmount;       // Amount bet by each player
    }
    
    struct Player {
        address playerAddress;
        // uint256 salt;            // Random salt from VRF
        bool saltReceived;       // Flag to check if salt has been received
        Move move;               // Player's move (set during reveal)
        bytes32 hashedMove;      // Commitment hash
        bool hasRevealed;        // Whether player has revealed their move
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Chainlink VRF variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    bytes32 private immutable i_gasLane;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address private immutable i_automationRegistry;

    // Constants
    uint256 public constant JOIN_TIMEOUT = 10 minutes;
    uint256 public constant COMMIT_TIMEOUT = 5 minutes;
    uint256 public constant REVEAL_TIMEOUT = 3 minutes;
    uint256 public constant GAME_FEE_RATE = 95;
    uint256 public constant GAME_FEE_RATE_DENOMINATOR = 100;
    
    // Mappings to store player data
    mapping(address => Player) private players;
    mapping(address => uint256) private playerSalts;
    mapping(uint256 => address) private requestIdToPlayer;
    mapping(address => uint256) private playerToRequestId;

    // Array to store request ID
    // uint256[] private requestIds;
    
    // Game information
    GameState private gameState;
    GameDetails private gameDetails;
    
    // Players
    address public player1;
    address public player2;

    // IERC20 token used
    // IERC20 public token;
    
    // Emergency stop
    // bool public emergencyStop;

    // Ownership
    // address private _owner;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event GameStateChanged(GameState indexed newState);
    event PlayerCreatedGame(address indexed player);
    event PlayerJoinedGame(address indexed player);
    event GameDetailsUpdated(uint256 createdAt, uint256 betAmount, uint256 lastActionAt);
    event PlayerSaltReceived(address indexed player);
    event PlayerMadeMove(address indexed player);
    event PlayerRevealedMove(address indexed player, Move move);
    event GameResult(address winner, uint256 prize);
    event EmergencyStopActivated(bool active);

    event RequestSent(uint256 requestId, address player); //////
    event RandomFulfilled(uint256 requestId, address player, uint256 randomValue);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
        // address _tokenAddress
        // address _automationRegistry
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        gameState = GameState.Open;
        // i_automationRegistry = _automationRegistry;
        // token = IERC20(_tokenAddress);
    }

    modifier onlyPlayer() {
        if (msg.sender != player1 && msg.sender != player2) {
            revert RockPaperScissors__PlayerNotInGame();
        }
        _;
    }

    // modifier onlyOwner() {
    //     if (msg.sender != _owner) {
    //         revert RockPaperScissors__NotTheOwner();
    //     }
    //     _;
    // }
    
    // modifier() {
    //     if (emergencyStop) {
    //         revert RockPaperScissors__EmergencyStop();
    //     }
    //     _;
    // }
    
    // modifier() {
    //     if (msg.sender != i_automationRegistry && msg.sender != owner()) {
    //         revert RockPaperScissors__NotAutomationRegistry();
    //     }
    //     _;
    // }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function createGame() external payable nonReentrant {
        if (gameState != GameState.Open && gameState != GameState.Finished) {
            revert RockPaperScissors__GameAlreadyClosed();
        }
        /**
         * @dev The player must send the bet amount in the transaction.
         * @notice using chainlink price feed to use dollar peg could be considered
         */
        if (msg.value < 0.01 ether) { 
            revert RockPaperScissors__BetAmountsMustBeGreater();
        }
 
        // If game is in Finished state, reset it before creating a new game
        if (gameState == GameState.Finished) {
            _resetGame();
        }

        gameDetails = GameDetails({
            createdAt: block.timestamp,
            lastActionAt: block.timestamp,
            betAmount: msg.value
        });
        
        players[msg.sender] = Player({
            playerAddress: msg.sender,
            // salt: 0,
            saltReceived: false,
            move: Move.None,
            hashedMove: bytes32(0),
            hasRevealed: false
        });
        uint256 requestId = requestRandomSalt(msg.sender);
        requestIdToPlayer[requestId] = msg.sender;
        
        player1 = msg.sender;
        gameState = GameState.Open;

        emit GameStateChanged(GameState.Open);
        emit PlayerCreatedGame(msg.sender);
        emit GameDetailsUpdated(gameDetails.createdAt, gameDetails.betAmount, gameDetails.lastActionAt);
    }

    function joinGame() external payable nonReentrant {
        if (gameState != GameState.Open) {
            revert RockPaperScissors__GameAlreadyClosed();
        }
        if (player1 == msg.sender) {
            revert RockPaperScissors__CannotJoinYourOwnGame();
        }
        // if (block.timestamp > gameDetails.lastActionAt + JOIN_TIMEOUT) {
        //     revert RockPaperScissors__JoinTimeoutReached();
        // }

        if (msg.value != gameDetails.betAmount) {
            revert RockPaperScissors__BetAmountsMustBeSame();
        }

        gameDetails.lastActionAt = block.timestamp;
        
        players[msg.sender] = Player({
            playerAddress: msg.sender,
            // salt: 0,
            saltReceived: false,
            move: Move.None,
            hashedMove: bytes32(0),
            hasRevealed: false
        });
        requestRandomSalt(msg.sender);
        // requestIdToPlayer[requestId] = msg.sender;
        
        player2 = msg.sender;
        gameState = GameState.Ready;

        emit GameStateChanged(GameState.Ready);
        emit PlayerJoinedGame(msg.sender);
        emit GameDetailsUpdated(gameDetails.createdAt, gameDetails.betAmount, gameDetails.lastActionAt);
    }

    function makeMove(Move move) external onlyPlayer nonReentrant {
        if (gameState != GameState.Ready) {
            revert RockPaperScissors__InvalidGameState();
        }
        /**
         * @dev Ensure the player has received the random salt
         */
        if (!players[msg.sender].saltReceived) {
            revert RockPaperScissors__SaltNotSetYet();
        }
        if (players[msg.sender].hashedMove != bytes32(0)) {
            revert RockPaperScissors__MoveAlreadyCommitted();
        }
        if (move < Move.Rock || move > Move.Scissors) {
            revert RockPaperScissors__InvalidMove();
        }
        
        bytes32 hashedMove = _generateMoveHash(move, playerSalts[msg.sender]);
        players[msg.sender].hashedMove = hashedMove;

        // Check if both players have committed their moves
        if (msg.sender == player1 && players[player2].hashedMove != bytes32(0)) {
            gameState = GameState.Committed;
            // Update last action time
            gameDetails.lastActionAt = block.timestamp;
            emit GameStateChanged(GameState.Committed);
        }
        if (msg.sender == player2 && players[player1].hashedMove != bytes32(0)) {
            gameState = GameState.Committed;
            // Update last action time
            gameDetails.lastActionAt = block.timestamp;
            emit GameStateChanged(GameState.Committed);
        }
        emit PlayerMadeMove(msg.sender);
    } 
    
    function revealMove(Move move) external onlyPlayer nonReentrant {
        if (gameState != GameState.Committed) {
            revert RockPaperScissors__InvalidGameState();
        }
        if (players[msg.sender].hasRevealed) {
            revert RockPaperScissors__MoveAlreadyRevealed();
        }
        if (move < Move.Rock || move > Move.Scissors) {
            revert RockPaperScissors__InvalidMove();
        }
        
        // Verify the move matches the commitment
        bytes32 computedHash = keccak256(abi.encodePacked(move, playerSalts[msg.sender]));
        if (players[msg.sender].hashedMove != computedHash) {
            revert RockPaperScissors__InvalidMove(); // 🔴🟠🟡 not yet tested
        }

        players[msg.sender].move = move;
        players[msg.sender].hasRevealed = true;

        // Check if both players have revealed their moves
        if (msg.sender == player1 && players[player2].hasRevealed) {
            gameState = GameState.Revealed;
            // Update last action time
            gameDetails.lastActionAt = block.timestamp;
            emit GameStateChanged(GameState.Revealed);
            _determineWinner();
        }
        if (msg.sender == player2 && players[player1].hasRevealed) {
            gameState = GameState.Revealed;
            // Update last action time
            gameDetails.lastActionAt = block.timestamp;
            emit GameStateChanged(GameState.Revealed);
            _determineWinner();
        }
        emit PlayerRevealedMove(msg.sender, move);
    }
    
    // function setEmergencyStop(bool _stop) external onlyOwner {
    //     emergencyStop = _stop;
    //     emit EmergencyStopActivated(_stop);
        
    //     // If stopping in emergency, refund players if a game is in progress
    //     if (_stop && gameState != GameState.Open && gameState != GameState.Closed) {
    //         if (player1 != address(0)) {
    //             _refundPlayer(player1, gameDetails.betAmount);
    //         }
    //         if (player2 != address(0)) {
    //             _refundPlayer(player2, gameDetails.betAmount);
    //         }
    //         _resetGame();
    //     }
    // }

    // function transferOwnership(address newOwner) public override(ConfirmedOwnerWithProposal, Ownable) onlyOwner {
    //     _transferOwnership(newOwner);
    // }

    // function _transferOwnership(address newOwner) internal override(ConfirmedOwnerWithProposal, Ownable) {
    //     address oldOwner = _owner;
    //     _owner = newOwner;
    // }
    
    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _generateMoveHash(Move move, uint256 salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(move, salt));
    }

    function _resetGame() internal {
        // Clear player salts from the private mapping
        delete playerSalts[player1];
        delete playerSalts[player2];

        // Clear request mappings
        delete playerToRequestId[player1];
        delete playerToRequestId[player2];
        uint256 requestId1 = playerToRequestId[player1];
        uint256 requestId2 = playerToRequestId[player2];
        delete requestIdToPlayer[requestId1];
        delete requestIdToPlayer[requestId2];

        // Clear player data
        delete players[player1];
        delete players[player2];
        player1 = address(0);
        player2 = address(0);
        

        // Clear game details
        delete gameDetails;
        gameState = GameState.Open; 

        emit GameStateChanged(GameState.Open);
    }

    function _refundPlayer(address player, uint256 amount) internal {
        if (amount > 0) {
            (bool success,) = payable(player).call{value: amount}("");
            if (!success) {
                revert RockPaperScissors__TokenTransferFailed();
            }
        }
    }

    function _determineWinner() internal {
        uint256 totalPrize = (gameDetails.betAmount * 2 * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR;
        address winner;
        
        // Compare moves to determine winner
        if (players[player1].move == players[player2].move) {
            // Draw - refund both players
            _refundPlayer(player1, gameDetails.betAmount);
            _refundPlayer(player2, gameDetails.betAmount);
            winner = address(0); // Draw
        } else if (
            (players[player1].move == Move.Rock && players[player2].move == Move.Scissors) ||
            (players[player1].move == Move.Paper && players[player2].move == Move.Rock) ||
            (players[player1].move == Move.Scissors && players[player2].move == Move.Paper)
        ) {
            // Player 1 wins
            _refundPlayer(player1, totalPrize);
            winner = player1;
        } else {
            // Player 2 wins
            _refundPlayer(player2, totalPrize);
            winner = player2;
        }
        gameState = GameState.Finished;
        emit GameResult(winner, totalPrize);
        emit GameStateChanged(GameState.Finished);
    }

    // function _calculateMove(Move move1, Move move2) internal returns ()

    /*//////////////////////////////////////////////////////////////
                               CHAINLINK
    //////////////////////////////////////////////////////////////*/
    function requestRandomSalt(address player) public returns(uint256) { // 🔴🟠🟡 vulnerability issue: can anybody calls this func
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_gasLane,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });   
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        requestIdToPlayer[requestId] = player;
        playerToRequestId[player] = requestId;

        return requestId;
   }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        address player = requestIdToPlayer[_requestId];
        if (player != address(0)) {
            uint256 randomNumber = _randomWords[0];
            playerSalts[player] = randomNumber;
            players[player].saltReceived = true;
                
            emit PlayerSaltReceived(player);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              AUTOMATION
    //////////////////////////////////////////////////////////////*/
    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded, bytes memory performData) {
        // Initialize with default values
        upkeepNeeded = false;
        uint8 actionType = 0;
        
        // if (emergencyStop) {
        //     return (false, abi.encode(0));
        // }
        
        if (gameState == GameState.Open && player1 != address(0)) {
            // Check if join timeout has passed -> refund to player1
            if (block.timestamp > gameDetails.lastActionAt + JOIN_TIMEOUT) {
                upkeepNeeded = true;
                actionType = 1; // Join timeout reached
            }
        } else if (gameState == GameState.Ready) {
            // Check if commit timeout has passed
            if (block.timestamp > gameDetails.lastActionAt + COMMIT_TIMEOUT) {
                upkeepNeeded = true;
                actionType = 2; // Commit timeout reached
            }
        } else if (gameState == GameState.Committed) {
            // Check if reveal timeout has passed
            if (block.timestamp > gameDetails.lastActionAt + REVEAL_TIMEOUT) {
                upkeepNeeded = true;
                actionType = 3; // Reveal timeout reached
            }
        } else if (gameState == GameState.Revealed) {
            // Game completed, results determined, just needs cleanup
            upkeepNeeded = true;
            actionType = 4; // Game completed
        }
        
        performData = abi.encode(actionType);
        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external {
        uint8 actionType = abi.decode(performData, (uint8));
        
        if (actionType == 1) {
            // Join timeout reached, refund player1
            _refundPlayer(player1, gameDetails.betAmount);
            _resetGame();
        } else if (actionType == 2) {
            // Commit timeout reached, handle players who didn't commit
            _handleCommitTimeout();
        } else if (actionType == 3) {
            // Reveal timeout reached, handle players who didn't reveal
            _handleRevealTimeout();
        } else if (actionType == 4) {
            // Game completed, reset for next game
            _resetGame();
        }
    }
    
    function _handleCommitTimeout() internal {
        if (players[player1].hashedMove == bytes32(0) && players[player2].hashedMove == bytes32(0)) {
            // Both players failed to commit, refund both
            _refundPlayer(player1, gameDetails.betAmount);
            _refundPlayer(player2, gameDetails.betAmount);
        } else if (players[player1].hashedMove == bytes32(0)) {
            // Player 1 failed to commit, player 2 wins
            uint256 totalPrize = (gameDetails.betAmount * 2 * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR;
            _refundPlayer(player2, totalPrize);
            emit GameResult(player2, totalPrize);
        } else if (players[player2].hashedMove == bytes32(0)) {
            // Player 2 failed to commit, player 1 wins
            uint256 totalPrize = (gameDetails.betAmount * 2 * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR;
            _refundPlayer(player1, totalPrize);
            emit GameResult(player1, totalPrize);
        }
        
        _resetGame();
    }
    
    function _handleRevealTimeout() internal {
        if (!players[player1].hasRevealed && !players[player2].hasRevealed) {
            // Both players failed to reveal, refund both
            _refundPlayer(player1, gameDetails.betAmount);
            _refundPlayer(player2, gameDetails.betAmount);
            emit GameResult(address(0), 0); // Draw
        } else if (!players[player1].hasRevealed) {
            // Player 1 failed to reveal, player 2 wins
            uint256 totalPrize = (gameDetails.betAmount * 2 * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR;
            _refundPlayer(player2, totalPrize);
            emit GameResult(player2, totalPrize);
        } else if (!players[player2].hasRevealed) {
            // Player 2 failed to reveal, player 1 wins
            uint256 totalPrize = (gameDetails.betAmount * 2 * GAME_FEE_RATE) / GAME_FEE_RATE_DENOMINATOR;
            _refundPlayer(player1, totalPrize);
            emit GameResult(player1, totalPrize);
        }
        
        _resetGame();
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL & PUBLIC VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getPlayer1() external view returns (address) {
        return player1;
    }

    function getPlayer2() external view returns (address) {
        return player2;
    }

    // function owner() public view override returns (address) {
    //     return _owner;
    // }

    function getGameState() external view returns (GameState) {
        return gameState;
    }

    function getGameDetails() external view returns (GameDetails memory) {
        return gameDetails;
    }

    function getPlayerToRequestId(address player) external view returns (uint256) {
        return playerToRequestId[player];
    }
    
    function getPlayerDetails(address player) external view returns (Player memory) {
        return players[player];
    }
    
    function getPlayerSaltStatus(address player) external view returns (bool) {
        return players[player].saltReceived;
    }
    
    function getPlayerCommitStatus(address player) external view returns (bool) {
        return players[player].hashedMove != bytes32(0);
    }
    
    function getPlayerRevealStatus(address player) external view returns (bool) {
        return players[player].hasRevealed;
    }

    // function getDeterminedWinner(Move move1, Move move2) external returns (address) {
    //     return _determineWinner(move1, move2);
    // }
}