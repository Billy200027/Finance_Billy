package com.billy.finance;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

public class FinancePushService extends FirebaseMessagingService {
    public static final String CHANNEL = "finance_billy_activity";
    @Override public void onNewToken(String token) {
        getSharedPreferences("finance_push", MODE_PRIVATE).edit().putString("token", token).apply();
        // Account routing is updated only through the authenticated app, never by a public topic.
    }
    @Override public void onMessageReceived(RemoteMessage message) {
        SharedPreferences p=getSharedPreferences("finance_push", MODE_PRIVATE);
        Map<String,String> data=message.getData();
        String binding=data.get("binding"),event=data.get("event_id");
        if (!p.getBoolean("enabled",false) || binding==null || !binding.equals(p.getString("binding","")) || event==null) return;
        if (Build.VERSION.SDK_INT>=33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) return;
        // Persistent deduplication makes retries harmless, including a restarted process.
        if (p.contains("seen_"+event)) return;
        NotificationManager nm=getSystemService(NotificationManager.class);
        if (!nm.areNotificationsEnabled()) return;
        NotificationChannel channel=new NotificationChannel(CHANNEL,"Actividad de Finance Billy",NotificationManager.IMPORTANCE_HIGH);
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);nm.createNotificationChannel(channel);
        Intent open=new Intent(this,MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        String page=data.get("page");
        if ("Noticias".equals(page)||"Solicitudes".equals(page)||"Comprobantes".equals(page)||"Préstamos".equals(page)) open.putExtra("finance_page",page);
        PendingIntent click=PendingIntent.getActivity(this,event.hashCode(),open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification n=new Notification.Builder(this,CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setColor(0xff6f1d36).setContentTitle(data.get("title")).setContentText(data.get("body"))
            .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(click)
            .setPublicVersion(new Notification.Builder(this,CHANNEL).setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Finance Billy").setContentText("Tienes una nueva actividad.").build()).build();
        nm.notify(event.hashCode(),n);
        SharedPreferences.Editor edit=p.edit();
        long cutoff=System.currentTimeMillis()-2L*24*60*60*1000;
        for(String k:p.getAll().keySet())if(k.startsWith("seen_")&&p.getLong(k,0)<cutoff)edit.remove(k);
        edit.putLong("seen_"+event,System.currentTimeMillis()).apply();
    }
}
