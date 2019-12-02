pragma solidity ^0.5.11;

contract Game {

    /* 
    https://emn178.github.io/online-tools/keccak_256.html for the keccak_256 
     input --> "0x485683dfd9290ce165e4a4dc07c331df3cac4b23398bd10f546b18e714ca5d2f" ---> Add 0x and quotes.
     input --> "$bet$decision$password$" (ex: "51hello") (bet in {1-9}, decision in {0,1} (0 = not attack, 1 = attack) , password is anything) 
    
    * Msg.value when AA_CommitDecision must be equal to bet in "$bet$decision$password$" (ex: "51hello" then msg.value = 5), if these values are not equal then player will not receive refunding nor price
    * Players that not attack also have to place a "lie bet" greater than the minimum in order to influence attackers (it would be returned at the end of the round)
    
    * Sybil attacks allow players to have very high bets (>9) and to add attackers, but they are not incentivized to do this because the high costs and that the win proportional to their bets  
    * Easy improvements: 
        * Allow multiple attacks for each player. This will incentivice cascade or bubble scenarios, and it will be interesting to analyse the strategies of players 
    */
    
    uint public costOfAttack   = 1 ether;               // Cost of attacking, will keep in the jackpot for next rounds ie: guarantees that jackpot never empty for future rounds
    uint public minimumAttack  = 1 ether;               // Minimum bet allowed
    uint minimumTheta          = 20;                    // Percentage of needed players to execute a successful attack
    uint public minimumPlayers = 0;                     // minimum amount of players needed to play 
    uint private Confirmed     = 0;                     // Players that have already confirmed
    uint public nbPlayers      = 0;                     // Number of Players is zero at the beginning
    uint public jackpot        = address(this).balance; // Remaining funds
    uint private nbAttackers   = 0;                     // Counts the attacks
    uint private unknownSeed   = 0;                     // Provides a seed for the random number  
    uint private totalBets     = 0;                     // Adds the bets of all attackers
    uint256 private T0         = 100000000000000;       // Aprox. time when minimum amount of players have commited plus the waiting time
    uint256 private T1         = 100000000000000;       // Aprox. time when minimum amount of players have commited plus the confirmation time  
    uint256 private dt         = 10 seconds;            // Waiting time, time available to add new players even though the minimum amount of players already commited
    uint256 private dt2        = 300 seconds;           // Time given to Confirm (usefull to stop stalling scenarios, makes sure the system changes if some player thinks it is stalled by confirming again)
    uint public Theta         = 101;                   // The fundamental, "Resistance of the system" ie: Percentage of attackers needed to have a succesfull attack
    
    
    modifier betHigherThanMinimumAttack{              // Requirement needed for playing (player's bet or "lie bet" must be higher than the minimum allowed)  
        require(msg.value >= minimumAttack);
        _;
    } 
    
    mapping(address => uint) private playerBet;                 // which player has how much ether in the jackpot
    mapping(address => uint) private playerStatus;              // to see which players decided to attack and which not
    mapping(address => uint) private playerCommit;              // follow if player has already commited, looks at the msg.value commited
    mapping(address => bytes32) private Decision;               // register the decisions of players 
    mapping(uint    => address payable) private playerAddress;  // register players address'
    
    event logStrUnStr(string,uint,string);                      // Usefull for the front-end build
    event logString(string);                                    // Usefull for the front-end build

    enum State {Active,Waiting,Close,Distribute,DistributeWaiting}    
    
    /*
    Active            ---> Players can place bets and commit
    Waiting           ---> Players can queep commiting even though the number of players is greater thn the minimum amount of players needed
    Close             ---> No commits are allowed and confirmation is available
    Distribute        ---> The stage where palyers can claim price or refunding (only one player needed to claim)
    DistributeWaiting ---> Use to avoid re-entry attacks
    */
    
    State public state;        // Allow everyone to see the actual state
    
    constructor() public {     // Start the game with active state
        state = State.Active;
    }

    function AA_CommitDecision(bytes32 _hashedBetDecisionPw) public payable betHigherThanMinimumAttack {  
        jackpot = address(this).balance;                         // Actualize jackpot
        if(state == State.Active || state == State.Waiting) {    // Check for correct state
            if(playerCommit[msg.sender] == 0) {                  // Check if a player has not already commited
                
                playerBet[msg.sender]    = 0;                    // Create Bet element
                Decision[msg.sender]     = _hashedBetDecisionPw; // Save the encrypted decision
                playerAddress[nbPlayers] = msg.sender;           // Save address of player
                playerCommit[msg.sender] = msg.value;            // Save bet of player
                playerStatus[msg.sender] = 0;                    // Save status of player ( status = 0 --> already commited)
                nbPlayers               += 1;                    // Register new player 
                
                if(nbPlayers >= minimumPlayers) {                // Check if registered players are greater than the minimum 
                    if (state == State.Active) {                 // Check that the registered amount of players has not been already met 
                        T0 = now + dt;                           // Define window of time for allowing new players 
                        T1 = now + dt + dt2;                     // Define window of time for confirmation
                        state = State.Waiting;                   // Start Waiting state
                        //emit logString('State is WAITING');
                        //emit logStrUnStr('Confirmation available in aprox.: ', dt, ' seconds !!!');
                    }
                    if (state == State.Waiting && now > T0) {    // Check if waiting time has already finished  
                        state = State.Close;                     // Start Confirmation stage
                    }
                }  
            }
        }
        
        // I would remove the following (adding noise to the system) and put the state as a public variable (we so incentivice not playing when you shouldn't) 
        if(state == State.Close || state == State.Distribute || state == State.DistributeWaiting || playerCommit[msg.sender] > 0) {  // Check if the player tried to commit in a wrong stage or already has a commit     
            msg.sender.transfer(msg.value);                                                                                          // Return the ether to the players 
        }                   
    }
    
    
    function AAA_Confirmation (string memory _publicBetDecisionPw) public {                       // If you don't put correct password then you will not recuperate your initial msg.value and will be set as a non attacker
        if (state == State.Close || now > T0) {                                                   // Check if Confirmation stage already began or waiting window ended
            state = State.Close;                                                                  // Change state to close in case that waiting window ended
            //emit logString('State is CLOSED');
            
            if (playerStatus[msg.sender] == 0 && playerCommit[msg.sender] > 0) {                  // Check for confirmation status and previous commited hash authenticity
                if (Decision[msg.sender] == keccak256(abi.encodePacked(_publicBetDecisionPw))) {  // Check for previous commited hash authenticity
                    bytes memory bytesBet = bytes(_publicBetDecisionPw);                          // Convert data 
                    
                    if (bytesBet[1] == "0" || bytesBet[1] == "1" || bytesBet[0] == "0" || bytesBet[0] == "1" || bytesBet[0] == "2" || bytesBet[0] == "3" || bytesBet[0] == "4" || bytesBet[0] == "5" || bytesBet[0] == "6" || bytesBet[0] == "7" || bytesBet[0] == "8" || bytesBet[0] == "9") { // Check correctness of input 
                        playerBet[msg.sender] = Element2Uint(bytesBet, 0);                        // Register confirmed bet 
                        uint AoN              = Element2Uint(bytesBet, 1);                        // Register confiremed decision Attack or not attack
                        unknownSeed          += playerBet[msg.sender] ^ (AoN + 1);                // Define new seed for random number generation
                        
                        if (playerBet[msg.sender] * 1 ether == playerCommit[msg.sender]) {        // Check that bet is really the value inserted on commit step 
                            if (bytesBet[1] == "1") {                                             // Check if decision is to attack
                                playerStatus[msg.sender] = 1;                                     // Confirm status of player to attacker
                                Confirmed               += 1;                                     // Add confirmed player
                            }
                            if (bytesBet[1] == "0") {                                             // Check if decision is to attack
                                playerStatus[msg.sender] = 2;                                     // Confirm status of player to defender
                                Confirmed               += 1;                                     // Add confirmed player
                            }
                        }
                    }
                } else {                                                                          // if authenticity fails 
                    Confirmed += 1;                                                               // Add confirmed player (but the status will not change and so will loose their bet or "false bet")
                }
            }             
            
            if (Confirmed >= nbPlayers || now > T1) {       // Check if all players have confirmed or if confirmation window has expired in orther to prevent stalting (it can be chequed by any player that thinks it should move on)
                state = State.Distribute;                   // Change stage to allow the claim of refund or prices
                //emit logString('State is DISTRIBUTE');
            }
            
        } else {
            emit logStrUnStr('Confirmation available in aprox.: ', T1 - now, ' seconds !!!'); // Usefull for front-end
        }
    }
    
    
    function AAAA_ClaimPayout() public payable {                // Any player can activate this, the first one is incentiviced by not paying cost of attack
        if(state == State.Distribute) {                         // Check for correct stage
            state = State.DistributeWaiting;                    // This solves the re-entrance attack problem !!!
            //emit logString('State is DISTRIBUTE_WAITING');
            
            if (Theta > 100) {
                Theta = uint(keccak256(abi.encodePacked(jackpot,unknownSeed,nbAttackers,now))) % 100;    // Calculate the minimum amount of attackers needed to make effective an attack 
            }
            
            for (uint i = 0; i < nbPlayers; i++) {              // Loop on players
                if (playerStatus[playerAddress[i]] == 1) {      // Check for attackers
                    nbAttackers += 1;                           // Add attackers to counter
                    totalBets   += playerBet[msg.sender];       // Add attacker's bet to the bet counter
                }
            }
            
            for (uint i = 0; i < nbPlayers; i++) {                                                                   // Loop on players
                if (playerStatus[playerAddress[i]] == 1) {                                                           // Check for attackers
                    if (nbAttackers * 100  > Theta * nbPlayers && nbAttackers * 100 > minimumTheta * nbPlayers) {    // Check that number of attackers is greater than the system resistance and the minimum required
                        uint amount = playerBet[playerAddress[i]] * address(this).balance / totalBets;               // Calculate the relative price of each player depending on their bets
                        if (playerAddress[i] == msg.sender) {                                                        // Filter the sender to give bigger price
                            require(amount <= address(this).balance);                                                // Check availability of funds in jackpot
                            playerAddress[i].transfer(amount);                                                       // Transfer price with incentivice to Claim, the first player to claim does not pay costOfAttack 
                            //emit logString('Transfer sent');
                        } else {                                                                                     // For every other player
                            require(amount - costOfAttack <= address(this).balance);                                 // Check availability of funds in jackpot
                            playerAddress[i].transfer(amount - costOfAttack);                                        // Transfer price with cost of attack
                            //emit logString('Transfer sent');
                        }
                    }
                } 
                if (playerStatus[playerAddress[i]] == 2) {                                                           // Check for defenders
                    require(playerBet[playerAddress[i]] * 1 ether <= address(this).balance);                         // Check availability of funds in jackpot
                    playerAddress[i].transfer(playerBet[playerAddress[i]] * 1 ether);                                // Refund "false bet"
                    //emit logString('Transfer sent');
                }
            }
            
            state = State.Active;                       // New round activated
            //emit logString('State is ACTIVE');
            
            for (uint i = 0; i < nbPlayers; i++) {      // Reset all parameters
                delete playerBet[playerAddress[i]]; 
                delete playerStatus[playerAddress[i]];
                delete playerCommit[playerAddress[i]];
                delete playerAddress[i];
            }
            
            
            nbPlayers   = 0;                            // Reset all parameters
            nbAttackers = 0;
            unknownSeed = 0;
            Confirmed   = 0;
            totalBets   = 0;
            jackpot     = address(this).balance; 
            Theta       = 101;
            T0          = 100000000000000;
            T1          = 100000000000000;
            dt          = 10;
            dt2         = 30;
            
        }
    }
    
    function Element2Uint(bytes memory a, uint _n) private pure returns(uint) {  // Practical type transformation  
        uint b;
        if (a[_n] == "0") b = 0;
        if (a[_n] == "1") b = 1;
        if (a[_n] == "2") b = 2;
        if (a[_n] == "3") b = 3;
        if (a[_n] == "4") b = 4;
        if (a[_n] == "5") b = 5;
        if (a[_n] == "6") b = 6;
        if (a[_n] == "7") b = 7;
        if (a[_n] == "8") b = 8;
        if (a[_n] == "9") b = 9;
        return b;
    }

    function A_DonateToJackpot() public payable {     // Function to donate ETH to the game (can be used by any player)
        jackpot = address(this).balance;
        emit logString('Thank you for your donation !!!');
    }
    
}
