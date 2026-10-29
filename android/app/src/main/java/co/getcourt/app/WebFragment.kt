package co.getcourt.app

import android.Manifest.permission.ACCESS_COARSE_LOCATION
import android.Manifest.permission.ACCESS_FINE_LOCATION
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.webkit.GeolocationPermissions
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import androidx.core.view.updatePadding
import dev.hotwire.core.turbo.config.context
import dev.hotwire.core.turbo.nav.PresentationContext
import dev.hotwire.core.turbo.webview.HotwireWebChromeClient
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment

@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class WebFragment : HotwireWebFragment() {
    private var pendingGeolocation: Pair<String, GeolocationPermissions.Callback>? = null

    // Hotwire's own delegate asks for FINE alone, which Android 12+ ignores, and rejects approximate grants.
    private val locationPermissionLauncher = registerForActivityResult(RequestMultiplePermissions()) {
        val (origin, callback) = pendingGeolocation ?: return@registerForActivityResult
        pendingGeolocation = null
        callback.invoke(origin, TrustedUrl.allows(origin, BuildConfig.DEBUG) && hasLocationPermission(), false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Hotwire paints the WebView with this view's color when moving it between screens;
        // without one it stays white and flashes before the page renders.
        view.findViewById<View>(dev.hotwire.navigation.R.id.hotwire_view)
            ?.setBackgroundColor(ContextCompat.getColor(requireContext(), R.color.page))

        // The site header already carries navigation; modals keep the app bar for its close button.
        val hideAppBar = pathProperties.context == PresentationContext.DEFAULT
        if (hideAppBar) {
            (toolbarForNavigation()?.parent as? View)?.isVisible = false
        }

        // The tab bar covers the navigation bar, but hides itself for modals and the keyboard.
        val bottomInsets = if (hideAppBar) {
            WindowInsetsCompat.Type.ime()
        } else {
            WindowInsetsCompat.Type.navigationBars() or WindowInsetsCompat.Type.ime()
        }
        ViewCompat.setOnApplyWindowInsetsListener(view) { v, insets ->
            val top = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
            v.updatePadding(top = if (hideAppBar) top else 0, bottom = insets.getInsets(bottomInsets).bottom)
            insets
        }
    }

    override fun createWebChromeClient() = object : HotwireWebChromeClient(navigator.session) {
        override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback?) {
            if (origin == null || callback == null) return

            if (!TrustedUrl.allows(origin, BuildConfig.DEBUG)) {
                callback.invoke(origin, false, false)
                return
            }
            if (hasLocationPermission()) {
                callback.invoke(origin, true, false)
            } else {
                pendingGeolocation?.let { (previousOrigin, previousCallback) ->
                    previousCallback.invoke(previousOrigin, false, false)
                }
                pendingGeolocation = origin to callback
                locationPermissionLauncher.launch(arrayOf(ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION))
            }
        }
    }

    private fun hasLocationPermission(): Boolean {
        // WebView on Android 12 ignores approximate location: https://issues.chromium.org/issues/40205003
        val accepted = if (Build.VERSION.SDK_INT in Build.VERSION_CODES.S..Build.VERSION_CODES.S_V2) {
            listOf(ACCESS_FINE_LOCATION)
        } else {
            listOf(ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION)
        }
        return accepted.any { ContextCompat.checkSelfPermission(requireContext(), it) == PackageManager.PERMISSION_GRANTED }
    }
}
