# Destinations are looked up by their @HotwireDestinationDeepLink annotation at runtime.
-keep @dev.hotwire.navigation.destinations.HotwireDestinationDeepLink class * { *; }

# Compile-time-only annotations pulled in transitively.
-dontwarn javax.lang.model.element.Modifier
