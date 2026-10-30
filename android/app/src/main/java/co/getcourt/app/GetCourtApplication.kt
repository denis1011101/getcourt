package co.getcourt.app

import android.app.Application
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerFragmentDestinations

class GetCourtApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(assetFilePath = "json/configuration.json")
        )
        Hotwire.defaultFragmentDestination = WebFragment::class
        Hotwire.registerFragmentDestinations(WebFragment::class)
        Hotwire.config.applicationUserAgentPrefix = "GetCourt Android;"
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG
    }
}
