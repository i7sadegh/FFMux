package com.ffmux.app

import android.app.Application

class FFMuxApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Graph.initialize(this)
    }
}
