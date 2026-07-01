package com.submersion.libdivecomputer

import java.nio.ByteBuffer

/**
 * Encodes/decodes a ParsedDive to a byte[] using the plugin's OWN Pigeon codec
 * (via the public DiveComputerHostApi.codec), so a dive can cross the AIDL
 * boundary from :dc back to the main process without hand-duplicating the
 * 28-field, nested ParsedDive schema. The codec (StandardMessageCodec) already
 * knows how to write/read ParsedDive and its nested ProfileSample/TankInfo/
 * GasMix/DiveEvent types (type byte 136 and friends). See issue #318.
 */
object DiveMarshaling {
    fun encode(dive: ParsedDive): ByteArray {
        // StandardMessageCodec.encodeMessage returns a buffer positioned at the
        // end of the written data; flip to expose [0, size) for reading out.
        val buffer = DiveComputerHostApi.codec.encodeMessage(dive)
            ?: return ByteArray(0)
        buffer.flip()
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        return bytes
    }

    fun decode(bytes: ByteArray): ParsedDive {
        val value = DiveComputerHostApi.codec.decodeMessage(ByteBuffer.wrap(bytes))
        return value as ParsedDive
    }
}
