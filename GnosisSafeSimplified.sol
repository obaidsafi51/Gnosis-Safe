// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GnosisSafeSimplified {
    // Events
    event SafeInitialized(address[] owners, uint256 threshold);
    event TransactionProposed(uint256 indexed transactionId, address indexed owner, address destination, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed owner);
    event TransactionExecuted(uint256 indexed transactionId, address indexed owner);

    // Data Structures
    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmationsCount;
    }

    // State Variables
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public threshold;
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;

    // Modifiers
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier transactionExists(uint256 transactionId) {
        require(transactionId < transactions.length, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 transactionId) {
        require(!transactions[transactionId].executed, "Transaction already executed");
        _;
    }

    // Constructor
    constructor(address[] memory _owners, uint256 _threshold) {
        require(_owners.length > 0, "At least one owner required");
        require(_threshold > 0 && _threshold <= _owners.length, "Invalid threshold");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner address");
            require(!isOwner[owner], "Duplicate owner");

            isOwner[owner] = true;
            owners.push(owner);
        }

        threshold = _threshold;
        emit SafeInitialized(_owners, _threshold);
    }

    // Functions
    function submitTransaction(address destination, uint256 value, bytes calldata data) public onlyOwner {
        uint256 transactionId = transactions.length;
        transactions.push(Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false,
            confirmationsCount: 0
        }));
        emit TransactionProposed(transactionId, msg.sender, destination, value, data);
        confirmTransaction(transactionId); // Automatically confirm the transaction for the proposer
    }

    function confirmTransaction(uint256 transactionId) public onlyOwner transactionExists(transactionId) notExecuted(transactionId) {
        require(!confirmations[transactionId][msg.sender], "Transaction already confirmed");

        confirmations[transactionId][msg.sender] = true;
        transactions[transactionId].confirmationsCount += 1;
        emit TransactionConfirmed(transactionId, msg.sender);
    }

    function executeTransaction(uint256 transactionId) public onlyOwner transactionExists(transactionId) notExecuted(transactionId) {
        require(transactions[transactionId].confirmationsCount >= threshold, "Not enough confirmations");

        Transaction storage transaction = transactions[transactionId];
        transaction.executed = true;
        (bool success, ) = transaction.destination.call{value: transaction.value}(transaction.data);
        require(success, "Transaction execution failed");
        emit TransactionExecuted(transactionId, msg.sender);
    }

    // View Functions
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getTransaction(uint256 transactionId) public view returns (address destination, uint256 value, bytes memory data, bool executed, uint256 confirmationsCount) {
        Transaction storage transaction = transactions[transactionId];
        return (
            transaction.destination,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.confirmationsCount
        );
    }
}