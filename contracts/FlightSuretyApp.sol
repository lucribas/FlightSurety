pragma solidity >=0.4.24 <0.6.0;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)
    using SafeMath for uint256;

    FlightSuretyData flightSuretyData; // Instance of FlightSuretyData

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // ----------------
    // Contract
    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    // ----------------
    // Flight

    // Flight status codes
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    uint256 constant M = 4; // Number of required keys for tx
    bool private vote_status = false;

    // ----------------
    // Oracle

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 2;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }
    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event RegisterAirline(address account);
    event PurchaseInsurance(address airline, address sender, uint256 amount);
    event CreditInsurees(address airline, address passenger, uint256 credit);
    event FundedLines(address funded, uint256 value);
    event Withdraw(address sender, uint256 amount);
    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );
    event SubmitOracleResponse(
        uint8 indexes,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    );
    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );
    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );


    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address dataContract) public {
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContract);
        flightSuretyData.registerAirline(contractOwner, true);

        emit RegisterAirline(contractOwner);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool) {
        return operational;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *
     */

    function registerAirline(address airline)
        external
        requireIsOperational
        returns (bool, bool)
    {
        require(airline != address(0), "'account' must be a valid address.");
        require(
            !flightSuretyData.getAirlineRegistrationStatus(airline),
            "Airline is already registered"
        );
        require(
            flightSuretyData.getAirlineOperatingStatus(msg.sender),
            "Caller airline is not operational"
        );

        uint256 multicall_Length = flightSuretyData.multiCallsLength();

        if (multicall_Length < M) {
            // Register airline directly in this case
            flightSuretyData.registerAirline(airline, false);
            emit RegisterAirline(airline);
            return (true, false); // Registered without a vote
        } else {
            if (vote_status) {
                uint256 voteCount = flightSuretyData.getVoteCounter(airline);

                if (voteCount >= multicall_Length / 2) {
                    // Airline has been voted in
                    flightSuretyData.registerAirline(airline, false);

                    vote_status = false;
                    flightSuretyData.resetVoteCounter(airline);

                    emit RegisterAirline(airline);
                    return (true, true);
                } else {
                    // Airline has been voted out
                    flightSuretyData.resetVoteCounter(airline);
                    return (false, true);
                }
            } else {
                // Requesting for a vote
                return (false, false);
            }
        }
    }

    /**
     * @dev Approve registration of fifth and subsequent airlines
     *
     */

    function approveAirlineRegistration(address airline, bool airline_vote)
        public
        requireIsOperational
    {
        require(
            !flightSuretyData.getAirlineRegistrationStatus(airline),
            "airline already registered"
        );
        require(
            flightSuretyData.getAirlineOperatingStatus(msg.sender),
            "airline not operational"
        );

        if (airline_vote == true) {
            // Check and avoid duplicate vote for the same airline
            bool isDuplicate = false;
            uint256 incrementVote = 1;
            isDuplicate = flightSuretyData.getVoterStatus(msg.sender);

            // Check to avoid registering same airline multiple times
            require(!isDuplicate, "Caller has already voted.");
            flightSuretyData.addVoters(msg.sender);
            flightSuretyData.addVoterCounter(airline, incrementVote);
        }
        vote_status = true;
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */

    function fund() public payable requireIsOperational {
        // verify fund is 10 ether
        require(msg.value == 10 ether, "Ether should be 10");

        // Make sure airline has not yet been funded
        require(
            !flightSuretyData.getAirlineOperatingStatus(msg.sender),
            "Airline is already funded"
        );

        // Save in contract instead
        //contractOwner.transfer(msg.value);

        flightSuretyData.fundAirline(msg.sender, msg.value);

        flightSuretyData.setAirlineOperatingStatus(msg.sender, true);

        emit FundedLines(msg.sender, msg.value);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */

    function buy(address airline) external payable requireIsOperational {
        // Check if airline is operational
        require(
            flightSuretyData.getAirlineOperatingStatus(airline),
            "Airline you are buying insurance from should be operational"
        );

        // Check if amount range is greater than 0 ether and less than 1 ether.
        require(
            (msg.value > 0 ether) && (msg.value <= 1 ether),
            "You can not buy insurance of more than 1 ether or less than 0 ether"
        );

        // Save in contract instead
        //airline.transfer(msg.value);
        // Register insurance in database
        flightSuretyData.registerInsurance(airline, msg.sender, msg.value);

        //uint256 getFund = flightSuretyData.getAirlineFunding(airline);

        emit PurchaseInsurance(airline, msg.sender, msg.value);
    }

    function getPassenger_CreditedAmount() external returns (uint256) {
        uint256 credit = flightSuretyData.getPassengerCredit(msg.sender);
        return credit;
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function withdraw() external requireIsOperational {
        require(
            flightSuretyData.getPassengerCredit(msg.sender) > 0,
            "No balance to withdraw"
        );

        uint256 withdraw_value = flightSuretyData.withdraw(msg.sender);
        // Transfer credit to passenger wallet
        msg.sender.transfer(withdraw_value);

        emit Withdraw(msg.sender, withdraw_value);
    }

    /**
     * @dev Called after oracle has updated flight status
     *
     */

    function processFlightStatus(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    ) public {
        address passenger;
        uint256 amountPaid;
        (passenger, amountPaid) = flightSuretyData.getInsuredPassenger_amount(
            airline
        );

        require(
            (passenger != address(0)) && (airline != address(0)),
            "'accounts' must be  valid address."
        );
        require(amountPaid > 0, "Passenger is not insured");

        // Only credit if flight delay is airline fault (airline late and late due to technical)
        if (
            (statusCode == STATUS_CODE_LATE_AIRLINE) ||
            (statusCode == STATUS_CODE_LATE_TECHNICAL)
        ) {
            uint256 credit = amountPaid.mul(3).div(2);

            flightSuretyData.creditInsurees(airline, passenger, credit);
            emit CreditInsurees(airline, passenger, credit);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        address airline,
        string flight,
        uint256 timestamp
    ) external requireIsOperational {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key =
            keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
            requester: msg.sender,
            isOpen: true
        });

        emit OracleRequest(index, airline, flight, timestamp);
    }

    /********************************************************************************************/
    /*                                       ORACLE MANAGEMENT                                  */
    /********************************************************************************************/

    function triggerOracleResponse(
        uint8 indexes,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    ) external {
        emit SubmitOracleResponse(
            indexes,
            airline,
            flight,
            timestamp,
            statusCode
        );
    }

    function getResistration_fee() external pure returns (uint256) {
        return REGISTRATION_FEE;
    }

    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() external view returns (uint8[3] memory) {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    ) external requireIsOperational {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key =
            keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (
            oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES
        ) {
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }

    function getFlightKey(
        address airline,
        string flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns (uint8[3]) {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns random integer from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random =
            uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            blockhash(block.number - nonce++),
                            account
                        )
                    )
                ) % maxValue
            );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    // endregion

    /**
     * @dev Fallback function for funding smart contract.
     *
     */

    function() external payable {
        fund();
    }
}

// Creating an interface to FlightSuretyData.sol
contract FlightSuretyData {
    function registerAirline(address account, bool isOperational) external;

    function multiCallsLength() external returns (uint256);

    function getAirlineOperatingStatus(address account) external returns (bool);

    function setAirlineOperatingStatus(address account, bool status) external;

    function registerInsurance(
        address airline,
        address passenger,
        uint256 amount
    ) external;

    function creditInsurees(
        address airline,
        address passenger,
        uint256 amount
    ) external;

    function getInsuredPassenger_amount(address airline)
        external
        returns (address, uint256);

    function getPassengerCredit(address passenger) external returns (uint256);

    function getAirlineRegistrationStatus(address account)
        external
        returns (bool);

    function fundAirline(address airline, uint256 amount) external;

    function getAirlineFunding(address airline) external returns (uint256);

    function withdraw(address passenger) external returns (uint256);

    function getVoteCounter(address account) external returns (uint256);

    function setVoteCounter(address account, uint256 vote) external;

    function getVoterStatus(address voter) external returns (bool);

    function addVoterCounter(address airline, uint256 count) external;

    function resetVoteCounter(address account) external;

    function addVoters(address voter) external;
}
