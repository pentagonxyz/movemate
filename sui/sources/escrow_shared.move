// SPDX-License-Identifier: MIT

/// @title escrow_shared
/// @dev Basic escrow module with refunds and an arbitrator: holds an object designated for a recipient until the sender approves withdrawal, the recipient refunds the sender, or the arbitrator does one of the two.
module movemate::escrow_shared {
    use std::option::{Self, Option};

    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// @dev When trying to transfer escrowed object to the recipient but you are not the sender.
    const ENOT_SENDER: u64 = 0x10000;

    /// @dev When trying to refund escrowed object to the sender but you are not the recipient.
    const ENOT_RECIPIENT: u64 = 0x10001;

    /// @dev When trying to arbitrate an escrowed object but you are not the arbitrator.
    const ENOT_ARBITRATOR: u64 = 0x10002;

    struct Escrow<T: key + store> has key {
        id: UID,
        sender: address,
        recipient: address,
        arbitrator: Option<address>,
        obj: Option<T>
    }

    /// @dev Stores the sent object in an escrow object.
    /// @param recipient The destination address of the escrowed object.
    public entry fun escrow<T: key + store>(sender: address, recipient: address, arbitrator: Option<address>, obj_in: T, ctx: &mut TxContext) {
        let escrow = Escrow<T> {
            id: object::new(ctx),
            sender,
            recipient,
            arbitrator,
            obj: option::some(obj_in)
        };
        transfer::share_object(escrow);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == escrow.sender, ENOT_SENDER);
        transfer::transfer(option::extract(&mut escrow.obj), escrow.recipient);
    }

    /// @dev Refunds escrowed object to the sender.
    public entry fun refund<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == escrow.recipient, ENOT_RECIPIENT);
        transfer::transfer(option::extract(&mut escrow.obj), escrow.sender);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer_arbitrated<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(option::is_some(&escrow.arbitrator) && tx_context::sender(ctx) == *option::borrow(&escrow.arbitrator), ENOT_ARBITRATOR);
        transfer::transfer(option::extract(&mut escrow.obj), escrow.recipient);
    }

    /// @dev Refunds escrowed object to the sender.
    public entry fun refund_arbitrated<T: key + store>(escrow: &mut Escrow<T>, ctx: &mut TxContext) {
        assert!(option::is_some(&escrow.arbitrator) && tx_context::sender(ctx) == *option::borrow(&escrow.arbitrator), ENOT_ARBITRATOR);
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
        id: UID,
        data: u64
    }

    #[test]
    public fun test_transfer() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_SENDER_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        transfer(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::next_tx(scenario, TEST_RECIPIENT_ADDR);
        let obj = test_scenario::take_from_sender<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_to_sender(scenario, obj);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    public fun test_refund() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_RECIPIENT_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        refund(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::next_tx(scenario, TEST_SENDER_ADDR);
        let obj = test_scenario::take_from_sender<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_to_sender(scenario, obj);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    public fun test_transfer_arbitrator() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_ARBITRATOR_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        transfer_arbitrated(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::next_tx(scenario, TEST_RECIPIENT_ADDR);
        let obj = test_scenario::take_from_sender<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_to_sender(scenario, obj);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    public fun test_refund_arbitrator() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_ARBITRATOR_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        refund_arbitrated(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::next_tx(scenario, TEST_SENDER_ADDR);
        let obj = test_scenario::take_from_sender<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_to_sender(scenario, obj);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_SENDER)]
    public fun test_transfer_unauthorized() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_RECIPIENT_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        transfer(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_RECIPIENT)]
    public fun test_refund_unauthorized() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_SENDER_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        refund(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_ARBITRATOR)]
    public fun test_transfer_arbitrator_unauthorized() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_RECIPIENT_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        transfer_arbitrated(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::end(scenario_wrapper);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_ARBITRATOR)]
    public fun test_refund_arbitrator_unauthorized() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, option::some(TEST_ARBITRATOR_ADDR), FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_SENDER_ADDR);
        let escrow_wrapper = test_scenario::take_shared<Escrow<FakeObject>>(scenario);
        refund_arbitrated(&mut escrow_wrapper, test_scenario::ctx(scenario));
        test_scenario::return_shared(escrow_wrapper);
        test_scenario::end(scenario_wrapper);
    }
}
