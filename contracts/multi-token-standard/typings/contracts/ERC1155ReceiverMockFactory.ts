/* Generated by ts-generator ver. 0.0.8 */
/* tslint:disable */

import { Contract, ContractFactory, Signer } from "ethers";
import { Provider } from "ethers/providers";
import { UnsignedTransaction } from "ethers/utils/transaction";

import { TransactionOverrides } from ".";
import { ERC1155ReceiverMock } from "./ERC1155ReceiverMock";

export class ERC1155ReceiverMockFactory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(overrides?: TransactionOverrides): Promise<ERC1155ReceiverMock> {
    return super.deploy(overrides) as Promise<ERC1155ReceiverMock>;
  }
  getDeployTransaction(overrides?: TransactionOverrides): UnsignedTransaction {
    return super.getDeployTransaction(overrides);
  }
  attach(address: string): ERC1155ReceiverMock {
    return super.attach(address) as ERC1155ReceiverMock;
  }
  connect(signer: Signer): ERC1155ReceiverMockFactory {
    return super.connect(signer) as ERC1155ReceiverMockFactory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): ERC1155ReceiverMock {
    return new Contract(address, _abi, signerOrProvider) as ERC1155ReceiverMock;
  }
}

const _abi = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "address",
        name: "_from",
        type: "address"
      },
      {
        indexed: false,
        internalType: "address",
        name: "_to",
        type: "address"
      },
      {
        indexed: false,
        internalType: "uint256[]",
        name: "_fromBalances",
        type: "uint256[]"
      },
      {
        indexed: false,
        internalType: "uint256[]",
        name: "_toBalances",
        type: "uint256[]"
      }
    ],
    name: "TransferBatchReceiver",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "address",
        name: "_from",
        type: "address"
      },
      {
        indexed: false,
        internalType: "address",
        name: "_to",
        type: "address"
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "_fromBalance",
        type: "uint256"
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "_toBalance",
        type: "uint256"
      }
    ],
    name: "TransferSingleReceiver",
    type: "event"
  },
  {
    inputs: [],
    name: "lastData",
    outputs: [
      {
        internalType: "bytes",
        name: "",
        type: "bytes"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "lastId",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "lastOperator",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "lastValue",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "shouldReject",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address"
      },
      {
        internalType: "address",
        name: "_from",
        type: "address"
      },
      {
        internalType: "uint256",
        name: "_id",
        type: "uint256"
      },
      {
        internalType: "uint256",
        name: "",
        type: "uint256"
      },
      {
        internalType: "bytes",
        name: "_data",
        type: "bytes"
      }
    ],
    name: "onERC1155Received",
    outputs: [
      {
        internalType: "bytes4",
        name: "",
        type: "bytes4"
      }
    ],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address"
      },
      {
        internalType: "address",
        name: "_from",
        type: "address"
      },
      {
        internalType: "uint256[]",
        name: "_ids",
        type: "uint256[]"
      },
      {
        internalType: "uint256[]",
        name: "",
        type: "uint256[]"
      },
      {
        internalType: "bytes",
        name: "_data",
        type: "bytes"
      }
    ],
    name: "onERC1155BatchReceived",
    outputs: [
      {
        internalType: "bytes4",
        name: "",
        type: "bytes4"
      }
    ],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [
      {
        internalType: "bytes4",
        name: "interfaceID",
        type: "bytes4"
      }
    ],
    name: "supportsInterface",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [
      {
        internalType: "bool",
        name: "_value",
        type: "bool"
      }
    ],
    name: "setShouldReject",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  }
];

