/// @title box
/// @notice Generalized box for transferring objects to arbitrary recipients.
module movemate::box {
    use std::error;
    use std::signer;
    use std::vector;

    use aptos_std::table::{Self, Table};

    /// @dev When trying to call `box` before calling `init`.
    const ESENDER_BOXES_NOT_INITIALIZED: u64 = 0;

    struct Boxes<T: store> has key, store {
        boxes: Table<address, vector<T>>
    }

    struct PrivateBoxes<T: store> has key, store {
        boxes: Table<address, vector<T>>
    }

    /// @dev Enables boxing of type `T` under `sender`.
    public entry fun init<T: store>(sender: &signer) {
        move_to(sender, Boxes<T> {
            boxes: table::new()
        });
    }

    /// @dev Stores the sent object in an box object.
    /// @param recipient The destination address of the box object.
    public entry fun box<T: store>(sender: address, recipient: address, obj_in: T) acquires Boxes {
        assert!(exists<Boxes<T>>(sender), error::not_found(ESENDER_BOXES_NOT_INITIALIZED));
        let boxes = &mut borrow_global_mut<Boxes<T>>(sender).boxes;
        let box = table::borrow_mut(boxes, recipient);
        vector::push_back(box, obj_in);
    }

    /// @dev Unboxes the object inside the box.
    public entry fun unbox<T: store>(sender: address, recipient: &signer, index: u64): T acquires Boxes {
        let boxes = &mut borrow_global_mut<Boxes<T>>(sender).boxes;
        let box = table::borrow_mut(boxes, signer::address_of(recipient));
        vector::swap_remove(box, index)
    }

    /// @dev Stores the sent object in an private box object. (Private box = verified senders only.)
    /// @param recipient The destination address of the box object.
    public entry fun box_private<T: store>(sender: &signer, recipient: address, obj_in: T) acquires PrivateBoxes {
        let sender_address = signer::address_of(sender);
        if (exists<PrivateBoxes<T>>(sender_address)) {
            let boxes = &mut borrow_global_mut<PrivateBoxes<T>>(sender_address).boxes;
            let box = table::borrow_mut(boxes, recipient);
            vector::push_back(box, obj_in);
        } else {
            let boxes = table::new<address, vector<T>>();
            table::add(&mut boxes, recipient, vector::singleton(obj_in));
            move_to(sender, Boxes<T> {
                boxes
            });
        }
    }

    /// @dev Unboxes the object inside the private box. (Private box = verified senders only.)
    public entry fun unbox_private<T: store>(sender: address, recipient: &signer, index: u64): T acquires PrivateBoxes {
        let boxes = &mut borrow_global_mut<PrivateBoxes<T>>(sender).boxes;
        let box = table::borrow_mut(boxes, signer::address_of(recipient));
        vector::swap_remove(box, index)
    }
}
