// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;


import "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
contract Lottery is VRFV2PlusWrapperConsumerBase, ConfirmedOwner {
    // VRF Wrapper and subscription
    uint32 private s_callbackGasLimit = 3000000;
    uint16 private s_requestConfirmations = 3;
    uint32 private s_numWords = 1;
event RequestSent(uint256 requestId, uint32 numWords, uint256 paid);
   
    // LINK token address
    address private linkTokenAddress;

    // Lottery state
    address private admin;
    struct Draw {
        uint256 drawId;
        uint256 endDate;
        address[] participants;
        bool drawCompleted;
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
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);

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

    constructor(address wrapperAddress, address _linkTokenAddress)
        VRFV2PlusWrapperConsumerBase(wrapperAddress)
        
        ConfirmedOwner(msg.sender)
    {
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
            winner: address(0)
        });

        emit LotteryDrawCreated(drawId, _endDate);
    }
    

    // Add a participant to a draw
    function addParticipant(uint256 drawId, address participant) external onlyAdmin drawExists(drawId) beforeEndDate(drawId) {
        draws[drawId].participants.push(participant);
        emit TicketAdded(drawId, participant);
    }

    // Request a random winner for a draw
    function requestRandomWinner(uint256 drawId, bool nativePayment) external onlyAdmin drawExists(drawId)  {
        require(draws[drawId].participants.length > 0, "No participants in draw");
        // Request random words using the direct funding method
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
        );
        uint256 requestId;
        uint256 reqPrice;

        if (nativePayment) {
            // Pay in native tokens
            (requestId, reqPrice) = requestRandomnessPayInNative(
                s_callbackGasLimit,
                s_requestConfirmations,
                s_numWords,
                extraArgs
            );
        } else {
            // Pay in LINK
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

        emit RequestSent(requestId, s_numWords);
    
    }
    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    // The default is 3, but you can set this higher.
    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFV2Wrapper.getConfig().maxNumWords.
    function requestRandomWords(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 drawId // Add drawId as a parameter
    ) external onlyOwner drawExists(drawId) returns (uint256) {
        require(!draws[drawId].drawCompleted, "Draw already completed");
        require(draws[drawId].participants.length > 0, "No participants in draw");
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
        );

        (uint256 requestId, uint256 reqPrice) = requestRandomness(
            _callbackGasLimit,
            _requestConfirmations,
            _numWords,
            extraArgs
        );
        
        s_requests[requestId] = RequestStatus({
            paid: reqPrice,
            randomWords: new uint256[](0),
            fulfilled: false
        });
         // Store the drawId associated with the requestId
        requestIdToDrawId[requestId] = drawId;

        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, _numWords, reqPrice);
        return requestId;
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

    // Receive function to accept native tokens
    receive() external payable {}
}