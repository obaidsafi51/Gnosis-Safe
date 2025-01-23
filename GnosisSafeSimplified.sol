// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GnosisSafeSimplified is ReentrancyGuard {
    // Events
    event SafeInitialized(address[] owners, uint256 threshold);
    event TransactionProposed(uint256 indexed transactionId, address indexed owner, address destination, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed owner);
    event TransactionExecuted(uint256 indexed transactionId, address indexed owner);
    event TransactionCancelled(uint256 indexed transactionId, address indexed owner);
    event TransactionFailed(uint256 indexed transactionId, address indexed destination, uint256 value, bytes data);
    event ThresholdUpdated(uint256 newThreshold);
    event TransactionId(uint256 indexed transactionId);

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
    constructor(address[] memory _owners, uint256 _threshold) payable {
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

    /**
     * @dev Submit a new transaction.
     * @param destination The address to which the transaction is sent.
     * @param value The amount of ETH to send with the transaction.
     * @param data The data payload of the transaction.
     */
    function submitTransaction(address destination, uint256 value, bytes calldata data) public onlyOwner {
        require(destination != address(0), "Invalid destination address");
        require(value <= address(this).balance, "Insufficient contract balance");

        uint256 transactionId = transactions.length;
        transactions.push(Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false,
            confirmationsCount: 0
        }));
        emit TransactionProposed(transactionId, msg.sender, destination, value, data);
    }

    /**
     * @dev Confirm a transaction.
     * @param transactionId The ID of the transaction to confirm.
     */
    function confirmTransaction(uint256 transactionId) public onlyOwner transactionExists(transactionId) notExecuted(transactionId) {
        require(!confirmations[transactionId][msg.sender], "Transaction already confirmed");

        confirmations[transactionId][msg.sender] = true;
        transactions[transactionId].confirmationsCount += 1;
        emit TransactionConfirmed(transactionId, msg.sender);
    }

    /**
     * @dev Execute a confirmed transaction.
     * @param transactionId The ID of the transaction to execute.
     */
    function executeTransaction(uint256 transactionId) public onlyOwner transactionExists(transactionId) notExecuted(transactionId) nonReentrant {
        Transaction storage transaction = transactions[transactionId];
        require(transaction.confirmationsCount >= threshold, "Not enough confirmations");
        require(transaction.destination != address(0), "Invalid destination address");

        // Mark the transaction as executed before the call to prevent reentrancy
        transaction.executed = true;
        emit TransactionExecuted(transactionId, msg.sender);

        // Execute the transaction with a gas limit
        (bool success, ) = transaction.destination.call{value: transaction.value, gas: 300000}(transaction.data);
        if (!success) {
            // Revert the executed flag if the call fails
            transaction.executed = false;
            emit TransactionFailed(transactionId, transaction.destination, transaction.value, transaction.data);
            revert("Transaction execution failed");
        }
    }

    /**
     * @dev Cancel a transaction.
     * @param transactionId The ID of the transaction to cancel.
     */
    function cancelTransaction(uint256 transactionId) public onlyOwner transactionExists(transactionId) notExecuted(transactionId) {
        require(confirmations[transactionId][msg.sender], "You have not confirmed this transaction");

        transactions[transactionId].executed = true; // Mark as executed to prevent further actions
        emit TransactionCancelled(transactionId, msg.sender);
    }

    /**
     * @dev Update the threshold for confirming transactions.
     * @param newThreshold The new threshold value.
     */
    function updateThreshold(uint256 newThreshold) public onlyOwner {
        require(newThreshold > 0 && newThreshold <= owners.length, "Invalid threshold");
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    // View Functions

    /**
     * @dev Get the list of owners.
     * @return The list of owner addresses.
     */
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev Get the total number of transactions.
     * @return The number of transactions.
     */
    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev Get details of a specific transaction.
     * @param transactionId The ID of the transaction.
     * @return destination The destination address.
     * @return value The amount of ETH to send.
     * @return data The data payload.
     * @return executed Whether the transaction has been executed.
     * @return confirmationsCount The number of confirmations.
     */
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

    // Allow the contract to accept ETH
    receive() external payable {}
}