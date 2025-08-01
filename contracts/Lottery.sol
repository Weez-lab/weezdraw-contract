// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


import "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Lottery is VRFV2PlusWrapperConsumerBase, ConfirmedOwner {
    // VRF Wrapper and subscription
    uint32 private s_callbackGasLimit = 3000000;
    uint16 private s_requestConfirmations = 3;
    uint32 private s_numWords = 1;
  
    // LINK token address
    address private  admin;
    address private immutable linkTokenAddress;
  
    struct Draw {
        uint256 drawId;
        uint256 endDate;
        address[] participants;
        bool drawCompleted;
        bool randomnessRequested;
        address winner;
    }
    uint256 private drawCounter;
    mapping(uint256 => Draw) private draws;

    // VRF request status
    struct RequestStatus {
        uint256 paid; // Amount paid in LINK or native tokens
        bool fulfilled; // Whether the request has been fulfilled
        uint256[] randomWords; // Array of random words
    }
    mapping(uint256 => RequestStatus) public s_requests; // requestId -> RequestStatus
    uint256[] public requestIds; // Array of request IDs
    uint256 public lastRequestId; // Last request ID
    mapping(uint256 => uint256) private requestIdToDrawId; // requestId -> drawId
    // Events
    event LotteryDrawCreated(uint256 drawId, uint256 endDate);
    event TicketAdded(uint256 drawId, address participant);
    event WinnerSelected(uint256 drawId, address winner);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);
    event RequestSent(uint256 requestId, uint32 numWords, uint256 paid);

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier beforeEndDate(uint256 drawId) {
        require(draws[drawId].endDate > block.timestamp, "Lottery draw has ended");
        _;
    }

    modifier afterEndDate(uint256 drawId) {
        require(draws[drawId].endDate <= block.timestamp, "Lottery draw has not ended yet");
        _;
    }

    modifier drawExists(uint256 drawId) {
        require(draws[drawId].drawId != 0, "Draw does not exist");
        _;
    }

    function setCallbackGasLimit(uint32 gasLimit) external onlyOwner {
        s_callbackGasLimit = gasLimit;
    }
 
    function setRequestConfirmations(uint16 confirmations) external onlyOwner {
        require(confirmations >= 1 && confirmations <= 200, "Invalid confirmation count");
        s_requestConfirmations = confirmations;
    }

    function setNumWords(uint32 numWords) external onlyOwner {
        require(numWords > 0 && numWords <= 500, "Invalid numWords");
        s_numWords = numWords;
    }

      // @notice Set a new admin address (only callable by owner)
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid address");
        admin = newAdmin;
    }
     // ✅ Getters to support tests
    function getCallbackGasLimit() external view returns (uint32) {
        return s_callbackGasLimit;
    }

    function getMinConfirmations() external view returns (uint16) {
        return s_requestConfirmations;
    }

    function getNumWords() external view returns (uint32) {
        return s_numWords;
    }
    constructor(address wrapperAddress, address _linkTokenAddress)
        VRFV2PlusWrapperConsumerBase(wrapperAddress)
        
        ConfirmedOwner(msg.sender)
    {
        require(_linkTokenAddress != address(0), "Invalid LINK token address");
        admin = msg.sender;
        drawCounter = 1; // Start draw IDs from 1
        linkTokenAddress = _linkTokenAddress; // Store LINK token address
    }

    // Create a new draw
    function createDraw(uint256 _endDate) external onlyAdmin {
        require(_endDate > block.timestamp, "End date must be in the future");

        uint256 drawId = drawCounter++;
        draws[drawId] = Draw({
            drawId: drawId,
            endDate: _endDate,
            participants: new address[](0),
            drawCompleted: false,
            randomnessRequested: false,
            winner: address(0)
        });

        emit LotteryDrawCreated(drawId, _endDate);
    }
    

    // Add a participant to a draw
    function addParticipant(uint256 drawId, address participant) external onlyAdmin drawExists(drawId) beforeEndDate(drawId) {
        require(!draws[drawId].randomnessRequested, "Randomness already requested");
        require(participant != address(0), "Invalid participant address");
        for (uint i = 0; i < draws[drawId].participants.length; i++) {
         require(draws[drawId].participants[i] != participant, "Participant already added");
        }
        draws[drawId].participants.push(participant);
        emit TicketAdded(drawId, participant);
    }

    // Request a random winner for a draw
    function requestRandomWinner(uint256 drawId, bool nativePayment) external onlyAdmin drawExists(drawId) afterEndDate(drawId)  {

        require(draws[drawId].participants.length > 0, "No participants in draw");
        // Request random words using the direct funding method
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
        );

        uint256 estimatedCost = i_vrfV2PlusWrapper.calculateRequestPrice(
        s_callbackGasLimit,
        s_numWords
        );
     
        uint256 requestId;
        uint256 reqPrice;

        if (nativePayment) {
            // Pay in native tokens
             require(address(this).balance >= estimatedCost, "Insufficient native token balance");
            (requestId, reqPrice) = requestRandomnessPayInNative(
                s_callbackGasLimit,
                s_requestConfirmations,
                s_numWords,
                extraArgs
            );
        } else {
            // Pay in LINK
            require(i_linkToken.balanceOf(address(this)) >= estimatedCost, "Insufficient LINK balance");
            (requestId, reqPrice) = requestRandomness(
                s_callbackGasLimit,
                s_requestConfirmations,
                s_numWords,
                extraArgs
            );
        }

        // Store the request details
        s_requests[requestId] = RequestStatus({
            paid: reqPrice,
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIdToDrawId[requestId] = drawId; // Fixing MRM
        requestIds.push(requestId);
        lastRequestId = requestId;
        draws[drawId].randomnessRequested = true;

        emit RequestSent(requestId, s_numWords,reqPrice);
    
    }
    


    // Callback function for VRF
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        // Retrieve the drawId associated with the requestId
        uint256 drawId = requestIdToDrawId[_requestId];
        require(!draws[drawId].drawCompleted, "Draw already completed");

        //require(!draws[drawId].drawCompleted, "Draw already completed");
        uint256 winnerIndex = _randomWords[0] % draws[drawId].participants.length;
        address winner = draws[drawId].participants[winnerIndex];
        draws[drawId].winner = winner;
        draws[drawId].drawCompleted = true;
        
        RequestStatus storage request = s_requests[_requestId];
        require(request.paid > 0, "request not found");
        request.fulfilled = true;
        request.randomWords = _randomWords; 
        emit WinnerSelected(drawId, winner);
        emit RequestFulfilled(_requestId, _randomWords, s_requests[_requestId].paid);
    }
 
    // Get draw details
    function getDrawDetails(uint256 drawId) external view drawExists(drawId) returns (
        uint256 endDate,
        address[] memory participants,
        bool drawCompleted,
        address winner
    ) {
        Draw memory draw = draws[drawId];
        return (draw.endDate, draw.participants, draw.drawCompleted, draw.winner);
    }

    // Get the current draw ID
    function getCurrentDrawId() external view returns (uint256) {
        return drawCounter - 1;
    }

    // Get request status
    function getRequestStatus(uint256 requestId) external view returns (
        uint256 paid,
        bool fulfilled,
        uint256[] memory randomWords
    ) {
        require(s_requests[requestId].paid > 0, "Request not found");
        RequestStatus memory request = s_requests[requestId];
        return (request.paid, request.fulfilled, request.randomWords);
    }

    function getEstimatedRequestPrice(bool nativePayment) public view returns (uint256) {
        // Encode nativePayment flag as required by your wrapper
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
        );

        // Call calculateRequestPrice with current settings and extraArgs if supported
        // If your wrapper doesn't accept extraArgs, remove it from call
        uint256 price = i_vrfV2PlusWrapper.calculateRequestPrice(
            s_callbackGasLimit,
            s_numWords
            // , extraArgs  // Uncomment if your wrapper supports this argument
        );

        return price;
    }
    function withdrawNative(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Native withdrawal failed");
    }   
    function withdrawLink(uint256 amount) external onlyOwner {
        uint256 contractBalance = i_linkToken.balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient LINK balance");
        bool success = i_linkToken.transfer(msg.sender, amount);
        require(success, "LINK withdrawal failed");
    }
    // Receive function to accept native tokens
    receive() external payable {}

}
