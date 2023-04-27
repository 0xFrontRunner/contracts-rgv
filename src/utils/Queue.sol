// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Queue {
    // Define the struct for the queue elements
    struct WithdrawalItem {
        address recipient;
        uint256 shares;
        uint256 amount;
        uint256 timestamp;
    }

    // Declare the queue array
    WithdrawalItem[] public withdrawals;

    // Declare and initialize the front and rear indices
    uint256 internal front = 0;
    uint256 internal rear = 0;

    // Function to add an element to the queue
    function enqueue(WithdrawalItem memory _item) internal {
        withdrawals.push(_item);
        rear++;
    }

    // Function to remove an element from the queue
    function dequeue() internal returns (WithdrawalItem memory) {
        require(front < rear, "Queue is empty");

        WithdrawalItem memory itemToReturn = withdrawals[front];
        delete withdrawals[front];
        front++;

        return itemToReturn;
    }

    // Function to check if the queue is empty
    function withdrawalsIsEmpty() public view returns (bool) {
        return front == rear;
    }

    // Function to get the current size of the queue
    function withdrawalsLenght() public view returns (uint256) {
        return rear - front;
    }
}
