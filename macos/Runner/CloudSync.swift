import CloudKit
import FlutterMacOS
import Foundation

final class CloudSyncHandler {
  private static let wordRecordType = "WordCard"
  private static let settingsRecordType = "AppSettings"
  private static let settingsRecordName = "app_settings"
  private static let modifyBatchLimit = 400

  let containerId: String
  private lazy var database: CKDatabase = {
    let container = CKContainer(identifier: containerId)
    return container.privateCloudDatabase
  }()

  init(containerId: String) {
    self.containerId = containerId
  }

  func pushChanges(records: [[String: Any]], completion: @escaping (Result<Void, Error>) -> Void) {
    pushChangesBatch(records: records, startIndex: 0, completion: completion)
  }

  private func pushChangesBatch(records: [[String: Any]],
                                startIndex: Int,
                                completion: @escaping (Result<Void, Error>) -> Void) {
    guard startIndex < records.count else {
      completion(.success(()))
      return
    }

    let endIndex = min(startIndex + Self.modifyBatchLimit, records.count)
    let batch = Array(records[startIndex..<endIndex])
    var ckRecords: [CKRecord] = []
    var tempFiles: [URL] = []

    for record in batch {
      guard let id = record["id"] as? String else { continue }
      let recordId = CKRecord.ID(recordName: id)
      let ckRecord = CKRecord(recordType: Self.wordRecordType, recordID: recordId)

      ckRecord["word"] = record["word"] as? NSString ?? ""
      ckRecord["meaning"] = record["meaning"] as? NSString ?? ""
      ckRecord["partOfSpeech"] = record["partOfSpeech"] as? NSString ?? ""

      if let sentences = record["sentences"] as? [String] {
        ckRecord["sentences"] = sentences as NSArray
      }

      if let schedule = record["reviewSchedule"] as? [Int] {
        ckRecord["reviewSchedule"] = schedule.map { NSNumber(value: $0) } as NSArray
      }

      if let nextReviewIndex = record["nextReviewIndex"] as? Int {
        ckRecord["nextReviewIndex"] = NSNumber(value: nextReviewIndex)
      }

      if let createdAt = Self.dateFromMillis(record["createdAt"]) {
        ckRecord["createdAt"] = createdAt as NSDate
      }
      if let updatedAt = Self.dateFromMillis(record["updatedAt"]) {
        ckRecord["updatedAt"] = updatedAt as NSDate
      }
      if let nextReviewDate = Self.dateFromMillis(record["nextReviewDate"]) {
        ckRecord["nextReviewDate"] = nextReviewDate as NSDate
      }

      if let history = record["history"] as? [Int] {
        let dates = history.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
        ckRecord["history"] = dates as NSArray
      }

      let isDeleted = record["isDeleted"] as? Bool ?? false
      ckRecord["isDeleted"] = NSNumber(value: isDeleted)

      let imageValue = record["imageBytes"]
      if let bytes = imageValue as? FlutterStandardTypedData {
        let data = bytes.data
        let tempUrl = FileManager.default.temporaryDirectory
          .appendingPathComponent("\(UUID().uuidString).jpg")
        do {
          try data.write(to: tempUrl)
          ckRecord["image"] = CKAsset(fileURL: tempUrl)
          tempFiles.append(tempUrl)
        } catch {
          // Ignore image if write fails
        }
      } else {
        ckRecord["image"] = nil
      }

      ckRecords.append(ckRecord)
    }

    let operation = CKModifyRecordsOperation(recordsToSave: ckRecords, recordIDsToDelete: nil)
    operation.savePolicy = .changedKeys
    operation.modifyRecordsResultBlock = { result in
      for url in tempFiles {
        try? FileManager.default.removeItem(at: url)
      }
      switch result {
      case .success:
        self.pushChangesBatch(records: records, startIndex: endIndex, completion: completion)
      case .failure(let error):
        NSLog("CloudSync pushChanges failed: %@", String(describing: error))
        completion(.failure(error))
      }
    }

    database.add(operation)
  }

  func fetchChanges(since: Date, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
    let predicate = NSPredicate(format: "updatedAt > %@", since as NSDate)
    let query = CKQuery(recordType: Self.wordRecordType, predicate: predicate)
    query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

    var allRecords: [[String: Any]] = []
    var recordError: Error?
    let operation = CKQueryOperation(query: query)
    operation.recordMatchedBlock = { _, result in
      switch result {
      case .success(let record):
        allRecords.append(Self.mapRecord(record))
      case .failure(let error):
        if recordError == nil {
          recordError = error
        }
      }
    }
    operation.queryResultBlock = { result in
      if let error = recordError {
        NSLog("CloudSync fetchChanges record error: %@", String(describing: error))
        completion(.failure(error))
        return
      }
      switch result {
      case .success(let cursor):
        if let cursor = cursor {
          self.fetchWithCursor(cursor, accumulator: allRecords, completion: completion)
        } else {
          completion(.success(allRecords))
        }
      case .failure(let error):
        NSLog("CloudSync fetchChanges failed: %@", String(describing: error))
        completion(.failure(error))
      }
    }
    database.add(operation)
  }

