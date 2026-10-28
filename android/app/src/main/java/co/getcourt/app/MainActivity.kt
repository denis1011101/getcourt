package co.getcourt.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.navigator.NavigatorConfiguration

class MainActivity : HotwireActivity() {
    // App link that opened the activity; routed on top of the start page once the navigator is up.
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        if (savedInstanceState == null) {
            pendingLink = linkFrom(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkFrom(intent)?.let { delegate.currentNavigator?.route(it) }
    }

    override fun onNavigatorReady(navigator: Navigator) {
        val link = pendingLink ?: return
        pendingLink = null
        // The start destination is still being attached here; route once it exists.
        window.decorView.post { navigator.route(link) }
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = "https://getcourt.co/",
            navigatorHostId = R.id.main_nav_host
        )
    )

    private fun linkFrom(intent: Intent?): String? =
        intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString
}
