// SPDX-License-Identifier: MIT 

pragma solidity =0.7.6;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

contract VoFarmRouter{

    mapping (string => address) private pools;
    IUniswapV3Pool pool;

    // Arb-ChainID = 42161
    constructor(string memory _name)
    {

        uint256 id = getChainID();
        if (id == 42161)
        {
            pools["ETH/USDC05"] = 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
            pools["ETH/USDC3"]  = 0x17c14D2c404D167802b16C450d3c99F88F2c4F4d;
            pools["WBTC/ETH05"] = 0x2f5e87C9312fa29aed5c179E456625D79015299c;
            pools["WBTC/ETH3"]  = 0x149e36E72726e0BceA5c59d40df2c43F60f5A22D;
            pools["ETH/GMX1"]   = 0x80A9ae39310abf666A87C743d6ebBD0E8C42158E;
        }

        pool = IUniswapV3Pool(pools[_name]);

    }

    function getChainID() private pure returns(uint256)
    {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function getX96() private view returns(uint160)
    {

        (uint160 sqrtPriceX96, 
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked ) = pool.slot0();

        return sqrtPriceX96;
    }

    function getPrimaryPrice() public view returns(uint256)
    {
        return (getX96() ** 2 / 2 ** 192);
    }

    function getSecondaryPrice() public view returns(uint256)
    {
        return (2 ** 192 / getX96() ** 2);
    }

}
