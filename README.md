The 
Lottery
 contract is a decentralized Ethereum-based application designed to manage fair and transparent lottery draws. By integrating Chainlink's Verifiable Random Function (VRF), it ensures cryptographically secure random winner selection. Administered by a designated owner, the contract supports creating draws, adding participants, and concluding with a randomly selected winner. It offers flexible payment options (LINK or native tokens) for VRF requests and incorporates robust security measures, such as access controls and state validation, to maintain integrity. Detailed tracking of draws and VRF requests enhances auditability and trust.

Randomness Request Functionality
The contract provides two functions, 
requestRandomWinner
 and 
requestRandomWords
, allowing the admin to initiate Chainlink VRF requests for random number generation. The 
requestRandomWinner
 function is tailored for lottery draws, enabling payment in either LINK or native tokens and linking the request to a specific draw. The 
requestRandomWords
 function offers a more general interface for requesting randomness, primarily for admin use. Both functions configure request parameters, such as gas limits and confirmation requirements, and log the request details via events, ensuring transparency and traceability.

Fulfillment and Winner Selection
The 
fulfillRandomWords
 function processes the random number provided by Chainlink VRF, mapping it to the relevant lottery draw. It selects the winner by using the random number to index into the draw’s participant list, ensuring a fair and unbiased outcome. The draw is then marked as complete, with the winner’s address recorded. Events are emitted to log the winner and fulfillment details, providing a transparent and verifiable record of the lottery’s conclusion.
