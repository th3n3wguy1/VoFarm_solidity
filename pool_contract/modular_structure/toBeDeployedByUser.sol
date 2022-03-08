//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import '@openzeppelin/contracts/access/AccessControl.sol';
import "../source/VoFarmer.sol";
import "../pools/router.sol";

contract Trader is AccessControl{

    uint256[] prices;

    uint256 lastXPrices = 1;
    uint256 minPrices = 1;
    uint256 minDifferenceUp = 5;
    uint256 minDifferenceDown = 5;
    uint256 minStableDeposit = 1;
    uint256 minVolatileDeposit = 1;

    bytes32 public constant PROVIDER_ROLE = keccak256("Provider");
    VoFarmPool voFarm;
    VoFarmRouter voRouter;

    string lastAdvice;

    address private stable;
    address private volat;

    constructor(string memory _name, 
        address _primary, 
        address _secundary, 
        address _router) {

        voFarm = new VoFarmPool(_name, _primary, _secundary, _router);
        voRouter = new VoFarmRouter(_name);

        stable = _primary;
        volat = _secundary;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(PROVIDER_ROLE, DEFAULT_ADMIN_ROLE);

    }

    //-----------------------------
// Access control

	modifier onlyAdmin()
    {
        require(isAdmin(msg.sender), "Restricted to admins!");   
        _;
    }

    modifier onlyProvider()
    {
        require(isProvider(msg.sender), "Restricted to user!");
        _;
    }
    
    function isAdmin(address toTest) private view returns(bool)
    {
        return hasRole(DEFAULT_ADMIN_ROLE, toTest);
    }
    
    function isProvider(address toTest) private view returns(bool)
    {
        return hasRole(PROVIDER_ROLE, toTest);
    }
    
    function addProvider(address toAdd) public onlyAdmin
    {
        grantRole(PROVIDER_ROLE, toAdd);
    }
    
    function addAdmin(address toAdd) private onlyAdmin
    {
        grantRole(DEFAULT_ADMIN_ROLE, toAdd);
    }
    
    function removeProvider(address toRemove) private onlyAdmin
    {
        revokeRole(PROVIDER_ROLE, toRemove);
    }
    
    function removeAdmin(address toRemove) private onlyAdmin
    {
        revokeRole(DEFAULT_ADMIN_ROLE, toRemove);
    }

    function deposit(address _token, uint _amount) public
    {
        voFarm.deposit(_token,_amount);
    }

    function withdraw() public
    {
        voFarm.withdraw();
    }

    function getBalance(address _token) public view returns(uint256)
    {
        return voFarm._getPrice(_token);
    }

    // To Be executed by BOT
    function executeCurrentInvestmentAdvices() 
    public 
    onlyProvider 
    returns (bool toReturn){

        prices.push(voRouter.getPrimaryPrice());
        
        // Get values from investmentStrat
        (
            bool startTransfer, 
            address tokenIN, 
            address tokenOUT, 
            uint256 amount
            ) = investmentStrat();
        
        if (startTransfer == true) {
            toReturn = voFarm.swapExcactInToOut(
                amount,
                tokenIN, 
                tokenOUT
            );
        }

        return toReturn;
    }

        // vorher public payable, vlt wieder ändern
	function investmentStrat() private onlyProvider returns (
            bool startTransfer, 
            address tokenIN, 
            address tokenOUT, 
            uint256 amount)
        {
        
        bytes32 recom = keccak256(abi.encodePacked(lastAdvice));

        //für aktuell erstmal: komplette kapital des einen token swappen
		if (recom == keccak256(abi.encodePacked("buy"))) {
			// verkaufe den stabilen Token und erhalte dafür den volatilen
			tokenIN = stable;
			tokenOUT = volat;
            voFarm.setStableState(false);
		} else if (recom == keccak256(abi.encodePacked("sell"))) {
			// verkauf den volatilen Token und erhalte dafür stable 
			tokenIN = volat;
			tokenOUT = stable;
            voFarm.setStableState(true);
        } 

        if ( uint160(tokenIN) != 0) {
            if (IERC20(tokenIN).balanceOf(address(this)) > 0) {
                amount = IERC20(tokenIN).balanceOf(address(this));
                startTransfer = true;
            }
        }

        return (startTransfer, tokenIN, tokenOUT, amount);
    }


    function avg(uint[] memory numberArray) 
    private 
    pure 
    returns (uint){
        uint sum = 0;
        for(uint i=0; i<numberArray.length; i++){
            sum += 1000*numberArray[i];
        }
        uint numAvg = sum/numberArray.length;
        numAvg = numAvg/1000;
        return numAvg;
    }

    function lastXValues(uint x, uint[] memory numberArray) 
    private 
    pure 
    returns (uint[] memory){
        if(numberArray.length <= x){
            return numberArray;
        }else{
            uint[] memory lastValues = new uint[](x);
            uint iterator=0;
            for(uint i=numberArray.length - x; i<numberArray.length; i++){
                lastValues[iterator] = numberArray[i];
                iterator++;
            }
            return lastValues;
        }
    }

    function compareLatestPriceToRelevantValues()
    private 
    view 
    returns (uint, bool){
         uint[] memory relevantValues = lastXValues(lastXPrices, prices);
         //require(relevantValues.length >= minPrices, "Not enough data.");
         
         if (relevantValues.length >= minPrices) {
            uint latestPrice = prices[prices.length - 1];
            uint relevantAverage = avg(relevantValues);
            //actual comparisson here
            uint difference = 0;
            bool priceIsUp = false;
            if(latestPrice >= relevantAverage){
                difference = latestPrice - relevantAverage;
                priceIsUp = true;
            }else{
                difference = relevantAverage - latestPrice;
            }
            //return difference and price movement
            return (difference, priceIsUp);
         }

         return (0, false);
         
    }

    //returns string: buy/sell/hold
    function evaluateLatestMovement() 
    private
    {
        bool priceIsUp;
        uint difference;
        (difference, priceIsUp) =  compareLatestPriceToRelevantValues();
        if(priceIsUp){
            if(difference >= minDifferenceUp){
                //recommend sell
                lastAdvice = "sell";
            }else{
                //recommend hold
                lastAdvice =  "hold";
            }
        }else{
            if(difference >= minDifferenceDown){
                //recommend buy
                lastAdvice =  "buy";
            }else{
                //recommend hold
                lastAdvice =  "hold";
            }
        }
    }

}