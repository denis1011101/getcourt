package co.getcourt.app

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Menu
import android.view.View
import android.webkit.CookieManager
import androidx.activity.enableEdgeToEdge
import androidx.core.view.isVisible
import com.google.android.material.bottomnavigation.BottomNavigationView
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.navigator.NavigatorHost
import dev.hotwire.navigation.tabs.HotwireBottomNavigationController
import dev.hotwire.navigation.tabs.HotwireBottomTab
import dev.hotwire.navigation.tabs.navigatorConfigurations

class MainActivity : HotwireActivity() {
    // App link that opened the activity; routed on top of the start page once the navigator is up.
    private var pendingLink: String? = null
    private var currentTabIndex = 0

    private val authHandler = Handler(Looper.getMainLooper())
    private var observedAuth = ""
    private val authCheck = object : Runnable {
        override fun run() {
            val auth = currentAuth()
            if (auth != observedAuth) {
                observedAuth = auth
                // Each navigator owns a Turbo cache and back stack, including the visible one.
                // Reset on the cookie change itself: the response may arrive after switching tabs.
                tabs.forEach { navigatorHost(it).navigator.reset() }
            }
            authHandler.postDelayed(this, 500)
        }
    }

    private val tabs by lazy {
        listOf(
            tab(R.string.tab_games, R.drawable.ic_tab_games, "games", "/", R.id.games_nav_host),
            tab(R.string.tab_courts, R.drawable.ic_tab_courts, "courts", "/courts", R.id.courts_nav_host),
            tab(R.string.tab_life, R.drawable.ic_tab_life, "life", "/tennis_life", R.id.life_nav_host),
            tab(R.string.tab_more, R.drawable.ic_tab_more, "more", "/more", R.id.more_nav_host)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val bottomNav = findViewById<BottomNavigationView>(R.id.bottom_nav)
        HotwireBottomNavigationController(this, bottomNav).load(tabs)
        observedAuth = savedInstanceState?.getString(KEY_AUTH) ?: currentAuth()
        addNewButton(bottomNav, savedInstanceState?.getInt(KEY_TAB) ?: 0)

        if (savedInstanceState == null) {
            pendingLink = linkFrom(intent)
        }
    }

    override fun onResume() {
        super.onResume()
        authHandler.post(authCheck)
    }

    override fun onPause() {
        authHandler.removeCallbacks(authCheck)
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkFrom(intent)?.let { delegate.currentNavigator?.route(it) }
    }

    override fun onNavigatorReady(navigator: Navigator) {
        val link = pendingLink ?: return
        pendingLink = null
        // The start destination is still being attached here; route once it exists.
        window.decorView.post { delegate.currentNavigator?.route(link) }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_TAB, currentTabIndex)
        outState.putString(KEY_AUTH, observedAuth)
    }

    override fun navigatorConfigurations() = tabs.navigatorConfigurations

    // "+" sits between Courts and Life like on the site, but opens a form over the current tab
    // instead of becoming a tab. The controller numbers menu items by tab index, so the menu is
    // rebuilt with a gap for it and item selection is taken over.
    private fun addNewButton(bottomNav: BottomNavigationView, selectedTabIndex: Int) {
        bottomNav.menu.clear()
        tabs.forEachIndexed { index, tab ->
            val order = if (index < NEW_BUTTON_ORDER) index else index + 1
            bottomNav.menu.add(Menu.NONE, index, order, tab.title).setIcon(tab.iconResId).isCheckable = true
        }
        bottomNav.menu.add(Menu.NONE, NEW_BUTTON_ID, NEW_BUTTON_ORDER, R.string.tab_new).setIcon(R.drawable.ic_tab_new)

        bottomNav.setOnItemSelectedListener { item ->
            if (item.itemId == NEW_BUTTON_ID) {
                delegate.currentNavigator?.route(newFormLocation())
                false
            } else {
                showTab(item.itemId)
                true
            }
        }
        // Not selectedItemId: re-selecting the checked item counts as a tab tap, which clears its history.
        bottomNav.menu.findItem(selectedTabIndex).isChecked = true
        showTab(selectedTabIndex)
    }

    private fun showTab(index: Int) {
        currentTabIndex = index
        val tab = tabs[index]
        delegate.setCurrentNavigator(tab.configuration)
        tabs.forEach { findViewById<View>(it.configuration.navigatorHostId).isVisible = it == tab }
    }

    private fun currentAuth(): String = CookieManager.getInstance().getCookie(BuildConfig.BASE_URL)
        ?.split(";")
        ?.map { it.trim() }
        ?.firstOrNull { it.startsWith("native_auth=") }
        ?.substringAfter("=")
        .orEmpty()

    private fun navigatorHost(tab: HotwireBottomTab) =
        supportFragmentManager.findFragmentById(tab.configuration.navigatorHostId) as NavigatorHost

    // Mirrors the site's "New" button, which picks the form by the page being viewed.
    private fun newFormLocation(): String {
        val path = delegate.currentNavigator?.location?.let { java.net.URI(it).path }.orEmpty()
        val form = when {
            path.startsWith("/courts") -> "/courts/new"
            path.startsWith("/tournaments") -> "/tournaments/new"
            else -> "/games/new"
        }
        return BuildConfig.BASE_URL + form
    }

    private fun tab(title: Int, icon: Int, name: String, path: String, hostId: Int) = HotwireBottomTab(
        title = getString(title),
        iconResId = icon,
        configuration = NavigatorConfiguration(
            name = name,
            startLocation = BuildConfig.BASE_URL + path,
            navigatorHostId = hostId
        )
    )

    private fun linkFrom(intent: Intent?): String? =
        intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString
            ?.takeIf { TrustedUrl.allows(it, BuildConfig.DEBUG) }

    private companion object {
        const val NEW_BUTTON_ID = 100
        const val NEW_BUTTON_ORDER = 2
        const val KEY_TAB = "selected_tab"
        const val KEY_AUTH = "observed_auth"
    }
}
