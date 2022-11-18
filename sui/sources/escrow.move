// SPDX-License-Identifier: MIT

/// @title escrow
/// @dev Basic escrow module: holds an object designated for a recipient until the sender approves withdrawal.
module movemate::escrow {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    struct Escrow<T: key + store> has key {
        id: UID,
        recipient: address,
        obj: T
    }

    /// @dev Stores the sent object in an escrow object.
    /// @param recipient The destination address of the escrowed object.
    public entry fun escrow<T: key + store>(sender: address, recipient: address, obj_in: T, ctx: &mut TxContext) {
        let escrow = Escrow<T> {
            id: object::new(ctx),
            recipient,
            obj: obj_in
        };
        transfer::transfer(escrow, sender);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer<T: key + store>(escrow: Escrow<T>) {
        let Escrow {
            id: info,
            recipient: recipient,
            obj: obj,
        } = escrow;
        object::delete(info);
        transfer::transfer(obj, recipient);
    }

    #[test_only]
    use sui::test_scenario;

    #[test_only]
    const TEST_SENDER_ADDR: address = @0xA11CE;

    #[test_only]
    const TEST_RECIPIENT_ADDR: address = @0xB0B;

    #[test_only]
    struct FakeObject has key, store {
        id: UID,
        data: u64
    }

    #[test]
    public fun test_end_to_end() {
        let scenario_wrapper = test_scenario::begin(TEST_SENDER_ADDR);
        let scenario = &mut scenario_wrapper;
        escrow(TEST_SENDER_ADDR, TEST_RECIPIENT_ADDR, FakeObject { id: object::new(test_scenario::ctx(scenario)), data: 1234 }, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, TEST_SENDER_ADDR);
        let escrow = test_scenario::take_from_sender<Escrow<FakeObject>>(scenario);
        transfer(escrow);
        test_scenario::next_tx(scenario, TEST_RECIPIENT_ADDR);
        let obj = test_scenario::take_from_sender<FakeObject>(scenario);
        assert!(obj.data == 1234, 0);
        test_scenario::return_to_sender(scenario, obj);
        test_scenario::end(scenario_wrapper);
    }
}