const _bytecode =
  "0x608060405234801561001057600080fd5b50611036806100206000396000f3fe608060405234801561001057600080fd5b50600436106100a25760003560e01c80636eb3cd4911610076578063bc197c811161005b578063bc197c81146101eb578063c1292cc3146103f4578063f23a6e61146103fc576100a2565b80636eb3cd4914610199578063a175b638146101ca576100a2565b80626e75ec146100a757806301ffc9a7146101245780631dbb938114610177578063431838341461017f575b600080fd5b6100af6104d4565b6040805160208082528351818301528351919283929083019185019080838360005b838110156100e95781810151838201526020016100d1565b50505050905090810190601f1680156101165780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6101636004803603602081101561013a57600080fd5b50357fffffffff000000000000000000000000000000000000000000000000000000001661057f565b604080519115158252519081900360200190f35b610163610618565b610187610621565b60408051918252519081900360200190f35b6101a1610627565b6040805173ffffffffffffffffffffffffffffffffffffffff9092168252519081900360200190f35b6101e9600480360360208110156101e057600080fd5b50351515610643565b005b6103bf600480360360a081101561020157600080fd5b73ffffffffffffffffffffffffffffffffffffffff823581169260208101359091169181019060608101604082013564010000000081111561024257600080fd5b82018360208201111561025457600080fd5b8035906020019184602083028401116401000000008311171561027657600080fd5b91908080602002602001604051908101604052809392919081815260200183836020028082843760009201919091525092959493602081019350359150506401000000008111156102c657600080fd5b8201836020820111156102d857600080fd5b803590602001918460208302840111640100000000831117156102fa57600080fd5b919080806020026020016040519081016040528093929190818152602001838360200280828437600092019190915250929594936020810193503591505064010000000081111561034a57600080fd5b82018360208201111561035c57600080fd5b8035906020019184600183028401116401000000008311171561037e57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550610674945050505050565b604080517fffffffff000000000000000000000000000000000000000000000000000000009092168252519081900360200190f35b610187610d28565b6103bf600480360360a081101561041257600080fd5b73ffffffffffffffffffffffffffffffffffffffff823581169260208101359091169160408201359160608101359181019060a08101608082013564010000000081111561045f57600080fd5b82018360208201111561047157600080fd5b8035906020019184600183028401116401000000008311171561049357600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550610d2e945050505050565b60018054604080516020600284861615610100027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0190941693909304601f810184900484028201840190925281815292918301828280156105775780601f1061054c57610100808354040283529160200191610577565b820191906000526020600020905b81548152906001019060200180831161055a57829003601f168201915b505050505081565b60007f01ffc9a7000000000000000000000000000000000000000000000000000000007fffffffff000000000000000000000000000000000000000000000000000000008316148061061257507f4e2312e0000000000000000000000000000000000000000000000000000000007fffffffff000000000000000000000000000000000000000000000000000000008316145b92915050565b60005460ff1681565b60045481565b60025473ffffffffffffffffffffffffffffffffffffffff1681565b600080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0016911515919091179055565b60006060845167ffffffffffffffff8111801561069057600080fd5b506040519080825280602002602001820160405280156106ba578160200160208202803683370190505b5090506060855167ffffffffffffffff811180156106d757600080fd5b50604051908082528060200260200182016040528015610701578160200160208202803683370190505b50905060005b8651811015610791578783828151811061071d57fe5b602002602001019073ffffffffffffffffffffffffffffffffffffffff16908173ffffffffffffffffffffffffffffffffffffffff16815250503082828151811061076457fe5b73ffffffffffffffffffffffffffffffffffffffff90921660209283029190910190910152600101610707565b5060603373ffffffffffffffffffffffffffffffffffffffff16634e1273f484896040518363ffffffff1660e01b8152600401808060200180602001838103835285818151815260200191508051906020019060200280838360005b838110156108055781810151838201526020016107ed565b50505050905001838103825284818151815260200191508051906020019060200280838360005b8381101561084457818101518382015260200161082c565b5050505090500194505050505060006040518083038186803b15801561086957600080fd5b505afa15801561087d573d6000803e3d6000fd5b505050506040513d6000823e601f3d9081017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe016820160405260208110156108c457600080fd5b81019080805160405193929190846401000000008211156108e457600080fd5b9083019060208201858111156108f957600080fd5b825186602082028301116401000000008211171561091657600080fd5b82525081516020918201928201910280838360005b8381101561094357818101518382015260200161092b565b50505050905001604052505050905060603373ffffffffffffffffffffffffffffffffffffffff16634e1273f4848a6040518363ffffffff1660e01b8152600401808060200180602001838103835285818151815260200191508051906020019060200280838360005b838110156109c55781810151838201526020016109ad565b50505050905001838103825284818151815260200191508051906020019060200280838360005b83811015610a045781810151838201526020016109ec565b5050505090500194505050505060006040518083038186803b158015610a2957600080fd5b505afa158015610a3d573d6000803e3d6000fd5b505050506040513d6000823e601f3d9081017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe01682016040526020811015610a8457600080fd5b8101908080516040519392919084640100000000821115610aa457600080fd5b908301906020820185811115610ab957600080fd5b8251866020820283011164010000000082111715610ad657600080fd5b82525081516020918201928201910280838360005b83811015610b03578181015183820152602001610aeb565b5050505090500160405250505090507f342e0fabcfd1ee833d876ecb1c45c3c2128e88b7cb5ba33cb71476504c75ac9689308484604051808573ffffffffffffffffffffffffffffffffffffffff1681526020018473ffffffffffffffffffffffffffffffffffffffff1681526020018060200180602001838103835285818151815260200191508051906020019060200280838360005b83811015610bb3578181015183820152602001610b9b565b50505050905001838103825284818151815260200191508051906020019060200280838360005b83811015610bf2578181015183820152602001610bda565b50505050905001965050505050505060405180910390a1855115610cb55760405160200180807f48656c6c6f2066726f6d20746865206f74686572207369646500000000000000815250601901905060405160208183030381529060405280519060200120868051906020012014610cb5576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526036815260200180610fcb6036913960400191505060405180910390fd5b60005460ff16151560011415610cf257507fdeadbeef000000000000000000000000000000000000000000000000000000009350610d1f92505050565b507fbc197c81000000000000000000000000000000000000000000000000000000009350610d1f92505050565b95945050505050565b60035481565b6000803373ffffffffffffffffffffffffffffffffffffffff1662fdd58e87876040518363ffffffff1660e01b8152600401808373ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060206040518083038186803b158015610d9f57600080fd5b505afa158015610db3573d6000803e3d6000fd5b505050506040513d6020811015610dc957600080fd5b5051604080517efdd58e000000000000000000000000000000000000000000000000000000008152306004820152602481018890529051919250600091339162fdd58e916044808301926020929190829003018186803b158015610e2c57600080fd5b505afa158015610e40573d6000803e3d6000fd5b505050506040513d6020811015610e5657600080fd5b50516040805173ffffffffffffffffffffffffffffffffffffffff8a1681523060208201528082018590526060810183905290519192507f35754fc132e57c492c060947310a879a2a3bc6d8360c268803988f6366a5ffa2919081900360800190a1835115610f645760405160200180807f48656c6c6f2066726f6d20746865206f74686572207369646500000000000000815250601901905060405160208183030381529060405280519060200120848051906020012014610f64576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526036815260200180610fcb6036913960400191505060405180910390fd5b60005460ff16151560011415610f9f57507fdeadbeef000000000000000000000000000000000000000000000000000000009150610d1f9050565b507ff23a6e61000000000000000000000000000000000000000000000000000000009150610d1f905056fe4552433131353552656365697665724d6f636b236f6e4552433131353552656365697665643a20554e45585045435445445f44415441a264697066735822122026952f1e785831a8f96f443a0e8dcf3d98fb633792d8405ec25d5ff77afe58b064736f6c63430007040033";
