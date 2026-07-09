package com.submersion.libdivecomputer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

// JVM tests for the chunk-reassembly logic behind UsbSerialIoStream.read.
//
// The scenarios mirror the Mares Puck Pro handshake from issue #318: the
// device answers a 2-byte command with ACK + payload + EOM in a single USB
// bulk packet, while libdivecomputer reads it back in 1-byte and N-byte
// slices and expects tty semantics (surplus bytes stay available).
class SerialReadBufferTest {

    private companion object {
        const val CHUNK = 64
    }

    private fun bytes(range: IntRange) = range.map { it.toByte() }.toByteArray()

    @Test
    fun servesRequestFromSingleLargerChunkAndBuffersSurplus() {
        val buffer = SerialReadBuffer(CHUNK)
        var calls = 0
        val payload = bytes(1..6)

        val first = buffer.read(1, 3000) { dest, _ ->
            calls++
            System.arraycopy(payload, 0, dest, 0, payload.size)
            payload.size
        }

        assertArrayEquals(byteArrayOf(1), first)
        assertEquals(1, calls)

        // The remaining 5 bytes must come from the buffer without touching USB.
        val second = buffer.read(5, 3000) { _, _ ->
            fail("must not issue a USB read while buffered bytes remain")
            0
        }
        assertArrayEquals(bytes(2..6), second)
    }

    @Test
    fun neverPassesBufferSmallerThanMinChunkSize() {
        val buffer = SerialReadBuffer(CHUNK)

        buffer.read(1, 3000) { dest, _ ->
            // A bulk read with a buffer smaller than the endpoint packet size
            // fails with EOVERFLOW and loses the packet (issue #318).
            assertTrue(
                "USB buffer was ${dest.size}, smaller than one bulk packet",
                dest.size >= CHUNK,
            )
            dest[0] = 42
            1
        }
    }

    @Test
    fun accumulatesAcrossMultipleChunks() {
        val buffer = SerialReadBuffer(CHUNK)
        val deliveries = listOf(bytes(1..4), bytes(5..8), bytes(9..10))
        var call = 0

        val result = buffer.read(10, 3000) { dest, _ ->
            val chunk = deliveries[call++]
            System.arraycopy(chunk, 0, dest, 0, chunk.size)
            chunk.size
        }

        assertArrayEquals(bytes(1..10), result)
        assertEquals(3, call)
    }

    @Test
    fun emptySliceDoesNotAbortReadWithPositiveTimeout() {
        val buffer = SerialReadBuffer(CHUNK)
        var call = 0

        val result = buffer.read(1, 3000) { dest, _ ->
            when (call++) {
                0 -> 0 // stray zero-length transfer must not fake a timeout
                else -> {
                    dest[0] = 7
                    1
                }
            }
        }

        assertArrayEquals(byteArrayOf(7), result)
        assertEquals(2, call)
    }

    @Test
    fun returnsNullOnceDeadlinePasses() {
        var nowMs = 0L
        val buffer = SerialReadBuffer(CHUNK, nowNanos = { nowMs * 1_000_000L })
        var calls = 0

        val result = buffer.read(1, 3000) { _, _ ->
            calls++
            nowMs += 500
            0
        }

        assertNull(result)
        // Slices at t=0,500,...,2500; the deadline check stops the loop at 3000.
        assertEquals(6, calls)
    }

    @Test
    fun sliceTimeoutShrinksTowardDeadline() {
        var nowMs = 0L
        val buffer = SerialReadBuffer(CHUNK, nowNanos = { nowMs * 1_000_000L })
        val slices = mutableListOf<Int>()

        buffer.read(1, 3000) { _, slice ->
            slices.add(slice)
            nowMs += 1000
            0
        }

        assertEquals(listOf(3000, 2000, 1000), slices)
    }

    @Test
    fun nonBlockingReadStopsAtFirstEmptySlice() {
        val buffer = SerialReadBuffer(CHUNK)
        val slices = mutableListOf<Int>()

        val result = buffer.read(1, 0) { _, slice ->
            slices.add(slice)
            0
        }

        assertNull(result)
        // libdivecomputer's non-blocking read maps to a single minimal slice.
        assertEquals(listOf(1), slices)
    }

    @Test
    fun infiniteTimeoutUsesBlockingSliceAndRetriesEmptySlices() {
        val buffer = SerialReadBuffer(CHUNK)
        var call = 0
        val slices = mutableListOf<Int>()

        val result = buffer.read(1, -1) { dest, slice ->
            slices.add(slice)
            when (call++) {
                0 -> 0
                else -> {
                    dest[0] = 9
                    1
                }
            }
        }

        assertArrayEquals(byteArrayOf(9), result)
        // usb-serial-for-android treats timeout 0 as "block until data".
        assertEquals(listOf(0, 0), slices)
    }

    @Test
    fun clearDropsBufferedSurplus() {
        val buffer = SerialReadBuffer(CHUNK)
        buffer.read(1, 3000) { dest, _ ->
            System.arraycopy(bytes(1..6), 0, dest, 0, 6)
            6
        }

        buffer.clear()

        val result = buffer.read(1, 3000) { dest, _ ->
            dest[0] = 99
            1
        }
        assertArrayEquals(byteArrayOf(99), result)
    }

    @Test
    fun zeroSizeReadReturnsEmptyWithoutUsbRead() {
        val buffer = SerialReadBuffer(CHUNK)
        val result = buffer.read(0, 3000) { _, _ ->
            fail("zero-size read must not touch USB")
            0
        }
        assertArrayEquals(ByteArray(0), result)
    }

    @Test
    fun surplusFromFinalChunkOfMultiChunkReadIsPreserved() {
        val buffer = SerialReadBuffer(CHUNK)
        val deliveries = listOf(bytes(1..4), bytes(5..12))
        var call = 0

        val first = buffer.read(6, 3000) { dest, _ ->
            val chunk = deliveries[call++]
            System.arraycopy(chunk, 0, dest, 0, chunk.size)
            chunk.size
        }
        assertArrayEquals(bytes(1..6), first)

        val second = buffer.read(6, 3000) { _, _ ->
            fail("must not issue a USB read while buffered bytes remain")
            0
        }
        assertArrayEquals(bytes(7..12), second)
    }
}
