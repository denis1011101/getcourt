package co.getcourt.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrustedUrlTest {
    @Test fun acceptsProductionLinksAndOrigins() {
        listOf("https://getcourt.co", "https://getcourt.co:443/", "https://getcourt.co/games/12?x=1#score")
            .forEach { assertTrue(it, TrustedUrl.allows(it, false)) }
    }

    @Test fun rejectsUntrustedOrMalformedUrls() {
        listOf("http://getcourt.co/", "https://getcourt.co:444/", "https://user@getcourt.co/",
            "https://getcourt.co.evil.test/", "https://ru.getcourt.co/", "javascript://getcourt.co/x",
            "https://evil.test/", "//getcourt.co/", "not a URL", "https://getcourt.co\\@evil.test/")
            .forEach { assertFalse(it, TrustedUrl.allows(it, true)) }
    }

    @Test fun localhostIsDebugOnlyAndPortIsRestricted() {
        assertTrue(TrustedUrl.allows("http://localhost:3000/games", true))
        assertFalse(TrustedUrl.allows("http://localhost:3000/", false))
        assertFalse(TrustedUrl.allows("http://localhost:3001/", true))
        assertFalse(TrustedUrl.allows("http://user@localhost:3000/", true))
    }
}
