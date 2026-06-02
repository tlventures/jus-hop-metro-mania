package com.tlventures.metrosafar;

import android.os.Bundle;
import androidx.core.splashscreen.SplashScreen;
import io.flutter.embedding.android.FlutterActivity;

public class MainActivity extends FlutterActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // Activate the Android 12+ splash screen (animated spinner icon shown
        // by the OS immediately on launch, before the Flutter engine boots).
        SplashScreen.installSplashScreen(this);
        super.onCreate(savedInstanceState);
    }
}
