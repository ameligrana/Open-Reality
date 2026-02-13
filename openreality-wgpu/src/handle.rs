use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

/// Type-safe handle store mapping opaque u64 handles to values.
/// Julia holds these handles and passes them back via FFI.
pub struct HandleStore<T> {
    items: HashMap<u64, T>,
}

impl<T> HandleStore<T> {
    pub fn new() -> Self {
        Self {
            items: HashMap::new(),
        }
    }

    /// Insert an item and return its opaque handle.
    pub fn insert(&mut self, item: T) -> u64 {
        let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
        self.items.insert(handle, item);
        handle
    }

    /// Get an immutable reference by handle.
    pub fn get(&self, handle: u64) -> Option<&T> {
        self.items.get(&handle)
    }

    /// Get a mutable reference by handle.
    pub fn get_mut(&mut self, handle: u64) -> Option<&mut T> {
        self.items.get_mut(&handle)
    }

    /// Remove and return the item.
    pub fn remove(&mut self, handle: u64) -> Option<T> {
        self.items.remove(&handle)
    }

    /// Iterate over all items.
    pub fn iter(&self) -> impl Iterator<Item = (&u64, &T)> {
        self.items.iter()
    }

    /// Number of stored items.
    pub fn len(&self) -> usize {
        self.items.len()
    }

    /// Clear all items, running destructors.
    pub fn clear(&mut self) {
        self.items.clear();
    }
}

impl<T> Default for HandleStore<T> {
    fn default() -> Self {
        Self::new()
    }
}
