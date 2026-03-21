const errors = @import("../core/errors.zig");

fn DriverRcError(comptime FallbackError: type) type {
    const info = @typeInfo(FallbackError);
    if (info != .error_set) {
        @compileError("mapDriverRc fallback must be an error value");
    }
    return errors.DriverMappedError || errors.AllocError || FallbackError;
}

/// Maps driver return codes to stable driver-layer errors plus caller fallback.
pub fn mapDriverRc(comptime Driver: type, rc: i32, fallback: anytype) DriverRcError(@TypeOf(fallback)) {
    return switch (rc) {
        Driver.BUSY => error.DriverBusy,
        Driver.CONSTRAINT => error.DriverConstraint,
        Driver.MISUSE => error.DriverMisuse,
        Driver.IOERR => error.DriverIo,
        Driver.READONLY => error.DriverReadonly,
        Driver.CANTOPEN => error.DriverCantOpen,
        Driver.RANGE => error.DriverRange,
        Driver.TOOBIG => error.DriverTooBig,
        Driver.NOMEM => error.OutOfMemory,
        else => fallback,
    };
}

test "driver_errors: map known codes and fallback" {
    const driver = @import("../driver/sqlite3.zig");

    try std.testing.expectEqual(error.DriverBusy, mapDriverRc(driver, driver.BUSY, error.DriverError));
    try std.testing.expectEqual(error.DriverConstraint, mapDriverRc(driver, driver.CONSTRAINT, error.DriverError));
    try std.testing.expectEqual(error.DriverMisuse, mapDriverRc(driver, driver.MISUSE, error.DriverError));
    try std.testing.expectEqual(error.DriverIo, mapDriverRc(driver, driver.IOERR, error.DriverError));
    try std.testing.expectEqual(error.DriverReadonly, mapDriverRc(driver, driver.READONLY, error.DriverError));
    try std.testing.expectEqual(error.DriverCantOpen, mapDriverRc(driver, driver.CANTOPEN, error.DriverError));
    try std.testing.expectEqual(error.DriverRange, mapDriverRc(driver, driver.RANGE, error.DriverError));
    try std.testing.expectEqual(error.DriverTooBig, mapDriverRc(driver, driver.TOOBIG, error.DriverError));
    try std.testing.expectEqual(error.OutOfMemory, mapDriverRc(driver, driver.NOMEM, error.DriverError));
    try std.testing.expectEqual(error.DriverError, mapDriverRc(driver, driver.OK, error.DriverError));
}

const std = @import("std");
