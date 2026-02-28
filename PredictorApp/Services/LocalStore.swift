import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

/// SQLite-backed storage for predictions, learnings, and optional config/model_metadata.
final class LocalStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "PredictorApp.LocalStore", qos: .userInitiated)

    init() {
        openDatabase()
        createTablesIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let appDir = appSupport.appendingPathComponent("PredictorApp", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        let dbPath = appDir.appendingPathComponent("predictor.sqlite").path

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            db = nil
            return
        }
    }

    private let migrationKey = "PredictorApp_crypto_types_migrated"
    private let targetSlotMigrationKey = "PredictorApp_target_slot_migrated"

    private func createTablesIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS predictions (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            predicted_at TEXT,
            target_time TEXT NOT NULL,
            predicted_value REAL NOT NULL,
            explanation TEXT,
            actual_value REAL,
            passed INTEGER,
            error_magnitude REAL,
            created_at TEXT NOT NULL,
            supersedes_id TEXT,
            revision INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_predictions_type ON predictions(type);
        CREATE INDEX IF NOT EXISTS idx_predictions_created_at ON predictions(created_at DESC);
        CREATE TABLE IF NOT EXISTS learnings (
            id TEXT PRIMARY KEY,
            model_type TEXT NOT NULL,
            learned_at TEXT NOT NULL,
            tidbit TEXT NOT NULL,
            prediction_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_learnings_learned_at ON learnings(learned_at DESC);
        CREATE TABLE IF NOT EXISTS config (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS model_metadata (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_type TEXT NOT NULL,
            version INTEGER NOT NULL DEFAULT 1,
            last_trained_at TEXT,
            metrics TEXT
        );
        """
        queue.sync {
            executeStatements(sql)
            migrateCryptoTypesIfNeeded()
            migrateTargetSlotIfNeeded()
        }
    }

    /// Add target_slot column for 10am/5pm EST crypto predictions.
    private func migrateTargetSlotIfNeeded() {
        guard db != nil, !UserDefaults.standard.bool(forKey: targetSlotMigrationKey) else { return }
        executeStatements("ALTER TABLE predictions ADD COLUMN target_slot TEXT;")
        UserDefaults.standard.set(true, forKey: targetSlotMigrationKey)
    }

    /// Recreate predictions/learnings without strict type CHECK so we can store ethereum/solana (one-time migration).
    private func migrateCryptoTypesIfNeeded() {
        guard db != nil, !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        executeStatements("""
        CREATE TABLE IF NOT EXISTS predictions_new (id TEXT PRIMARY KEY, type TEXT NOT NULL, predicted_at TEXT, target_time TEXT NOT NULL, predicted_value REAL NOT NULL, explanation TEXT, actual_value REAL, passed INTEGER, error_magnitude REAL, created_at TEXT NOT NULL, supersedes_id TEXT, revision INTEGER DEFAULT 0);
        INSERT OR IGNORE INTO predictions_new SELECT id, type, predicted_at, target_time, predicted_value, explanation, actual_value, passed, error_magnitude, created_at, supersedes_id, revision FROM predictions;
        """)
        executeStatements("DROP TABLE IF EXISTS predictions;")
        executeStatements("ALTER TABLE predictions_new RENAME TO predictions;")
        executeStatements("CREATE INDEX IF NOT EXISTS idx_predictions_type ON predictions(type); CREATE INDEX IF NOT EXISTS idx_predictions_created_at ON predictions(created_at DESC);")
        executeStatements("""
        CREATE TABLE IF NOT EXISTS learnings_new (id TEXT PRIMARY KEY, model_type TEXT NOT NULL, learned_at TEXT NOT NULL, tidbit TEXT NOT NULL, prediction_id TEXT);
        INSERT OR IGNORE INTO learnings_new SELECT id, model_type, learned_at, tidbit, prediction_id FROM learnings;
        """)
        executeStatements("DROP TABLE IF EXISTS learnings;")
        executeStatements("ALTER TABLE learnings_new RENAME TO learnings;")
        executeStatements("CREATE INDEX IF NOT EXISTS idx_learnings_learned_at ON learnings(learned_at DESC);")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func executeStatements(_ sql: String) {
        var stmt: OpaquePointer?
        let cSql = sql.cString(using: .utf8)
        sqlite3_exec(db, cSql, nil, nil, nil)
    }

    private func nowISO() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    // MARK: - Predictions

    func insertPrediction(
        type: String,
        targetTime: String,
        predictedValue: Double,
        explanation: String? = nil,
        supersedesId: String? = nil,
        revision: Int = 0,
        targetSlot: String? = nil
    ) -> Prediction? {
        let id = UUID().uuidString
        let now = nowISO()
        let sql = """
        INSERT INTO predictions (id, type, predicted_at, target_time, predicted_value, explanation, created_at, supersedes_id, revision, target_slot)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var result: Prediction?
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, now, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, targetTime, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 5, predictedValue)
            sqlite3_bind_text(stmt, 6, explanation, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, now, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, supersedesId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 9, Int32(revision))
            sqlite3_bind_text(stmt, 10, targetSlot, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                result = Prediction(
                    id: id,
                    type: type,
                    predictedAt: now,
                    targetTime: targetTime,
                    predictedValue: predictedValue,
                    explanation: explanation,
                    actualValue: nil,
                    passed: nil,
                    errorMagnitude: nil,
                    createdAt: now,
                    supersedesId: supersedesId,
                    revision: revision,
                    targetSlot: targetSlot
                )
            }
        }
        return result
    }

    func updatePredictionActual(id: String, actualValue: Double, passed: Bool, errorMagnitude: Double) {
        let sql = "UPDATE predictions SET actual_value = ?, passed = ?, error_magnitude = ? WHERE id = ?;"
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, actualValue)
            sqlite3_bind_int(stmt, 2, passed ? 1 : 0)
            sqlite3_bind_double(stmt, 3, errorMagnitude)
            sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func getLatestPredictions() -> [Prediction] {
        var out: [Prediction] = []
        queue.sync {
            // Weather: no target_slot
            let sqlWeather = "SELECT * FROM predictions WHERE type = ? ORDER BY created_at DESC LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlWeather, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, PredictionType.weather.rawValue, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW, let p = rowToPrediction(stmt) { out.append(p) }
            }
            // Crypto: latest per (type, target_slot) for 10am and 5pm
            for type in PredictionType.cryptoTypes.map(\.rawValue) {
                for slot in TargetSlot.allCases.map(\.rawValue) {
                    let sql = "SELECT * FROM predictions WHERE type = ? AND target_slot = ? ORDER BY created_at DESC LIMIT 1;"
                    var stmt2: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt2, nil) == SQLITE_OK else { continue }
                    defer { sqlite3_finalize(stmt2) }
                    sqlite3_bind_text(stmt2, 1, type, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt2, 2, slot, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(stmt2) == SQLITE_ROW, let p = rowToPrediction(stmt2) {
                        out.append(p)
                    }
                }
            }
        }
        return out
    }

    func getPredictions(orderByCreatedAtDescLimit limit: Int = 50) -> [Prediction] {
        var out: [Prediction] = []
        queue.sync {
            let sql = "SELECT * FROM predictions ORDER BY created_at DESC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW, let p = rowToPrediction(stmt) {
                out.append(p)
            }
        }
        return out
    }

    func getPredictionsWithActuals(type: String? = nil, limit: Int = 200) -> [Prediction] {
        var out: [Prediction] = []
        queue.sync {
            let sql: String
            if let t = type {
                sql = "SELECT * FROM predictions WHERE actual_value IS NOT NULL AND type = ? ORDER BY created_at DESC LIMIT ?;"
            } else {
                sql = "SELECT * FROM predictions WHERE actual_value IS NOT NULL ORDER BY created_at DESC LIMIT ?;"
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if let t = type {
                sqlite3_bind_text(stmt, 1, t, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }
            while sqlite3_step(stmt) == SQLITE_ROW, let p = rowToPrediction(stmt) {
                out.append(p)
            }
        }
        return out
    }

    func getPredictionsForVerification(type: String, limit: Int = 100) -> [Prediction] {
        var out: [Prediction] = []
        queue.sync {
            let sql = "SELECT * FROM predictions WHERE type = ? AND actual_value IS NULL ORDER BY target_time ASC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW, let p = rowToPrediction(stmt) {
                out.append(p)
            }
        }
        return out
    }

    func getWeatherPredictionForTargetDate(_ targetDateISO: String) -> Prediction? {
        let start = "\(targetDateISO)T00:00:00Z"
        let end = "\(targetDateISO)T23:59:59.999Z"
        var result: Prediction?
        queue.sync {
            let sql = "SELECT * FROM predictions WHERE type = ? AND target_time >= ? AND target_time <= ? ORDER BY created_at DESC LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, PredictionType.weather.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, start, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, end, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = rowToPrediction(stmt)
            }
        }
        return result
    }

    private func rowToPrediction(_ stmt: OpaquePointer?) -> Prediction? {
        guard let stmt = stmt else { return nil }
        let colCount = sqlite3_column_count(stmt)
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let type = String(cString: sqlite3_column_text(stmt, 1))
        let predictedAt = colText(stmt, 2)
        let targetTime = String(cString: sqlite3_column_text(stmt, 3))
        let predictedValue = sqlite3_column_double(stmt, 4)
        let explanation = colText(stmt, 5)
        let actualValue = colDouble(stmt, 6)
        let passed = colBool(stmt, 7)
        let errorMagnitude = colDouble(stmt, 8)
        let createdAt = colText(stmt, 9) ?? ""
        let supersedesId = colText(stmt, 10)
        let revision = colInt(stmt, 11)
        let targetSlot = colCount >= 13 ? colText(stmt, 12) : nil
        return Prediction(
            id: id,
            type: type,
            predictedAt: predictedAt,
            targetTime: targetTime,
            predictedValue: predictedValue,
            explanation: explanation,
            actualValue: actualValue,
            passed: passed,
            errorMagnitude: errorMagnitude,
            createdAt: createdAt,
            supersedesId: supersedesId,
            revision: revision,
            targetSlot: targetSlot
        )
    }

    // MARK: - Learnings

    func insertLearning(modelType: String, tidbit: String, predictionId: String? = nil) -> Learning? {
        let id = UUID().uuidString
        let now = nowISO()
        let sql = "INSERT INTO learnings (id, model_type, learned_at, tidbit, prediction_id) VALUES (?, ?, ?, ?, ?);"
        var result: Learning?
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, modelType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, now, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, tidbit, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, predictionId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                result = Learning(id: id, modelType: modelType, learnedAt: now, tidbit: tidbit, predictionId: predictionId)
            }
        }
        return result
    }

    func getLearnings(modelType: String? = nil, limit: Int = 100) -> [Learning] {
        var out: [Learning] = []
        queue.sync {
            let sql: String
            if let t = modelType {
                sql = "SELECT * FROM learnings WHERE model_type = ? ORDER BY learned_at DESC LIMIT ?;"
            } else {
                sql = "SELECT * FROM learnings ORDER BY learned_at DESC LIMIT ?;"
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if let t = modelType {
                sqlite3_bind_text(stmt, 1, t, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }
            while sqlite3_step(stmt) == SQLITE_ROW, let l = rowToLearning(stmt) {
                out.append(l)
            }
        }
        return out
    }

    private func rowToLearning(_ stmt: OpaquePointer?) -> Learning? {
        guard let stmt = stmt else { return nil }
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let modelType = String(cString: sqlite3_column_text(stmt, 1))
        let learnedAt = colText(stmt, 2)
        let tidbit = String(cString: sqlite3_column_text(stmt, 3))
        let predictionId = colText(stmt, 4)
        return Learning(id: id, modelType: modelType, learnedAt: learnedAt, tidbit: tidbit, predictionId: predictionId)
    }

    // MARK: - Helpers

    private func colText(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let stmt = stmt, sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, i))
    }

    private func colDouble(_ stmt: OpaquePointer?, _ i: Int32) -> Double? {
        guard let stmt = stmt, sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, i)
    }

    private func colInt(_ stmt: OpaquePointer?, _ i: Int32) -> Int? {
        guard let stmt = stmt, sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(stmt, i))
    }

    private func colBool(_ stmt: OpaquePointer?, _ i: Int32) -> Bool? {
        guard let v = colInt(stmt, i) else { return nil }
        return v != 0
    }
}
