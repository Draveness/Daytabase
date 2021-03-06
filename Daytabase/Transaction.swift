//
//  DayTransaction.swift
//  Database
//
//  Created by Draveness on 3/1/17.
//  Copyright © 2017 Draveness. All rights reserved.
//

import Foundation
import CSQLite3

public class ReadTransaction {
    public unowned let connection: Connection
    let isReadWrite: Bool

    init(connection: Connection, readWrite: Bool = false) {
        self.connection = connection
        self.isReadWrite = readWrite
    }

    // MARK: - Count

    public func numberOfCollections() -> Int {
        guard let statement = connection.database.getCollectionCountStatement else { return 0 }

        defer {
            sqlite3_reset(statement)
        }

        let status = sqlite3_step(statement)
        if status == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, SQLITE_COLUMN_START))
        } else if status == SQLITE_ERROR {
            Daytabase.log.error("Error executing 'getCollectionCountStatement': \(status) \(daytabase_errmsg(self.connection.db))")
        }
        return 0
    }

    public func numberOfKeys(inCollection collection: String = "") -> Int {
        guard let statement = connection.database.getCollectionCountStatement else { return 0 }

        defer {
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }

        sqlite3_bind_text(statement, SQLITE_BIND_START, collection, collection.length, SQLITE_STATIC)
        let status = sqlite3_step(statement)
        if status == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, SQLITE_COLUMN_START))
        } else if status == SQLITE_ERROR {
            Daytabase.log.error("Error executing 'getKeyCountForCollectionStatement': \(status) \(daytabase_errmsg(self.connection.db))")
        }
        return 0
    }

    public func numberOfKeysInAllCollections() -> Int {
        guard let statement = connection.database.getKeyCountForAllStatement else { return 0 }

        defer {
            sqlite3_reset(statement)
        }

        let status = sqlite3_step(statement)
        if status == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, SQLITE_COLUMN_START))
        } else if status == SQLITE_ERROR {
            Daytabase.log.error("Error executing 'getKeyCountForAllStatement': \(status) \(daytabase_errmsg(self.connection.db))")
        }
        return 0
    }

    // MARK: - List

    public func allCollections() -> [String] {
        return []
    }

    public func value(forKey key: String, inCollection collection: String = "") -> Any? {
        return object(forkey: key, inCollection: collection)
    }

    /**
     * Object access.
     * Objects are automatically deserialized using database's configured deserializer.
     **/
    public func object(forkey key: String, inCollection collection: String = "") -> Any? {
        let cacheKey = CollectionKey(key: key, collection: collection)
        if let object = connection.objectCache.object(forKey: cacheKey) {
            return object
        }

        guard let statement = connection.database.getDataForKeyStatement else { return nil }

        defer {
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }
        defer {
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }

        let column_idx_rowid = SQLITE_COLUMN_START
        let column_idx_data = SQLITE_COLUMN_START + 1

        let bind_idx_collection = SQLITE_BIND_START
        let bind_idx_key = SQLITE_BIND_START + 1

        sqlite3_bind_text(statement, bind_idx_collection, collection, collection.length, SQLITE_STATIC)
        sqlite3_bind_text(statement, bind_idx_key, key, key.length, SQLITE_STATIC)

        let status = sqlite3_step(statement)
        if status == SQLITE_ROW {
            let _ = sqlite3_column_int64(statement, column_idx_rowid)
            let blob = sqlite3_column_blob(statement, column_idx_data)
            let count = sqlite3_column_bytes(statement, column_idx_data)
            guard let bytes = blob else { return nil }
            let data = Data(bytes: bytes, count: Int(count))

            let object = connection.database.objectDeserializer(collection, key, data)
            if let object = object {
                connection.objectCache.set(object: object, forKey: cacheKey)
            }
            return object
        } else if status == SQLITE_ERROR {
            Daytabase.log.error("Error executing 'getDataForKeyStatement': \(status) \(daytabase_errmsg(self.connection.db)) key(\(key))")
        }
        return nil
    }

    func hasObject(forKey key: String, inCollection collection: String = "") -> Bool {
        let cacheKey = CollectionKey(key: key, collection: collection)
        if connection.objectCache.contains(key: cacheKey) { return true }
        if rowid(forKey: key, inCollection: collection) != 0 { return true }
        return false
    }

    // MARK: - Transaction States

    func begin() {
        guard let statement = connection.database.beginTransactionStatement else { return }
        let status = sqlite3_step(statement)
        if status != SQLITE_DONE {
            Daytabase.log.error("Couldn't begin transaction: \(status) \(daytabase_errmsg(self.connection.db))")
        }
        sqlite3_reset(statement)
    }

    func commit() {
        guard let statement = connection.database.commitTransactionStatement else { return }
        let status = sqlite3_step(statement)
        if status != SQLITE_DONE {
            Daytabase.log.error("Couldn't commit transaction: \(status) \(daytabase_errmsg(self.connection.db))")
        }
        sqlite3_reset(statement)
    }

    func rollback() {
        guard let statement = connection.database.rollbackTransactionStatement else { return }
        let status = sqlite3_step(statement)
        if status != SQLITE_DONE {
            Daytabase.log.error("Couldn't rollback transaction: \(status) \(daytabase_errmsg(self.connection.db))")
        }
        sqlite3_reset(statement)
    }

    func rowid(forKey key: String, inCollection collection: String) -> Int64 {
        guard let statement = connection.database.getRowidForKeyStatement else { return 0 }

        defer {
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }

        let column_idx_result   = SQLITE_COLUMN_START;
        let bind_idx_collection = SQLITE_BIND_START + 0;
        let bind_idx_key        = SQLITE_BIND_START + 1;

        sqlite3_bind_text(statement, bind_idx_collection, collection, collection.length, SQLITE_STATIC)
        sqlite3_bind_text(statement, bind_idx_key, key, key.length,  SQLITE_STATIC)

        let status = sqlite3_step(statement)
        if status == SQLITE_ROW {
            return sqlite3_column_int64(statement, column_idx_result)
        } else if status == SQLITE_ERROR {
            Daytabase.log.error("Error executing 'getRowidForKeyStatement': \(status) \(daytabase_errmsg(self.connection.db)) key(\(key))")
        }

        return 0
    }
}

