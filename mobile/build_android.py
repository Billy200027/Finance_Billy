"""Generate the reproducible Android project. No credentials or native SDK required here."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'android-project'
FILES = {
    'settings.gradle': '''pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = 'FinanceBilly'
include ':app'
''',
    'build.gradle': "plugins { id 'com.android.application' version '8.13.2' apply false }\n",
    'gradle.properties': 'org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\n',
    'app/build.gradle': '''plugins { id 'com.android.application' }
android {
    namespace 'com.billy.finance'
    compileSdk 35
    defaultConfig { applicationId 'com.billy.finance'; minSdk 26; targetSdk 35; versionCode 1; versionName '3.1.1-prueba' }
    buildTypes { release { minifyEnabled false } }
    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
}
''',
    'app/src/main/AndroidManifest.xml': '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET" />
  <application android:label="Finance Billy" android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher"
    android:theme="@style/AppTheme" android:allowBackup="false" android:usesCleartextTraffic="false">
    <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize"
      android:configChanges="orientation|screenSize|keyboardHidden">
      <intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent-filter>
    </activity>
  </application>
</manifest>
''',
    'app/src/main/res/values/styles.xml': '''<resources><style name="AppTheme" parent="android:style/Theme.Material.Light.NoActionBar">
  <item name="android:fontFamily">sans</item><item name="android:colorAccent">#6f1d36</item>
  <item name="android:statusBarColor">#6f1d36</item><item name="android:navigationBarColor">#6f1d36</item>
  <item name="android:windowLightStatusBar">false</item><item name="android:windowLightNavigationBar">false</item>
  <item name="android:windowBackground">#6f1d36</item>
</style></resources>
''',
    'app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml': '''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/icon_background"/><foreground android:drawable="@drawable/icon_foreground"/>
</adaptive-icon>
''',
    'app/src/main/res/values/colors.xml': '<resources><color name="icon_background">#6f1d36</color></resources>\n',
    'app/src/main/java/com/billy/finance/MainActivity.java': r'''package com.billy.finance;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.WindowInsets;
import android.widget.LinearLayout;
import android.widget.Toast;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONTokener;

public class MainActivity extends Activity {
    private static final String HOME = "https://billy200027.github.io/Finance_Billy/";
    private static final int PICK_IMAGE = 10, SAVE_JSON = 11, MAX_BYTES = 5 * 1024 * 1024;
    private WebView web;
    private ValueCallback<Uri[]> imageCallback;
    private String exportJson;

    private boolean trusted(Uri uri) {
        return uri != null && "https".equals(uri.getScheme()) && "billy200027.github.io".equals(uri.getHost())
            && (uri.getPort() == -1 || uri.getPort() == 443) && uri.getUserInfo() == null
            && ("/Finance_Billy/".equals(uri.getPath()) || "/Finance_Billy/index.html".equals(uri.getPath()));
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#6f1d36"));
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#fcfaf9"));
        root.addView(web, new LinearLayout.LayoutParams(-1, -1));
        setContentView(root);
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            root.setOnApplyWindowInsetsListener((view, insets) -> {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                Insets ime = insets.getInsets(WindowInsets.Type.ime());
                view.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, ime.bottom));
                return WindowInsets.CONSUMED;
            });
        }
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true); // Android document picker returns content URIs.
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setSupportMultipleWindows(false);
        s.setJavaScriptCanOpenWindowsAutomatically(false);
        web.addJavascriptInterface(new ExportBridge(), "FinanceExport");
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (trusted(request.getUrl())) return false;
                if (request.isForMainFrame() && ("https".equals(request.getUrl().getScheme())
                        || "mailto".equals(request.getUrl().getScheme()) || "tel".equals(request.getUrl().getScheme()))) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW, request.getUrl())); }
                    catch (Exception ex) { note("No hay una aplicación para abrir ese enlace."); }
                }
                return true;
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (!request.isForMainFrame()) return;
                new AlertDialog.Builder(MainActivity.this).setTitle("Sin conexión")
                    .setMessage("Finance Billy necesita internet. Revisa tu conexión e intenta de nuevo.")
                    .setPositiveButton("Reintentar", (d, w) -> web.loadUrl(HOME))
                    .setNegativeButton("Cerrar", (d, w) -> finish()).show();
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!trusted(Uri.parse(url))) return;
                // Only exports created by this app; native file picker chooses the destination.
                view.evaluateJavascript("(function(){if(window.fbExportHook)return;window.fbExportHook=true;document.addEventListener('click',function(e){var a=e.target.closest&&e.target.closest('a[download]');if(!a||!a.href.startsWith('blob:')||!a.download.endsWith('.json'))return;e.preventDefault();fetch(a.href).then(function(r){return r.text()}).then(function(t){FinanceExport.saveJson(t)}).catch(function(){alert('No se pudo exportar. Intenta de nuevo.');});},true);})();", null);
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (!trusted(Uri.parse(web.getUrl()))) return false;
                if (imageCallback != null) imageCallback.onReceiveValue(null);
                imageCallback = callback;
                Intent pick = new Intent(Intent.ACTION_GET_CONTENT);
                pick.addCategory(Intent.CATEGORY_OPENABLE);
                pick.setType("image/*");
                pick.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"image/jpeg", "image/png"});
                try { startActivityForResult(Intent.createChooser(pick, "Selecciona tu comprobante"), PICK_IMAGE); }
                catch (Exception ex) { imageCallback.onReceiveValue(null); imageCallback = null; note("No se pudo abrir el selector de imágenes."); }
                return true;
            }
        });
        web.setDownloadListener((url, agent, disposition, mime, length) -> note("Utiliza Exportar registros JSON para guardar el respaldo."));
        web.loadUrl(HOME);
    }

    private boolean validImage(Uri uri) {
        if (uri == null || !"content".equals(uri.getScheme()) || !trusted(Uri.parse(web.getUrl()))) return false;
        try (InputStream stream = getContentResolver().openInputStream(uri)) {
            if (stream == null) return false;
            byte[] prefix = new byte[8];
            int got = 0, n;
            while (got < 8 && (n = stream.read(prefix, got, 8 - got)) > 0) got += n;
            boolean png = got == 8 && prefix[0] == (byte)137 && prefix[1] == 80 && prefix[2] == 78
                && prefix[3] == 71 && prefix[4] == 13 && prefix[5] == 10 && prefix[6] == 26 && prefix[7] == 10;
            boolean jpg = got >= 3 && prefix[0] == (byte)255 && prefix[1] == (byte)216 && prefix[2] == (byte)255;
            if (!png && !jpg) return false;
            int total = got; byte[] buffer = new byte[8192];
            while ((n = stream.read(buffer)) != -1) { total += n; if (total > MAX_BYTES) return false; }
            return true;
        } catch (Exception ex) { return false; }
    }

    public class ExportBridge {
        @JavascriptInterface public void saveJson(String data) {
            if (data == null || data.length() > MAX_BYTES) return;
            try { Object parsed = new JSONTokener(data).nextValue();
                if (!(parsed instanceof org.json.JSONObject) && !(parsed instanceof org.json.JSONArray)) return;
            } catch (Exception ex) { return; }
            runOnUiThread(() -> {
                if (!trusted(Uri.parse(web.getUrl())) || exportJson != null) return;
                exportJson = data;
                Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                save.addCategory(Intent.CATEGORY_OPENABLE); save.setType("application/json");
                save.putExtra(Intent.EXTRA_TITLE, "Finance-Billy-respaldo.json");
                try { startActivityForResult(save, SAVE_JSON); }
                catch (Exception ex) { exportJson = null; note("No se pudo abrir Guardar archivo."); }
            });
        }
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == PICK_IMAGE && imageCallback != null) {
            Uri uri = result == RESULT_OK && data != null ? data.getData() : null;
            boolean valid = validImage(uri);
            imageCallback.onReceiveValue(valid ? new Uri[]{uri} : null); imageCallback = null;
            if (uri != null && !valid) note("Usa una imagen JPG o PNG de hasta 5 MB.");
        }
        if (request == SAVE_JSON && exportJson != null) {
            String pending = exportJson; exportJson = null;
            if (result == RESULT_OK && data != null && data.getData() != null) {
                try (OutputStream out = getContentResolver().openOutputStream(data.getData())) {
                    if (out == null) throw new IllegalStateException();
                    out.write(pending.getBytes(StandardCharsets.UTF_8)); note("Respaldo guardado.");
                } catch (Exception ex) { note("No se pudo guardar el respaldo."); }
            }
        }
    }

    private void note(String text) { Toast.makeText(this, text, Toast.LENGTH_LONG).show(); }
    @Override public void onBackPressed() {
        new AlertDialog.Builder(this).setTitle("¿Cerrar Finance Billy?")
            .setMessage("Puedes volver a abrir la aplicación desde su icono.")
            .setPositiveButton("Cerrar", (d,w) -> finish()).setNegativeButton("Continuar", null).show();
    }
    @Override public void onDestroy() {
        if (imageCallback != null) imageCallback.onReceiveValue(null);
        exportJson = null; web.removeJavascriptInterface("FinanceExport"); web.destroy(); super.onDestroy();
    }
}
''',
}

for relative, contents in FILES.items():
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(contents, encoding='utf-8')
for relative in ['app/src/main/res/mipmap-mdpi/ic_launcher.png', 'app/src/main/res/drawable/icon_foreground.png']:
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'app-icon-512.png', target)
shutil.copyfile(ROOT / 'fonts/OFL.txt', OUT / 'FONT-LICENSE.txt')
print(f'Android project generated: {OUT}')
