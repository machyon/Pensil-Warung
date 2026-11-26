//! Catat: one Simpan saves a batch of typed lines (sales, restocks, product
//! creates and deletes) atomically. `dto` parses and validates the request,
//! `plan` resolves product names across the batch into an executable plan.

pub mod dto;
