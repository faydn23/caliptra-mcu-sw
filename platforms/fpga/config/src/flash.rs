// Licensed under the Apache-2.0 license

// HTG940_STANDALONE_FIRMWARE_BRAM
// 2 MiB volatile layout:
//   0x000000..0x0fffff  Slot A / boot image (Vivado initialized)
//   0x100000..0x1bffff  Slot B / recovery staging (768 KiB)
//   0x1c0000..0x1dffff  external OTP backing (128 KiB)
//   0x1e0000..0x1e7fff  logging (32 KiB)
//   0x1e8000..0x1fffff  reserved

use caliptra_mcu_config::flash::FlashPartition;

pub const DRIVER_NUM_EMULATED_FLASH_CTRL: usize = 0x8000_0012;
pub const BLOCK_SIZE: usize = 64 * 1024;

pub const STAGING_PARTITION: FlashPartition = FlashPartition {
    name: "staging_par",
    offset: 0x0010_0000,
    size: BLOCK_SIZE * 12,
    driver_num: DRIVER_NUM_EMULATED_FLASH_CTRL as u32,
};

pub const EMULATED_EXT_OTP_PARTITION: FlashPartition = FlashPartition {
    name: "emulated_ext_otp",
    offset: 0x001C_0000,
    size: BLOCK_SIZE * 2,
    driver_num: 0x7000_000B,
};

#[macro_export]
macro_rules! flash_partition_list_imaginary_flash {
    ($macro:ident) => {{
        $macro!(0, staging_par, STAGING_PARTITION);
    }};
}

pub const LOGGING_PARTITION: FlashPartition = FlashPartition {
    name: "logging",
    offset: 0x001E_0000,
    size: 32 * 1024,
    driver_num: 0x9001_0000,
};
