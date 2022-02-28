// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.7;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract VFPool is AccessControl{

    //------ access setup
	bytes32 public constant PROVIDER_ROLE = keccak256("Provider");
    string private contractName = "";

	// swapping
    ISwapRouter private swapRouter;
	uint24 private constant poolFee = 3000;

	// Rinkeby:
    address private stable; 
    address private volat;
    
    // temporär -- addressen hier für schnelleren debug-zugriff
    address private constant DAIRinkeby = 0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa;
    address private constant WETHRinkeby = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    address private constant USDCRinkeby = 0xeb8f08a975Ab53E34D8a0330E0D34de942C95926;
    address private constant WBTCRinkeby = 0x577D296678535e4903D59A4C929B718e1D575e0A;
    address private constant DAIRopsten = 0xaD6D458402F60fD3Bd25163575031ACDce07538D;
    address private constant WETH9Ropsten = 0xc778417E063141139Fce010982780140Aa0cD5Ab;

    string public lastAdvice = ""; 

	//------ oracle request setup
	Request[] requests;
	uint256 currentId;
	struct Request{
		uint256 id;
		string tknPair;
		uint256 agreedValue;
	}
	
	event requestData(
		uint256 id,
		string tknPair
	);
	
	event requestDone(
		uint256 id,
		uint256 agreedValue
	);

    // Debug -- teilweise später wieder auf private
    string[] advices;
    uint256 public lastCallback;

    //------ trading setup
    //Array of prices: volatile coin - stable coin
    uint256[] prices;

    //algo parameters, these can be fine tuned

    //number of price values to determine average from
    uint256 lastXPrices = 10;
	
	//teiler des gesamten Token kapitals, das bei einem trade geswappt werden soll
	uint256 div = 4;

    //minimum numer of price values to determine average from
    uint256 minPrices = 6;

    //comparisson parameters
    // ANPASSEN!!
    uint256 minDifferenceUp = 5;
    uint256 minDifferenceDown = 5;
    
    //all invested addresses
    address[] public investors;
    
    //stake = 1'000'000'000'000'000'000 equals 100%, stake = 0 
    uint256 totalSupply = 1000000000000000000;
    
    //address -> stake in pool
    mapping(address => uint256) public stakes;
    
    //zum Testen beide auf 1 gesetzt, sonst 10000000000000000
    //minimum stable deposit
    uint256 minStableDeposit = 1;
    //minimum volatile deposit
    uint256 minVolatileDeposit = 1;

    //contract stable state: stable=true, volatile=false
    bool public stableState = false;
	
	//------ basic address setup
	constructor(string memory _name, address _primary, address _secundary) {
	
        stable = _primary;
        volat = _secundary;
        contractName = _name;

		currentId = 0;

        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Rinkeby and ropsten

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

//-----------------------------
// Oracle functions

	function execRequest(
		string memory _tknPair
	)
	private
	onlyProvider
	{
		requests.push(Request(currentId, _tknPair,0));
		
		emit requestData(
			currentId,
			_tknPair
		);
		
	}
	
	function callback(
		uint256 _id,
		uint256 _value
	)
	public
	onlyProvider
	{
		Request storage currRequest = requests[_id];
		currRequest.agreedValue = _value;

        lastCallback = _value;

        // check id before push
        prices.push(_value);

		emit requestDone(
			_id,
			_value
		);

        currentId++;
	}

//-----------------------------
// Gettes functions / interaction

    function name() public view returns(string memory)
    {
        return contractName;
    }

    function _getPrice(address _token) public view returns(uint256)
    {
        return IERC20(_token).balanceOf(address(this));
    }

    function _getLastAdvice() public view returns(string memory)
    {
        return lastAdvice;
    }

    function _getPriceList() public view returns(uint[] memory)
    {
        return prices;
    }

    function _getCurrentReqID() public view returns(uint256)
    {
        return currentId;
    }

    function _getRequestPriceAtID(uint256 _id) public view returns(uint256)
    {
        return requests[_id].agreedValue;
    }

    function _getAdviceCount() public view returns(uint256)
    {
        return advices.length;
    }

    function _getAdviceAtCount(uint256 _id) public view returns(string memory)
    {
        return advices[_id-1];
    }

    function getPrimaryToken() public view returns(address)
    {
        return stable;
    }

    function getSecondaryToken() public view returns(address)
    {
        return volat;
    }


//-----------------------------
// Pool functions

	function swapExcactInToOut(
        uint256 amountIn, 
        address tokenIN, 
        address tokenOUT
        ) 
        private 
        onlyProvider
        returns (bool) {
    
        // Approve the router to spend DAI.
        TransferHelper.safeApprove(tokenIN, address(swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIN,
                tokenOut: tokenOUT,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap. Retrun true if the swap was succesfull
        if (swapRouter.exactInputSingle(params) > 0) 
        {
            return true;
        }
        else
        {
            return false;
        }
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
            stableState = false;

		} else if (recom == keccak256(abi.encodePacked("sell"))) {
			// verkauf den volatilen Token und erhalte dafür stable 
			tokenIN = volat;
			tokenOUT = stable;
            stableState = true;
        } 
        if (uint160(tokenIN) != 0){
            if (IERC20(tokenIN).balanceOf(address(this)) > 0) {
                amount = IERC20(tokenIN).balanceOf(address(this));
                startTransfer = true;
            }
        }

        return (startTransfer, tokenIN, tokenOUT, amount);
    }

    // To Be executed by BOT
    function executeCurrentInvestmentAdvices() 
    public 
    onlyProvider 
    returns (bool toReturn){
        
		// neue Daten in Price-List schreiben
		execRequest(contractName);
        
        // Get values from investmentStrat
        (
            bool startTransfer, 
            address tokenIN, 
            address tokenOUT, 
            uint256 amount
            ) = investmentStrat();
        
        if (startTransfer == true) {
            toReturn = swapExcactInToOut(
                amount,
                tokenIN, 
                tokenOUT
            );
        }

        return toReturn;
    }

//-----------------------------
// Trading - Strat
    /*
    Add new value to stored values.
    Execute trade evaluation.
    */   
	/*
	Wird nicht gebraucht. evaluateLatestMovement() wird direkt von investmentStrat aufgerufen
    function addMockValue() public returns (string memory){
        string memory recommendation;
        recommendation = evaluateLatestMovement();
        return recommendation;
    }
	*/

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
    view 
    returns (string memory){
        bool priceIsUp;
        uint difference;
        (difference, priceIsUp) =  compareLatestPriceToRelevantValues();
        if(priceIsUp){
            if(difference >= minDifferenceUp){
                //recommend sell
                return "sell";
            }else{
                //recommend hold
                return "hold";
            }
        }else{
            if(difference >= minDifferenceDown){
                //recommend buy
                return "buy";
            }else{
                //recommend hold
                return "hold";
            }
        }
    }

//-----------------------------
// Pool - Stake-Handling

//Funktionen werden noch korrekt implementiert
    //CRUD functions for mapping
    function getInvestorStake(address _address) public view returns (uint256)
    {
        return stakes[_address];
    }

    function removeInvestorAddress(address _address) public
    {
        //remove stake
        delete stakes[_address];
        //remove address from stored addresses
        uint256 investorsLength = investors.length;
        require(investorsLength > 0, "Cannot remove elements from empty array");
        address[] memory investorsTemp = new address[](investorsLength-1);
        
        uint c=0;
        for(uint i=0; i<investorsLength; i++){
            if(investors[i]!=_address){
                investorsTemp[c] = investors[i];
                c++;
            }
        }
        
        delete investors;
        
        for(uint i=0; i<investorsLength-1; i++){
            investors.push( investorsTemp[i] );
        }
    }
    
    function addInvestorAddress(address _address) private {
        require(_investorsContainsAddress(_address) == false, "Address already stored.");
        investors.push(_address);
    }
    
    function _investorsContainsAddress(address _address) 
    private 
    view 
    returns (bool){
        for(uint i=0;i<investors.length;i++){
            if(investors[i] == _address){
                return true;
            }
        }
        return false;
    }
    
    function _sumInvestorStakes() 
    private 
    view
    returns (uint256){
        uint256 sum = 0;
        for(uint i=0; i<investors.length; i++){
            sum = sum + stakes[investors[i]];
        }
        return sum;
    }

    function _smallestInvestorByStake() 
    private 
    view 
    returns (address){
        address investor = investors[0];
        for(uint i=1; i<investors.length; i++){
            if(stakes[investors[i]] < stakes[investor]){
                investor = investors[i];
            }
        }
        return investor;
    }
    
    function recalculateAllStakesOnDeposit(uint256 amount) private {
        uint256 oldBalance = this.balance() - amount;
        for(uint i=0; i<investors.length; i++){
            stakes[investors[i]] = (stakes[investors[i]]*oldBalance)/(oldBalance + amount);
        }
    }

    function recalculateAllStakesOnWithdraw(uint256 amount) private {
        if(investors.length == 1){
            //stake = total supply
            stakes[investors[0]] = totalSupply;
        }else{
            if(investors.length > 0){
                //calculate stakes
                uint256 oldBalance = this.balance();
                for(uint i=0; i<investors.length; i++){
                    stakes[investors[i]] = (stakes[investors[i]]*oldBalance)/(oldBalance - amount);
                }
                //divide remainder between investors
                uint256 remainder = totalSupply - _sumInvestorStakes();
                uint256 share = remainder / investors.length;
                if(share > 0){
                    for(uint i=0; i<investors.length; i++){
                        stakes[investors[i]] = stakes[investors[i]] + share;
                    }
                }
                address smallest = _smallestInvestorByStake();
                stakes[smallest] = stakes[smallest] + (remainder - share * investors.length);
            }
        }
    }
    
    function balance() public view returns (uint256){
        //hier aus beiden token wert errechnen, der eth wei einheit entspricht
        //tokenpreise müssen mit oracle abgefragt werden-> nicht unbedingt

        if(stableState){
            return ERC20(stable).balanceOf(address(this));
        }else{
            return ERC20(volat).balanceOf(address(this));
        }
    }
 
    function deposit(address _token, uint _amount) public{
        //can only deposit token depending on contract state, check validity and approve/reject
        //check for minimum deposit values
        if(stableState){
            require(_token==address(ERC20(stable)),"Please use stable token to deposit.");
            require(_amount>=minStableDeposit,"require minimum amount of stable-token");
        }else{
            require(_token==address(ERC20(volat)),"Please use volatile token to deposit.");
            require(_amount>=minVolatileDeposit,"require minimum mount of volatile-token");
        }

        //add tokens to pool
        ERC20(_token).transferFrom(msg.sender, address(this), _amount);

        //assign new stakes for everyone, add address to investors on first deposit
        if(investors.length < 1){
            addInvestorAddress(msg.sender);
            stakes[msg.sender] = totalSupply;
        }else{
            if(!_investorsContainsAddress(msg.sender)){
                addInvestorAddress(msg.sender);
            }
            recalculateAllStakesOnDeposit(_amount);
            stakes[msg.sender] = totalSupply - _sumInvestorStakes() + stakes[msg.sender];
        }
    }
    
    function withdraw() 
    external 
    payable
    {
        require(_investorsContainsAddress(msg.sender), "Address not investor.");
        uint256 amount = (stakes[msg.sender]*this.balance())/totalSupply;
        removeInvestorAddress(msg.sender);
        recalculateAllStakesOnWithdraw(amount);
        //(bool success, ) = //msg.sender.call{value:amount}("");
        if(stableState){
            ERC20(stable).transfer(msg.sender, amount);
        }else{
            ERC20(volat).transfer(msg.sender, amount);
        }
        //require(success, "Transfer failed.");
    }

    function getEarned() public view returns (uint256)
    {
        return (getInvestorStake(msg.sender) * balance()) /totalSupply;
    }
}
