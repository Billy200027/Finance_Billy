package com.billy.finance;

import android.app.NotificationManager;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.webkit.JavascriptInterface;
import com.google.firebase.messaging.FirebaseMessaging;
import java.util.UUID;
import org.json.JSONObject;

public class PushBridge {
    private final MainActivity activity;
    private final SharedPreferences prefs;
    PushBridge(MainActivity a) {
        activity=a; prefs=a.getSharedPreferences("finance_push",0);
        if(!prefs.contains("device"))prefs.edit().putString("device",UUID.randomUUID().toString()).apply();
        FirebaseMessaging.getInstance().getToken().addOnSuccessListener(t->{prefs.edit().putString("token",t).apply();activity.pushChanged();});
    }
    @JavascriptInterface public synchronized void setUser(String user) {
        if (user==null || !user.matches("[a-fA-F0-9-]{36}")) return;
        if(!user.equals(prefs.getString("user",""))) {
            prefs.edit().putString("user",user).putString("binding",UUID.randomUUID().toString()).putBoolean("enabled",false).apply();
            activity.getSystemService(NotificationManager.class).cancelAll();
        }
    }
    @JavascriptInterface public synchronized String info() {
        try {
            boolean permission=activity.getSystemService(NotificationManager.class).areNotificationsEnabled()
                && (Build.VERSION.SDK_INT<33 || activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED);
            return new JSONObject().put("device",prefs.getString("device",""))
                .put("token",prefs.getString("token",""))
                .put("binding",prefs.getString("binding",""))
                .put("enabled",prefs.getBoolean("enabled",false)).put("permission",permission).toString();
        } catch(Exception e) { return "{}"; }
    }
    @JavascriptInterface public synchronized void enable() {
        prefs.edit().putBoolean("enabled",true).apply();
        activity.runOnUiThread(()->{
            if(Build.VERSION.SDK_INT>=33 && activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)
                activity.requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},12);
            else activity.pushChanged();
        });
    }
    @JavascriptInterface public synchronized void disable() {
        prefs.edit().putBoolean("enabled",false).putString("binding",UUID.randomUUID().toString()).apply();
        activity.getSystemService(NotificationManager.class).cancelAll();
    }
    @JavascriptInterface public synchronized void logout() {
        disable(); prefs.edit().remove("user").apply();
    }
}
