package com.neutrinographics.bluey

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class PendingRequestRegistryTest {

    @Test
    fun `put then pop returns the entry`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "a")
        assertEquals("a", registry.pop(1L))
    }

    @Test
    fun `pop returns null for unknown id`() {
        val registry = PendingRequestRegistry<String>()
        assertNull(registry.pop(99L))
    }

    @Test
    fun `pop twice returns null the second time`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "a")
        assertEquals("a", registry.pop(1L))
        assertNull(registry.pop(1L))
    }

    @Test
    fun `put with duplicate id overwrites`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "first")
        registry.put(1L, "second")
        assertEquals("second", registry.pop(1L))
    }

    @Test
    fun `drainWhere removes and returns matching entries`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "keep")
        registry.put(2L, "drain")
        registry.put(3L, "drain")
        val drained = registry.drainWhere { it == "drain" }
        assertEquals(2, drained.size)
        assertTrue(drained.containsAll(listOf("drain", "drain")))
    }

    @Test
    fun `drainWhere leaves non-matching entries in place`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "keep")
        registry.put(2L, "drain")
        registry.drainWhere { it == "drain" }
        assertEquals("keep", registry.pop(1L))
        assertNull(registry.pop(2L))
    }

    @Test
    fun `clear returns all entries and empties the registry`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "a")
        registry.put(2L, "b")
        val cleared = registry.clear()
        assertEquals(2, cleared.size)
        assertTrue(cleared.containsAll(listOf("a", "b")))
        assertEquals(0, registry.size)
    }

    @Test
    fun `size reflects live entries`() {
        val registry = PendingRequestRegistry<String>()
        assertEquals(0, registry.size)
        registry.put(1L, "a")
        assertEquals(1, registry.size)
        registry.put(2L, "b")
        assertEquals(2, registry.size)
        registry.pop(1L)
        assertEquals(1, registry.size)
    }

    @Test
    fun `concurrent put and pop across many threads does not corrupt state`() {
        val registry = PendingRequestRegistry<Int>()
        val threadCount = 16
        val opsPerThread = 500
        val executor = java.util.concurrent.Executors.newFixedThreadPool(threadCount)
        val startLatch = java.util.concurrent.CountDownLatch(1)
        val doneLatch = java.util.concurrent.CountDownLatch(threadCount)

        repeat(threadCount) { threadIdx ->
            executor.submit {
                startLatch.await()
                val base = threadIdx.toLong() * opsPerThread
                // Each thread puts and pops its own disjoint id range
                for (i in 0 until opsPerThread) {
                    registry.put(base + i, threadIdx * 1000 + i)
                }
                for (i in 0 until opsPerThread) {
                    val v = registry.pop(base + i)
                    assertEquals(threadIdx * 1000 + i, v)
                }
                doneLatch.countDown()
            }
        }

        startLatch.countDown()
        assertTrue(doneLatch.await(10, java.util.concurrent.TimeUnit.SECONDS))
        executor.shutdown()
        assertEquals(0, registry.size)
    }
}
