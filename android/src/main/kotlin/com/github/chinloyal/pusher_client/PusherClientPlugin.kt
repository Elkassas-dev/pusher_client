package com.github.chinloyal.pusher_client

import androidx.annotation.NonNull
import com.github.chinloyal.pusher_client.pusher.PusherService
import io.flutter.embedding.engine.plugins.FlutterPlugin

/** PusherClientPlugin */
class PusherClientPlugin: FlutterPlugin {

  private var pusherService: PusherService? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    pusherService = PusherService()
    pusherService?.register(flutterPluginBinding.binaryMessenger)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    pusherService = null
  }
}
