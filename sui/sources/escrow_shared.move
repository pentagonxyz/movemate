// SPDX-License-Identifier: MIT

/// @title escrow_shared
/// @dev Basic escrow module with refunds and an arbitrator: holds an object designated for a recipient until the sender approves withdrawal, the recipient refunds the sender, or the arbitrator does one of the two.
module movemate::escrow_shared {
    use std::errors;
    use std::option::{Self, Option};

    use sui::object::{Self, Info};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// @dev When trying to transfer escrowed object to the recipient but you are not the sender.
    const ENOT_SENDER: u64 = 0;

    /// @dev When trying to refund escrowed object to the sender but you are not the recipient.
    const ENOT_RECIPIENT: u64 = 1;

    /// @dev When trying to arbitrate an escrowed object but you are not the arbitrator.
    const ENOT_ARBITRATOR: u64 = 2;

    struct Escrow<T: key + store> has key {
        info: Info,
        sender: address,
        recipient: address,
        arbitrator: Option<address>,
        obj: Option<T>
    }

    /// @dev Stores the sent object in an escrow object.
    /// @param recipient The destination address of the escrowed object.
    public entry fun escrow<T: key + store>(sender: address, recipient: address, arbitrator: Option<address>, obj_in: T, ctx: &mut TxContext) {
        let escrow = Escrow<T> {
            info: object::new(ctx),
            sender,
            recipient,
            arbitrator,
            obj: option::some(obj_in)
        };
        transfer::share_object(escrow);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == escrow.sender, errors::requires_address(ENOT_SENDER));
        transfer::transfer(option::extract(&mut escrow.obj), escrow.recipient);
    }

    /// @dev Refunds escrowed object to the sender.
    public entry fun refund<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == escrow.recipient, errors::requires_address(ENOT_RECIPIENT));
        transfer::transfer(option::extract(&mut escrow.obj), escrow.sender);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer_arbitrated<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(option::is_some(&escrow.arbitrator) && tx_context::sender(ctx) == *option::borrow(&escrow.arbitrator), errors::requires_address(ENOT_ARBITRATOR));
        transfer::transfer(option::extract(&mut escrow.obj), escrow.recipient);
    }

    /// @dev Refunds escrowed object to the sender.
    public entry fun refund_arbitrated<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(option::is_some(&escrow.arbitrator) && tx_context::sender(ctx) == *option::borrow(&escrow.arbitrator), errors::requires_address(ENOT_ARBITRATOR));
        transfer::transfer(option::extract(&mut escrow.obj), escrow.sender);
    }

    #[test_only]
    use sui::test_scenario;

    #[test_only]
    const TEST_SENDER_ADDR: address = @0xA11CE;

    #[test_only]
    const TEST_RECIPIENT_ADDR: address = @0xB0B;

    #[test_only]
    const TEST_ARBITRATOR_ADDR: address = @0xDAD;

    #[test_only]
    struct FakeObject has key, store {
        info: Info,
        data: u64
    }

    #[test]
    public fun test_transfer() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_SENDER_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        transfer(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
        test_scenario::next_tx(scenario, &TEST_RECIPIENT_ADDR);
        let obj = test_scenario::take_owned<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_owned(scenario, obj);
    }

    #[test]
    public fun test_refund() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_RECIPIENT_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        refund(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
        test_scenario::next_tx(scenario, &TEST_SENDER_ADDR);
        let obj = test_scenario::take_owned<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_owned(scenario, obj);
    }

    #[test]
    public fun test_transfer_arbitrator() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_ARBITRATOR_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        transfer_arbitrated(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
        test_scenario::next_tx(scenario, &TEST_RECIPIENT_ADDR);
        let obj = test_scenario::take_owned<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_owned(scenario, obj);
    }

    #[test]
    public fun test_refund_arbitrator() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_ARBITRATOR_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        refund_arbitrated(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
        test_scenario::next_tx(scenario, &TEST_SENDER_ADDR);
        let obj = test_scenario::take_owned<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_owned(scenario, obj);
    }

    #[test]
    #[expected_failure(abort_code = 0x002)]
    public fun test_transfer_unauthorized() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_RECIPIENT_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        transfer(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = 0x102)]
    public fun test_refund_unauthorized() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_SENDER_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        refund(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = 0x202)]
    public fun test_transfer_arbitrator_unauthorized() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_RECIPIENT_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        transfer_arbitrated(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = 0x202)]
    public fun test_refund_arbitrator_unauthorized() {
        let scenario = &mut test_scenario::begin(&TEST_SENDER_ADDR);
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { info: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, &TEST_SENDER_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        let escrow = test_scenario::borrow_mut(&mut escrow_wrapper);
        refund_arbitrated(escrow, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, escrow_wrapper);
    }
}