  func pushSettings(settings: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
    let recordId = CKRecord.ID(recordName: Self.settingsRecordName)
    database.fetch(withRecordID: recordId) { existingRecord, error in
      if let ckError = error as? CKError, ckError.code != .unknownItem {
        NSLog("CloudSync pushSettings fetch failed: %@", String(describing: ckError))
        completion(.failure(ckError))
        return
      }
      if let error = error, !(error is CKError) {
        NSLog("CloudSync pushSettings fetch failed: %@", String(describing: error))
        completion(.failure(error))
        return
      }

      let record = existingRecord ?? CKRecord(
        recordType: Self.settingsRecordType,
        recordID: recordId
      )
      Self.applySettings(settings, to: record)

      let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
      operation.savePolicy = .changedKeys
      operation.modifyRecordsResultBlock = { result in
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          NSLog("CloudSync pushSettings failed: %@", String(describing: error))
          completion(.failure(error))
        }
      }

      self.database.add(operation)
    }
  }

  func fetchSettings(completion: @escaping (Result<[String: Any]?, Error>) -> Void) {
    let recordId = CKRecord.ID(recordName: Self.settingsRecordName)
    database.fetch(withRecordID: recordId) { record, error in
      if let ckError = error as? CKError, ckError.code == .unknownItem {
        completion(.success(nil))
        return
      }
      if let error = error {
        NSLog("CloudSync fetchSettings failed: %@", String(describing: error))
        completion(.failure(error))
        return
      }
      guard let record = record else {
        completion(.success(nil))
        return
      }
      completion(.success(Self.mapSettingsRecord(record)))
    }
  }

  private func fetchWithCursor(_ cursor: CKQueryOperation.Cursor,
                               accumulator: [[String: Any]],
                               completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
    var allRecords = accumulator
    var recordError: Error?
    let operation = CKQueryOperation(cursor: cursor)
    operation.recordMatchedBlock = { _, result in
      switch result {
      case .success(let record):
        allRecords.append(Self.mapRecord(record))
      case .failure(let error):
        if recordError == nil {
          recordError = error
        }
      }
    }
    operation.queryResultBlock = { result in
      if let error = recordError {
        NSLog("CloudSync fetchWithCursor record error: %@", String(describing: error))
        completion(.failure(error))
        return
      }
      switch result {
      case .success(let nextCursor):
        if let nextCursor = nextCursor {
          self.fetchWithCursor(nextCursor, accumulator: allRecords, completion: completion)
        } else {
          completion(.success(allRecords))
        }
      case .failure(let error):
        NSLog("CloudSync fetchWithCursor failed: %@", String(describing: error))
        completion(.failure(error))
      }
    }
    database.add(operation)
  }

  private static func dateFromMillis(_ value: Any?) -> Date? {
    if let ms = value as? Int {
      return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }
    if let ms = value as? Int64 {
      return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }
    return nil
  }

  private static func intFromAny(_ value: Any?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private static func boolFromAny(_ value: Any?) -> Bool? {
    if let boolValue = value as? Bool {
      return boolValue
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  private static func applySettings(_ settings: [String: Any], to record: CKRecord) {
    record["reminderMinutes"] = NSNumber(value: Self.intFromAny(settings["reminderMinutes"]) ?? 20 * 60)
    record["showImages"] = NSNumber(value: Self.boolFromAny(settings["showImages"]) ?? true)
    record["reminderEnabled"] = NSNumber(value: Self.boolFromAny(settings["reminderEnabled"]) ?? true)
    record["syncEnabled"] = NSNumber(value: Self.boolFromAny(settings["syncEnabled"]) ?? true)
    record["syncIntervalSeconds"] = NSNumber(value: Self.intFromAny(settings["syncIntervalSeconds"]) ?? 60)
    record["updatedAt"] = (Self.dateFromMillis(settings["updatedAt"]) ?? Date()) as NSDate
  }

  private static func mapRecord(_ record: CKRecord) -> [String: Any] {
    var map: [String: Any] = [
      "id": record.recordID.recordName,
      "word": record["word"] as? String ?? "",
      "meaning": record["meaning"] as? String ?? "",
      "partOfSpeech": record["partOfSpeech"] as? String ?? "",
      "sentences": record["sentences"] as? [String] ?? [],
      "reviewSchedule": (record["reviewSchedule"] as? [NSNumber])?.map { $0.intValue } ?? [],
      "nextReviewIndex": (record["nextReviewIndex"] as? NSNumber)?.intValue ?? 0,
      "isDeleted": (record["isDeleted"] as? NSNumber)?.boolValue ?? false,
    ]

    if let createdAt = record["createdAt"] as? Date {
      map["createdAt"] = Int(createdAt.timeIntervalSince1970 * 1000.0)
    }
    if let updatedAt = record["updatedAt"] as? Date {
      map["updatedAt"] = Int(updatedAt.timeIntervalSince1970 * 1000.0)
    }
    if let nextReviewDate = record["nextReviewDate"] as? Date {
      map["nextReviewDate"] = Int(nextReviewDate.timeIntervalSince1970 * 1000.0)
    }
    if let history = record["history"] as? [Date] {
      map["history"] = history.map { Int($0.timeIntervalSince1970 * 1000.0) }
    }

    if let asset = record["image"] as? CKAsset,
       let url = asset.fileURL,
       let data = try? Data(contentsOf: url) {
      map["imageBytes"] = FlutterStandardTypedData(bytes: data)
    }

    return map
  }

  private static func mapSettingsRecord(_ record: CKRecord) -> [String: Any] {
    var map: [String: Any] = [
      "reminderMinutes": (record["reminderMinutes"] as? NSNumber)?.intValue ?? 20 * 60,
      "showImages": (record["showImages"] as? NSNumber)?.boolValue ?? true,
      "reminderEnabled": (record["reminderEnabled"] as? NSNumber)?.boolValue ?? true,
      "syncEnabled": (record["syncEnabled"] as? NSNumber)?.boolValue ?? true,
      "syncIntervalSeconds": (record["syncIntervalSeconds"] as? NSNumber)?.intValue ?? 60
    ]

    if let updatedAt = record["updatedAt"] as? Date {
      map["updatedAt"] = Int(updatedAt.timeIntervalSince1970 * 1000.0)
    }

    return map
  }
}
