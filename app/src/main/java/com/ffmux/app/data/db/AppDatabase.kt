package com.ffmux.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [DownloadEntity::class], version = 2, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun downloadDao(): DownloadDao

    companion object {
        /** v2 adds the byte counters and the terminal log column. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE downloads ADD COLUMN downloadedBytes INTEGER")
                db.execSQL("ALTER TABLE downloads ADD COLUMN totalBytes INTEGER")
                db.execSQL("ALTER TABLE downloads ADD COLUMN log TEXT")
            }
        }
    }
}
