package co.getcourt.app

import java.net.URI

internal object TrustedUrl {
    fun allows(value: String, debug: Boolean): Boolean = runCatching {
        val uri = URI(value)
        uri.rawUserInfo == null && !uri.isOpaque && (
            (uri.scheme == "https" && uri.host == "getcourt.co" && uri.port in listOf(-1, 443)) ||
                (debug && uri.scheme == "http" && uri.host == "localhost" && uri.port == 3000)
            )
    }.getOrDefault(false)
}
