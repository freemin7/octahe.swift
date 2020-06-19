//
//  target.swift
//  
//
//  Created by Kevin Carter on 6/19/20.
//

import Foundation


enum TargetStates {
    case available, failed
}


var targetRecords: [String: TargetRecord] = [:]


class TargetRecord {
    let target: typeTarget
    let conn: Execution
    var state = TargetStates.available
    var failedTask: String?
    var failedStep: Int?

    init(target: typeTarget, args: ConfigParse, options: octaheCLI.Options) throws {
        self.target = target
        if target.name == "localhost" {
            self.conn = ExecuteLocal(cliParameters: options, processParams: args)
        } else {
            self.conn = ExecuteSSH(cliParameters: options, processParams: args)

            let targetComponents = target.to.components(separatedBy: "@")
            if targetComponents.count > 1 {
                conn.user = targetComponents.first!
            }
            let serverPort = targetComponents.last!.components(separatedBy: ":")
            if serverPort.count > 1 {
                conn.server = serverPort.first!
                conn.port = serverPort.last!
            } else {
                conn.server = serverPort.first!
            }
            if !conn.port.isInt {
                throw RouterError.FailedConnection(
                    message: "Connection never attempted because the port is not an integer.",
                    targetData: target
                )
            }
        }
        self.conn.environment = args.octaheArgs
    }
}


class TargetOperations {
    let maxConcurrentOperationCount: Int

    init(connectionQuota: Int) {
        maxConcurrentOperationCount = connectionQuota
    }

    lazy var nodesInProgress: [IndexPath: Operation] = [:]
    lazy var nodeQueue: OperationQueue = {
    var queue = OperationQueue()
        queue.name = "Node queue"
        queue.maxConcurrentOperationCount = self.maxConcurrentOperationCount
        return queue
    }()
}


class TargetOperation: Operation {
    let targetRecord: TargetRecord
    let target: typeTarget
    let args: ConfigParse
    let options: octaheCLI.Options
    let task: TaskRecord
    let taskIndex: Int

    init(target: typeTarget, args: ConfigParse, options: octaheCLI.Options, taskIndex: Int) {
        self.target = target
        self.args = args
        self.options = options
        self.taskIndex = taskIndex
        self.task = taskRecords[taskIndex]!

        if let targetRecordsLookup = targetRecords[target.name] {
            self.targetRecord = targetRecordsLookup
        } else {
            let targetRecordsLookup = try! TargetRecord(target: target, args: args, options: options)
            targetRecords[target.name] = targetRecordsLookup
            self.targetRecord = targetRecords[target.name]!
        }
    }

    override func main() {
        if isCancelled {
            return
        }
        self.task.state = .running
        let conn = targetRecord.conn
        logger.debug("Executing: \(task.task)")
        do {
            if task.taskItem.execute != nil {
                if task.task == "SHELL" {
                    conn.shell = task.taskItem.execute!
                } else {
                    try conn.run(execute: task.taskItem.execute!)
                }
            } else if task.taskItem.destination != nil && task.taskItem.location != nil {
                try targetRecord.conn.copy(
                    base: args.configDirURL,
                    to: task.taskItem.destination!,
                    fromFiles: task.taskItem.location!
                )
            }
        } catch {
            task.state = .degraded
            self.targetRecord.failedStep = self.taskIndex
            self.targetRecord.failedTask = "\(error)"
            self.targetRecord.state = .failed
        }
        if task.state != .degraded {
            task.state = .success
        }

    }
}