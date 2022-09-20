/// @title box
/// @notice Generalized box for transferring objects that only have `store` but not `key`.
module movemate::box {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct Box<T: store> has key, store {
        id: UID,
        obj: T
    }

    struct PrivateBox<T: store> has key, store {
        id: UID,
        obj: T,
        sender: address
    }

    /// @dev Stores the sent object in an box object.
    /// @param recipient The destination address of the box object.
    public entry fun box<T: store>(recipient: address, obj_in: T, ctx: &mut TxContext) {
        let box = Box<T> {
            id: object::new(ctx),
            obj: obj_in
        };
        transfer::transfer(box, recipient);
    }

    /// @dev Unboxes the object inside the box.
    public fun unbox<T: store>(box: Box<T>): T {
        let Box {
            id: id,
            obj: obj,
        } = box;
        object::delete(id);
        obj
    }

    /// @dev Stores the sent object in a private box object. (Private box = stores the sender in the sender property.)
    /// @param recipient The destination address of the box object.
    public entry fun box_private<T: store>(recipient: address, obj_in: T, ctx: &mut TxContext) {
        let box = PrivateBox<T> {
            id: object::new(ctx),
            obj: obj_in,
            sender: tx_context::sender(ctx)
        };
        transfer::transfer(box, recipient);
    }

    /// @dev Unboxes the object inside the private box. (Private box = stores the sender in the sender property.)
    public fun unbox_private<T: store>(box: PrivateBox<T>): T {
        let PrivateBox {
            id: id,
            obj: obj,
            sender: _
        } = box;
        object::delete(id);
        obj
    }
}
