import * as _ from 'lodash';

import {artifacts} from '../artifacts';
import {TokenTransferProxyContract, ZeroExError} from '../types';
import {Web3Wrapper} from '../web3_wrapper';

import {ContractWrapper} from './contract_wrapper';

/**
 * This class includes the functionality related to interacting with the TokenTransferProxy contract.
 */
export class TokenTransferProxyWrapper extends ContractWrapper {
    private _tokenTransferProxyContractIfExists?: TokenTransferProxyContract;
    private _contractAddressIfExists?: string;
    constructor(web3Wrapper: Web3Wrapper, contractAddressIfExists?: string) {
        super(web3Wrapper);
        this._contractAddressIfExists = contractAddressIfExists;
    }
    /**
     * Check if the Exchange contract address is authorized by the TokenTransferProxy contract.
     * @param   exchangeContractAddress     The hex encoded address of the Exchange contract to call.
     * @return  Whether the exchangeContractAddress is authorized.
     */
    public async isAuthorizedAsync(exchangeContractAddress: string): Promise<boolean> {
        const tokenTransferProxyContractInstance = await this._getTokenTransferProxyContractAsync();
        const isAuthorized = await tokenTransferProxyContractInstance.authorized.callAsync(exchangeContractAddress);
        return isAuthorized;
    }
    /**
     * Get the list of all Exchange contract addresses authorized by the TokenTransferProxy contract.
     * @return  The list of authorized addresses.
     */
    public async getAuthorizedAddressesAsync(): Promise<string[]> {
        const tokenTransferProxyContractInstance = await this._getTokenTransferProxyContractAsync();
        const authorizedAddresses = await tokenTransferProxyContractInstance.getAuthorizedAddresses.callAsync();
        return authorizedAddresses;
    }
    /**
     * Retrieves the Ethereum address of the TokenTransferProxy contract deployed on the network
     * that the user-passed web3 provider is connected to.
     * @returns The Ethereum address of the TokenTransferProxy contract being used.
     */
    public getContractAddress(): string {
        const contractAddress = this._getContractAddress(
            artifacts.TokenTransferProxyArtifact, this._contractAddressIfExists,
        );
        return contractAddress;
    }
    private _invalidateContractInstance(): void {
        delete this._tokenTransferProxyContractIfExists;
    }
    private async _getTokenTransferProxyContractAsync(): Promise<TokenTransferProxyContract> {
        if (!_.isUndefined(this._tokenTransferProxyContractIfExists)) {
            return this._tokenTransferProxyContractIfExists;
        }
        const contractInstance = await this._instantiateContractIfExistsAsync<TokenTransferProxyContract>(
            artifacts.TokenTransferProxyArtifact, this._contractAddressIfExists,
        );
        this._tokenTransferProxyContractIfExists = contractInstance;
        return this._tokenTransferProxyContractIfExists;
    }
}