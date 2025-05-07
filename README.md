# 🪨📄✂️ Rock Paper Scissors — On-Chain with Chainlink VRF

A fully decentralized, provably fair Rock-Paper-Scissors game built with Solidity and Chainlink VRFv2+.
This game leverages Chainlink's Verifiable Random Function (VRF) to create unbiased gameplay where even the salt used to hash player moves is unpredictable.

---

## 🚀 Features

* 🔐 **Commit-Reveal Scheme**: Ensures players can't change their moves after committing.
* 🎲 **Chainlink VRF Integration**: Provides verifiable random salts to ensure fairness.
* ⛽ **Non-reentrancy Protection**: Safeguards against reentrancy attacks.
* ⏳ **Timeout Logic Ready**: Time-based game phases ready for Automation.
* 💰 **Native ETH Betting**: Players stake ETH, winner takes all minus small fee.

---

## 📦 Tech Stack

* **Solidity v0.8.24**
* **Chainlink VRFv2+**
* **OpenZeppelin ReentrancyGuard**

---

## 🕹️ How the Game Works

### 🧱 Step 1: Create Game

* Player 1 deploys a new game instance with an ETH bet.
* A random salt is requested from Chainlink VRF for Player 1.

### ➕ Step 2: Join Game

* Player 2 joins with the same ETH amount.
* Chainlink VRF generates salt for Player 2.

### 🎭 Step 3: Commit Moves

* Both players use their private move + salt to generate a commitment hash.
* The contract records the commitment.

### 🔍 Step 4: Reveal Moves

* Players reveal their move along with their salt.
* The contract checks if the revealed move matches the original commitment.

### 🏆 Step 5: Determine Winner

* Rock beats Scissors, Scissors beats Paper, Paper beats Rock.
* Winner receives 95% of the total bet (5% fee retained).

---

## 📚 Example Commit Flow

```solidity
bytes32 hashedMove = keccak256(abi.encodePacked(Move.Rock, playerSalt));
```

To reveal, the player calls:

```solidity
revealMove(Move.Rock);
```

---

## ⚠️ Safeguards

* **Same Bet Amount Check**
* **No Self-Join**
* **Only Players Can Interact**
* **Move Validation**
* **Commit/Reveal Only Once**
* **Game State Machine**

---

## 🔮 Chainlink VRF Integration

Each player receives a secure, verifiable random number (salt) from Chainlink VRF, ensuring:

* No one can predict or manipulate moves.
* Commitment hashes are truly private until reveal.

```solidity
function requestRandomSalt(address player) private returns (uint256 requestId);
```

---

## 📄 Game States

```solidity
enum GameState {
    Open,       // Game created, waiting for second player
    Ready,      // Both players joined
    Committed,  // Moves committed
    Revealed,   // Moves revealed
    Finished    // Game resolved
}
```

---

## 🛠️ Future Improvements

* [ ] Allow ERC20 token betting
* [ ] Enable multi-game matchmaking
* [ ] Add frontend with React + Ethers.js

---

## 🧠 Developer Notes

This contract follows a strong modular pattern and adheres to best practices:

* Gas-optimized enums and error messages
* Only essential storage and memory used
* Events allow easy off-chain tracking

---

## 📬 Contact

Made with ❤️ by a Solidity enthusiast. Contributions welcome!

---

## 📜 License

[MIT](./LICENSE)
