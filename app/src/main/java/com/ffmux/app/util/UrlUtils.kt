package com.ffmux.app.util

object UrlUtils {

    private val urlRegex = Regex("""https?://\S+""")

    fun extractFirstUrl(text: String): String? =
        urlRegex.find(text)?.value
            ?.trimEnd('.', ',', ';', ')')
            ?.takeIf { it.isNotBlank() }
}
