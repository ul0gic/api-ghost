import Darwin

/// Process resident memory in bytes (mach_task_basic_info). A failure of backpressure anywhere in
/// the in-process origin→proxy→client chain balloons this toward the body size; correct backpressure
/// keeps it flat at window-sized buffers.
enum MachMemory {
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
