package com.microbargain.micro_bargain

/**
 * Reads the parts of an Android native-crash tombstone (protobuf, Android 12+) that tell what crashed:
 * the signal, the cause, and the crashing thread's backtrace. Falls back to the readable text in the file.
 * Field numbers: system/core/debuggerd/proto/tombstone.proto.
 */
object Tombstone {
    private class Field(val number: Int, val varint: Long, val bytes: ByteArray?)

    private fun parse(data: ByteArray): List<Field> {
        val fields = mutableListOf<Field>()
        var i = 0
        fun varint(): Long {
            var result = 0L
            var shift = 0
            while (true) {
                val b = data[i++].toInt() and 0xFF
                result = result or ((b and 0x7F).toLong() shl shift)
                if (b < 0x80) return result
                shift += 7
            }
        }
        while (i < data.size) {
            val key = varint()
            val number = (key ushr 3).toInt()
            when ((key and 7).toInt()) {
                0 -> fields += Field(number, varint(), null)
                1 -> i += 8
                2 -> {
                    val length = varint().toInt()
                    fields += Field(number, 0, data.copyOfRange(i, i + length))
                    i += length
                }
                5 -> i += 4
                else -> throw IllegalArgumentException("wire type")
            }
        }
        return fields
    }

    private fun List<Field>.text(number: Int) = firstOrNull { it.number == number }?.bytes?.let { String(it) } ?: ""
    private fun List<Field>.number(number: Int) = firstOrNull { it.number == number }?.varint ?: 0L

    fun describe(data: ByteArray): String = try {
        val top = parse(data)
        val tid = top.number(6)
        val signal = top.firstOrNull { it.number == 10 }?.bytes?.let { parse(it) }
        val out = StringBuilder()
        if (signal != null) {
            out.append("Signal: ${signal.text(2)} ${signal.text(4)} fault addr 0x${java.lang.Long.toHexString(signal.number(9))}\n")
        }
        top.text(14).takeIf { it.isNotEmpty() }?.let { out.append("Abort: $it\n") }
        top.filter { it.number == 15 }.forEach { cause -> out.append("Cause: ${parse(cause.bytes!!).text(1)}\n") }
        for (entry in top.filter { it.number == 16 }) {
            val pair = parse(entry.bytes!!)
            val thread = pair.firstOrNull { it.number == 2 }?.bytes?.let { parse(it) } ?: continue
            if (thread.number(1) != tid) continue
            out.append("\nCrashed thread: ${thread.text(2)} (tid $tid)\n")
            thread.filter { it.number == 4 }.forEachIndexed { index, frame ->
                val f = parse(frame.bytes!!)
                val file = f.text(6).substringAfterLast('/')
                val function = f.text(4).ifEmpty { "?" }
                out.append("#${index.toString().padStart(2, '0')} pc ${java.lang.Long.toHexString(f.number(1))} $file ($function+${f.number(5)})\n")
            }
        }
        out.toString().ifBlank { readable(data) }
    } catch (_: Throwable) {
        readable(data)
    }

    private fun readable(data: ByteArray) =
        Regex("[\\x20-\\x7E]{6,}").findAll(String(data, Charsets.ISO_8859_1)).take(400).joinToString("\n") { it.value }
}
