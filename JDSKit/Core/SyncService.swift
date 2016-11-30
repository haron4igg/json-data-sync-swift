//
//  SyncService.swift
//  JDSKit
//
//  Created by Igor Reshetnikov on 3/1/16.
//  Copyright © 2016 RailsReactor. All rights reserved.
//

import Foundation
import PromiseKit
import CocoaLumberjack
import When

public enum SyncError: Error {
    case checkForUpdates(Date)
}

public typealias SyncInfo = [String]

private let ZeroDate = Date(timeIntervalSince1970: 0)
private let EventKey = String(describing: Event.self)

open class AbstractSyncService: CoreService {
    
    open var liteSyncEnabled = false
    
    // *************************** Override *******************************
    // if you want to split some update info between different users or something...
    
    open func filterIDForEntityKey(_ key: String) -> String? {
        return nil
    }
    
    open func shouldSyncEntityOfType(_ managedEntityKey: String, lastUpdateDate: Date?) -> Bool {
        return true
    }
    
    // *************************************************************************
    
    open var lastSyncDate = ZeroDate
    open var lastSuccessSyncDate = ZeroDate

    open lazy var updateInfoGateway: UpdateInfoGateway = {
        return UpdateInfoGateway(self.localManager)
    } ()
    
    internal func entitiesToSync() -> [String] {
        let extracted = ExtractAllReps(CDManagedEntity.self)
        return extracted.flatMap {
            let name = ($0 as! CDManagedEntity.Type).entityName
            if name == "ManagedEntity" {
                return nil
            }
            return name
        }
    }

    internal func checkForUpdates(_ eventSyncDate: Date) -> PromiseKit.Promise<SyncInfo> {
        DDLogDebug("Checking for updates... \(eventSyncDate)")
        let predicate = NSComparisonPredicate(format: "created_at_gt == %@", eventSyncDate.toSystemString());
        return self.remoteManager.loadEntities(Event.self, filters: [predicate], include: nil, fields: liteSyncEnabled ? ["relatedEntityName", "relatedEntityId", "action"] : nil).thenInBGContext { (events: [Event]) -> SyncInfo in
            var itemsToSync = Set<String>()
            let requiredItems = Set(self.entitiesToSync())
            
            for event in events {
                guard let entityName = event.relatedEntityName else { continue }
                
                if let date = event.updateDate, self.lastSyncDate.compare(date) == ComparisonResult.orderedAscending {
                    self.lastSyncDate = date
                }
                
                if let id = event.relatedEntityId, event.action == Action.Deleted {
                    do {
                        try AbstractRegistryService.mainRegistryService.entityServiceByKey(entityName).entityGatway()?.deleteEntityWithID(id)
                        DDLogDebug("Deleted \(entityName) with id: \(id)")
                    } catch {
                    }
                } else if requiredItems.contains(entityName) {
                    if !itemsToSync.contains(entityName) {
                        DDLogDebug("Will sync: \(entityName)...")
                    }
                    itemsToSync.insert(event.relatedEntityName!)
                }
            }
            
            return Array(itemsToSync)
        }
    }
    
    internal func syncInternal() -> When.Promise<Void> {
        return self.runOnBackgroundContext { () -> SyncInfo in
            
            if let eventSyncInfo = try self.updateInfoGateway.updateInfoForKey(EventKey, filterID: self.filterIDForEntityKey(EventKey)) {
                throw SyncError.CheckForUpdates(eventSyncInfo.updateDate!)
            } else {
                DDLogDebug("Going to sync at first time...")
                return self.entitiesToSync()
            }
        }.recover(on: dispatch_get_global_queue(Int(QOS_CLASS_DEFAULT.rawValue), 0)) { error -> PromiseKit.Promise<SyncInfo> in
            switch error {
            case SyncError.CheckForUpdates(let syncInfo):
                return self.checkForUpdates(syncInfo)
            default:
                throw error
            }
        }.thenInBGContext { updateEntitiesKeys -> [PromiseKit.Promise<NSDate>] in
            var syncPromises = [Promise<NSDate>]()

            for entityKey in updateEntitiesKeys {
                let service = AbstractRegistryService.mainRegistryService.entityServiceByKey(entityKey)
                let filter = self.filterIDForEntityKey(entityKey)
                let syncDate = try self.updateInfoGateway.updateInfoForKey(entityKey, filterID: filter)?.updateDate ?? ZeroDate
                
                if !self.shouldSyncEntityOfType(entityKey, lastUpdateDate: syncDate) {
                    continue
                }
                
                let syncPromise = service.syncEntityDelta(syncDate).thenInBGContext { _ -> NSDate in
                    let updateInfo: CDUpdateInfo = try self.updateInfoGateway.updateInfoForKey(entityKey, filterID: filter, createIfNeed: true)!
                    
                    var finalSyncDate = ZeroDate
                    if self.lastSyncDate == ZeroDate {
                        let topMostEntity: ManagedEntity? = try service.entityGatway()?.fetchEntities(nil, sortDescriptors: ["-updateDate"].sortDescriptors()).first
                        finalSyncDate = topMostEntity?.updateDate ?? syncDate
                    } else {
                        finalSyncDate = self.lastSyncDate
                    }
                    updateInfo.updateDate = finalSyncDate
                    return finalSyncDate
                }
                syncPromises.append(syncPromise)
            }
            
            return syncPromises
        }.then(on: .global()) { promises in
            return when(fulfilled: promises)
        }.thenInBGContext { dates -> Void in
            let eventSyncInfo = try self.updateInfoGateway.updateInfoForKey(EventKey, filterID: self.filterIDForEntityKey(EventKey), createIfNeed: true)
            if let eventSync = eventSyncInfo?.updateDate {
                if self.lastSyncDate == ZeroDate {
                    var latestDate = ZeroDate
                    
                    dates.forEach {
                        if latestDate.compare($0) == NSComparisonResult.OrderedAscending {
                            latestDate = $0
                        }
                    }
                    self.lastSyncDate = latestDate.timeIntervalSince1970 > eventSync.timeIntervalSince1970 ? latestDate : eventSync
                }
            }
            
            self.lastSuccessSyncDate = self.lastSyncDate
            eventSyncInfo?.updateDate = self.lastSyncDate
        }.always (on: dispatch_get_global_queue(Int(QOS_CLASS_DEFAULT.rawValue), 0)) {
            self.localManager.saveSyncSafe()
        }
    }
    
    open func sync() -> PromiseKit.Promise<Void> {
        return DispatchQueue.global().promise {}.then(on: .global()) { _ in
            if self.trySync() {
                return self.syncInternal().always {_ in
                    self.endSync()
                }
            } else {
                self.waitForSync()
                return Promise(value:())
            }
        }
    }
}
