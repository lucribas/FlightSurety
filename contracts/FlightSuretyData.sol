pragma solidity >=0.4.24 <0.6.0;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    //using SafeMath for uint;
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // ----------------
    // Contract Control
    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    mapping(address => bool) public authorizedContracts;
    address[] multiCalls = new address[](0);

    // Struct used to hold registered airlines
    struct Airlines {
        bool isRegistered;
        bool isOperational;
    }

    mapping(address => Airlines) airlines; // mapping address to struct which holds registered airlines.

    // ----------------
    // Insurance
    struct Insurance {
        address passenger;
        uint256 amount;
    }

    mapping(address => Insurance) insurance; // Airline address maps to struct

    struct Fund {
        uint256 amount;
    }
    mapping(address => Fund) fund;

    mapping(address => uint256) balances;

    // ----------------
    // Consensus

    struct Voters {
        bool status;
    }
    mapping(address => uint256) private voteCount;
    mapping(address => Voters) voters;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event AuthorizedContract(address authContract);
    event DeAuthorizedContract(address authContract);

    /********************************************************************************************/
    /*                                       CONSTRUCTOR 	                                    */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() public {
        contractOwner = msg.sender;
    }

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

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireAirlineRegistered(address _airline) {
        require(airlines[_airline].isRegistered, "Airline is not registered");
        _;
    }

    /**
     * @dev Modifier that requires the "ContractAddress" account to be authorized
     */
    modifier requireContractAddressAuthorized(address _contractAddress) {
        require(
            authorizedContracts[_contractAddress],
            "ContractAddress is not authorized"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */

    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function authorizeContract(address ContractAddress)
        external
        requireContractOwner
        requireIsOperational
    {
        authorizedContracts[ContractAddress] = true;
        emit AuthorizedContract(ContractAddress);
    }

    function deauthorizeContract(address contractAddress)
        external
        requireContractOwner
    {
        delete authorizedContracts[contractAddress];
        emit DeAuthorizedContract(contractAddress);
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    // ------------------- Get and Set function for multiCalls -------------------------

    function setmultiCalls(address account) private {
        multiCalls.push(account);
    }

    function multiCallsLength()
        external
        view
        requireIsOperational
        returns (uint256)
    {
        return multiCalls.length;
    }

    //----------------- Set and Get function for Airline struct ------------------------------
    function getAirlineOperatingStatus(address account)
        external
        view
        requireIsOperational
        returns (bool)
    {
        return airlines[account].isOperational;
    }

    function setAirlineOperatingStatus(address account, bool status)
        external
        requireIsOperational
    {
        airlines[account].isOperational = status;
    }

    function getAirlineRegistrationStatus(address account)
        external
        view
        requireIsOperational
        returns (bool)
    {
        return airlines[account].isRegistered;
    }

    function getVoteCounter(address account)
        external
        view
        requireIsOperational
        returns (uint256)
    {
        return voteCount[account];
    }

    function resetVoteCounter(address account) external requireIsOperational {
        delete voteCount[account];
    }

    function getVoterStatus(address voter)
        external
        view
        requireIsOperational
        returns (bool)
    {
        return voters[voter].status;
    }

    function addVoters(address voter) external {
        voters[voter] = Voters({status: true});
    }

    function addVoterCounter(address airline, uint256 count) external {
        uint256 vote = voteCount[airline];
        voteCount[airline] = vote.add(count);
    }

    // ---------------------------- Insurance registration --------------------------
    function registerInsurance(
        address airline,
        address passenger,
        uint256 amount
    ) external requireIsOperational {
        insurance[airline] = Insurance({passenger: passenger, amount: amount});
        uint256 getFund = fund[airline].amount;
        fund[airline].amount = getFund.add(amount);
    }

    //-----------------------------Fund recording -------------------------
    function fundAirline(address airline, uint256 amount) external {
        fund[airline] = Fund({amount: amount});
    }

    function getAirlineFunding(address airline)
        external
        view
        returns (uint256)
    {
        return fund[airline].amount;
    }

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */

    function registerAirline(address account, bool _isOperational)
        external
        requireIsOperational
    {
        // isRegistered is Always true for a registered airline
        // isOperational is only true when the airline has submited funding of 10 ether
        airlines[account] = Airlines({
            isRegistered: true,
            isOperational: _isOperational
        });
        setmultiCalls(account);
    }

    /**
     * @dev Check if an airline is registered
     *
     * @return A bool that indicates if the airline is registered
     */

    function isAirline(address account) external view returns (bool) {
        require(account != address(0), "'account' must be a valid address.");

        return airlines[account].isRegistered;
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(
        address airline,
        address passenger,
        uint256 amount
    ) external requireIsOperational {
        // Get expected amount to be credited
        uint256 required_amount = insurance[airline].amount.mul(3).div(2);

        require(
            insurance[airline].passenger == passenger,
            "Passenger is not insured"
        );
        require(
            required_amount == amount,
            "The amount to be credited is not as espected"
        );
        require(
            (passenger != address(0)) && (airline != address(0)),
            "'accounts' must be  valid address."
        );

        // Store amount to be credited in passenger balance
        balances[passenger] = amount;
    }

    function withdraw(address passenger)
        external
        requireIsOperational
        returns (uint256)
    {
        uint256 withdraw_cash = balances[passenger];

        delete balances[passenger];
        return withdraw_cash;
    }

    function getInsuredPassenger_amount(address airline)
        external
        view
        requireIsOperational
        returns (address, uint256)
    {
        return (insurance[airline].passenger, insurance[airline].amount);
    }

    function getPassengerCredit(address passenger)
        external
        view
        requireIsOperational
        returns (uint256)
    {
        return balances[passenger];
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

}