public final class ReadWriteTransaction: ReadTransaction {

    // MARK: - Object & Metadata

    public func set(value: Any, forKey key: String, inCollection collection: String = "") {
        set(object: value, forKey: key, inCollection: collection)
    }

    public func set(object inObject: Any, forKey key: String, inCollection collection: String = "") {
        let cacheKey = CollectionKey(key: key, collection: collection)

        var set = true
        if let _ = object(forkey: key, inCollection: collection) {
            set = set && update(object: inObject, forKey: key, inCollection: collection)
        } else {
            set = set && insert(object: inObject, forKey: key, inCollection: collection)
        }

        guard set else { return }

        connection.objectCache.set(object: inObject, forKey: cacheKey)
    }
}


// MARK: - Internal
extension ReadWriteTransaction {
    func insert(object: Any, forKey key: String, inCollection collection: String = "") -> Bool {
        guard let statement = connection.database.insertForRowidStatement else { return false }

        defer {
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }

        let bind_idx_collection = SQLITE_BIND_START
        let bind_idx_key = SQLITE_BIND_START + 1
        let bind_idx_data = SQLITE_BIND_START + 2
        let bind_idx_metadata = SQLITE_BIND_START + 3

        let serializedObject = connection.database.objectSerializer(collection, key, object) as NSData
        let serializedMetadata = NSData()

        sqlite3_bind_text(statement, bind_idx_collection, collection, collection.length, SQLITE_STATIC)
        sqlite3_bind_text(statement, bind_idx_key, key, key.length, SQLITE_STATIC)
        sqlite3_bind_blob(statement, bind_idx_data,
                          serializedObject.bytes, Int32(serializedObject.length), SQLITE_STATIC);
        sqlite3_bind_blob(statement, bind_idx_metadata,
                          serializedMetadata.bytes, Int32(serializedMetadata.length), SQLITE_STATIC);

        let status = sqlite3_step(statement);
        if status != SQLITE_DONE {
            Daytabase.log.error("Error executing 'insertForRowidStatement': \(status) \(daytabase_errmsg(self.connection.db)) key(\(key))")
            return false
        }
        let _ = sqlite3_last_insert_rowid(connection.db);
        return true
    }

    func update(object: Any, forKey key: String, inCollection collection: String = "") -> Bool {
        guard let statement = connection.database.updateAllForRowidStatement else { return false }

        defer {
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }

        let rowid = self.rowid(forKey: key, inCollection: collection)

        let bind_idx_data     = SQLITE_BIND_START + 0
        let bind_idx_metadata = SQLITE_BIND_START + 1
        let bind_idx_rowid    = SQLITE_BIND_START + 2

        let serializedObject = connection.database.objectSerializer(collection, key, object) as NSData
        let serializedMetadata = NSData()

        sqlite3_bind_blob(statement, bind_idx_data,
                          serializedObject.bytes, Int32(serializedObject.length), SQLITE_STATIC);
        sqlite3_bind_blob(statement, bind_idx_metadata,
                          serializedMetadata.bytes, Int32(serializedMetadata.length), SQLITE_STATIC);
        sqlite3_bind_int64(statement, bind_idx_rowid, sqlite3_int64(rowid));
        sqlite3_bind_blob(statement, bind_idx_data,
                          serializedObject.bytes, Int32(serializedObject.length), SQLITE_STATIC);
        sqlite3_bind_blob(statement, bind_idx_metadata,
                          serializedMetadata.bytes, Int32(serializedMetadata.length), SQLITE_STATIC);

        let status = sqlite3_step(statement);
        if status != SQLITE_DONE {
            Daytabase.log.error("Error executing 'updateAllForRowidStatement': \(status) \(daytabase_errmsg(self.connection.db)) key(\(key))")
            return false
        }
        let _ = sqlite3_last_insert_rowid(connection.db);
        return true
    }
}
