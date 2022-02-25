// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Transfer
{

	//Vorher über einen Aufruf im Front-End die Approve-Funktion des jeweiligen Token aufrufen
	// um dadurch den Transfer "freizuschalten". Verbindung des Meta-Mask-Wallet vom Kunden
	// um seine Addresse als msg.sender zu haben.
    address private constant stable = 0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa; //dai
    address private constant volat = 0xc778417E063141139Fce010982780140Aa0cD5Ab; //weth

    function transferToMe(address _owner, address _token, uint _amount) public returns(bool)
    {
        
        return ERC20(_token).transferFrom(_owner, address(this), _amount);

    }    

}