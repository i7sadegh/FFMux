package com.ffmux.app.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadDao {

    @Insert
    suspend fun insert(item: DownloadEntity): Long

    @Query("SELECT * FROM downloads ORDER BY id DESC")
    fun observeAll(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads WHERE id = :id")
    suspend fun findById(id: Long): DownloadEntity?

    @Query("SELECT * FROM downloads WHERE status = 'QUEUED' ORDER BY id LIMIT 1")
    suspend fun nextQueued(): DownloadEntity?

    @Query("UPDATE downloads SET status = 'RUNNING' WHERE id = :id AND status = 'QUEUED'")
    suspend fun markRunningIfQueued(id: Long): Int

    /** Atomically claims the next queued item so a late cancel cannot double-run it. */
    @Transaction
    suspend fun claimNext(): DownloadEntity? {
        val item = nextQueued() ?: return null
        return if (markRunningIfQueued(item.id) > 0) item else null
    }

    @Query("UPDATE downloads SET status = 'QUEUED', progress = 0 WHERE status IN ('RUNNING', 'SAVING')")
    suspend fun resetActive()

    /** Puts a failed or canceled download back into the queue for a retry. */
    @Query(
        "UPDATE downloads SET status = 'QUEUED', progress = 0, etaSec = NULL, " +
            "error = NULL, savedUri = NULL " +
            "WHERE id = :id AND status IN ('FAILED', 'CANCELED')"
    )
    suspend fun resetForRetry(id: Long): Int

    @Query("UPDATE downloads SET status = :status, progress = :progress, etaSec = :eta WHERE id = :id")
    suspend fun updateProgress(id: Long, status: String, progress: Float, eta: Long?)

    @Query("UPDATE downloads SET status = :status WHERE id = :id")
    suspend fun setStatus(id: Long, status: String)

    @Query("UPDATE downloads SET status = 'CANCELED' WHERE id = :id AND status = 'QUEUED'")
    suspend fun cancelQueued(id: Long)

    @Query("UPDATE downloads SET status = :status, error = :error WHERE id = :id")
    suspend fun finishWithError(id: Long, status: String, error: String?)

    @Query("UPDATE downloads SET status = 'COMPLETED', progress = 100, etaSec = NULL, savedUri = :uri WHERE id = :id")
    suspend fun finish(id: Long, uri: String?)

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun delete(id: Long)
}
