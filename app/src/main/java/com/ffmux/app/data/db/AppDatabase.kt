package com.ffmux.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [DownloadEntity::class], version = 3, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun downloadDao(): DownloadDao

    companion object {
        /**
         * v1 -> v2: the downloads table gains the downloadArgs column that
         * carries the yt-dlp option flags picked on the Home screen.
         */
        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE downloads ADD COLUMN downloadArgs TEXT NOT NULL DEFAULT ''"
                )
            }
        }

        /**
         * v2 -> v3: the downloads table gains the recordMinutes column
         * that carries the recording time limit of live streams.
         */
        val MIGRATION_2_3: Migration = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE downloads ADD COLUMN recordMinutes INTEGER NOT NULL DEFAULT 0"
                )
            }
        }
    }
}
