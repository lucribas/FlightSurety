
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

	//const productPrice = web3.toWei(1, "ether");
	//const fundPrice = web3.utils.toWei(10, 'ether');

	var config;
	before('setup contract', async () => {
		config = await Test.Config(accounts);
		await config.flightSuretyData.authorizeContract(config.flightSuretyApp.address);
	});

	/****************************************************************************************/
	/* Operations and Settings                                                              */
	/****************************************************************************************/

	it(`(multiparty) has correct initial isOperational() value`, async function () {

		// Get operating status
		let status = await config.flightSuretyData.isOperational.call();
		assert.equal(status, true, "Incorrect initial operating status value");

	});

	it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

		// Ensure that access is denied for non-Contract Owner account
		let accessDenied = false;
		try {
			await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
		}
		catch (e) {
			accessDenied = true;
		}
		assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

	});

	it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

		// Ensure that access is allowed for Contract Owner account
		let accessDenied = false;
		try {
			await config.flightSuretyData.setOperatingStatus(false);
		}
		catch (e) {
			accessDenied = true;
		}
		assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

	});

	it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

		await config.flightSuretyData.setOperatingStatus(false);

		let reverted = false;
		try {
			await config.flightSurety.setTestingMode(true);
		}
		catch (e) {
			reverted = true;
		}
		assert.equal(reverted, true, "Access not blocked for requireIsOperational");

		// Set it back for other tests to work
		await config.flightSuretyData.setOperatingStatus(true);

	});

	it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {

		// ARRANGE
		let newAirline = accounts[2];

		// ACT
		try {
			await config.flightSuretyApp.registerAirline(newAirline, { from: config.firstAirline });
		}
		catch (e) {

		}
		let result = await config.flightSuretyData.isAirline.call(newAirline);


		// ASSERT
		assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");

	});

	it('function call is made when multi-party threshold is reached', async () => {

		// ARRANGE
		let admin1 = accounts[1];
		let admin2 = accounts[2];
		let admin3 = accounts[3];
		let admin4 = accounts[4];


		try {
			await config.flightSuretyApp.registerAirline(admin1, { from: config.owner });
			await config.flightSuretyApp.registerAirline(admin2, { from: config.owner });
			await config.flightSuretyApp.registerAirline(admin3, { from: config.owner });

			await config.flightSuretyApp.registerAirline(admin4, { from: config.owner });


		} catch (e) {
			console.log('some failed');
		}

		let result = await config.flightSuretyData.isAirline.call(admin4);

		// ASSERT
		assert.equal(result, false, "Multi-party call passed");
	});

	it('ariline is only operational when it has submitted funding of 10 ether', async () => {

		// ARRANGE
		let admin2 = accounts[2];
		let admin3 = accounts[3];
		let fundPrice = web3.utils.toWei("10", "ether");

		try {
			await config.flightSuretyApp.fund({ from: admin2, value: fundPrice });
			await config.flightSuretyApp.fund({ from: admin3, value: fundPrice });

		} catch (e) {
			console.log('Funding has failed');
		}

		let result = await config.flightSuretyData.getAirlineOperatingStatus.call(admin3);

		// ASSERT
		assert.equal(result, true, "Status is not true")

	});


	it('Voting is made when multi-party threshold is reached', async () => {

		// ARRANGE

		let admin2 = accounts[2];
		let admin3 = accounts[3];
		let admin4 = accounts[4];
		let status = null;


		try {
			// Registration of the 5th airline.
			// Returns (false, false) = (sucess, vote_status).
			// A combination of false indicates that a votting is required.
			let registration_status = await config.flightSuretyApp.registerAirline.call(admin4, { from: admin3 });
			status = await config.flightSuretyData.isAirline.call(admin4);

			if (registration_status[0] == false && registration_status[1] == false) {
				await config.flightSuretyApp.approveAirlineRegistration(admin4, true, { from: config.owner });  //vote out
				await config.flightSuretyApp.approveAirlineRegistration(admin4, true, { from: admin3 });         // vote in
				await config.flightSuretyApp.approveAirlineRegistration(admin4, false, { from: admin2 });         // vote in
			}
			// Try registration again. 
			await config.flightSuretyApp.registerAirline(admin4, { from: admin3 });

		} catch (e) {

		}

		let result = await config.flightSuretyData.isAirline.call(admin4);

		// ASSERT
		assert.equal(result, true, "Multi-party voting call failed");
		assert.equal(status, false, "5th airline should not be registered without voting");
	});




	it('Passenger can buy flight inssurance for at most 1 ether', async () => {

		// ARRANGE
		let passenger6 = accounts[6];
		let airline = accounts[2];
		let rawAmount = 1;
		let InsuredPrice = web3.utils.toWei(rawAmount.toString(), "ether");


		try {

			await config.flightSuretyApp.buy(airline, { from: passenger6, value: InsuredPrice });

		} catch (e) {

		}

		let result = await config.flightSuretyData.getInsuredPassenger_amount.call(airline);

		// ASSERT
		assert.equal(result[0], passenger6, "Status is not true")



	});

	it('Insured passenger can be credited if flight is delayed', async () => {

		// ARRANGE
		let passenger = accounts[6];
		let airline = accounts[2];
		let credit_status = true;
		let balance = 1.5;
		let credit_before = 0
		let credit_after = 0
		let STATUS_CODE_LATE_AIRLINE = 20;
		let flight = 'FLGT002';
		let timestamp = Math.floor(Date.now() / 1000);


		try {
			// Check credit before passenger was credited
			credit_before = await config.flightSuretyApp.getPassenger_CreditedAmount.call({ from: passenger });
			credit_before = web3.utils.fromWei(credit_before, "ether")
			//console.log(credit_before);

			// Credit the passenger
			await config.flightSuretyApp.processFlightStatus(airline, flight, timestamp, STATUS_CODE_LATE_AIRLINE);


			// Get credit after passenger has been credited
			credit_after = await config.flightSuretyApp.getPassenger_CreditedAmount.call({ from: passenger });
			credit_after = web3.utils.fromWei(credit_after, "ether");
			//console.log(credit_after);


		} catch (e) {
			credit_status = false;
		}


		// ASSERT
		assert.equal(balance, credit_after, "Credited balance  not as expected")
		assert.equal(credit_status, true, "Passenger was not credited");

	});

	it('Credited passenger can withdraw ether(transfer from airline to passenger)', async () => {

		// ARRANGE
		let passenger = accounts[6];
		let withdraw = true;
		let balance_before = 0;
		let balance_after = 0;
		let eth_balance_before = 0;
		let eth_balance_after = 0;
		let credit = 1.5;

		try {


			balance_before = await config.flightSuretyApp.getPassenger_CreditedAmount.call({ from: passenger })
			balance_before = web3.utils.fromWei(balance_before, "ether");

			eth_balance_before = await web3.eth.getBalance(passenger)
			eth_balance_before = web3.utils.fromWei(eth_balance_before, "ether");
			console.log("ETH balance before: ", eth_balance_before)

			await config.flightSuretyApp.withdraw({ from: passenger });

			// Check if credit has been redrawn
			balance_after = await config.flightSuretyApp.getPassenger_CreditedAmount.call({ from: passenger })
			balance_after = web3.utils.fromWei(balance_after, "ether");

			eth_balance_after = await web3.eth.getBalance(passenger)
			eth_balance_after = web3.utils.fromWei(eth_balance_after, "ether");
			console.log("ETH balance after: ", eth_balance_after)

			console.log("The difference is ", eth_balance_after - eth_balance_before);

		} catch (e) {
			withdraw = false;
		}

		// ASSERT
		assert.equal(withdraw, true, "Passenger could not withdraw");
		assert.equal(balance_before, credit, "Redrawn credit doesn't match")
		assert.equal(balance_after, 0, "Credit was't redrawn");
		assert.ok((eth_balance_after - eth_balance_before) > 0, "Credited was not transfered to wallet");



	});

});
