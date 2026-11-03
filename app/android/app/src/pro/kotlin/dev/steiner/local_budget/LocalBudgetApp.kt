package dev.steiner.local_budget

import android.app.Application
import dev.steiner.local_budget.widget.WidgetRefreshWorker

/**
 * Pro-only application (declared in src/pro/AndroidManifest.xml). E7c
 * §4.3: owns the day-rollover widget tick. The free flavor keeps the
 * stock android.app.Application — widgets are a Paid-pack feature, the
 * free APK must not even schedule a render for them.
 */
class LocalBudgetApp : Application() {
    override fun onCreate() {
        super.onCreate()
        WidgetRefreshWorker.schedule(this)
    }
}
